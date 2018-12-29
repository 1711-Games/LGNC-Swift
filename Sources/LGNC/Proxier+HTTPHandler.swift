import Foundation
import LGNCore
import LGNP
import LGNS
import NIO
import NIOHTTP1

fileprivate func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
    var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
    let connectionHeaders: [String] = head.headers[canonicalForm: "connection"].map { $0.lowercased() }
    
    if !connectionHeaders.contains("keep-alive") && !connectionHeaders.contains("close") {
        // the user hasn't pre-set either 'keep-alive' or 'close', so we might need to add headers
        
        switch (request.isKeepAlive, request.version.major, request.version.minor) {
        case (true, 1, 0):
            // HTTP/1.0 and the request has 'Connection: keep-alive', we should mirror that
            head.headers.add(name: "Connection", value: "keep-alive")
        case (false, 1, let n) where n >= 1:
            // HTTP/1.1 (or treated as such) and the request has 'Connection: close', we should mirror that
            head.headers.add(name: "Connection", value: "close")
        default:
            // we should match the default or are dealing with some HTTP that we don't support, let's leave as is
            ()
        }
    }
    return head
}

internal extension LGNC.Proxier {
    internal final class HTTPHandler: ChannelInboundHandler {
        public typealias InboundIn = HTTPServerRequestPart
        public typealias OutboundOut = HTTPServerResponsePart
        
        private enum State {
            case idle
            case waitingForRequestBody
            case sendingResponse
            
            mutating func requestReceived() {
                precondition(self == .idle, "Invalid state for request received: \(self)")
                self = .waitingForRequestBody
            }
            
            mutating func requestComplete() {
                precondition(self == .waitingForRequestBody, "Invalid state for request complete: \(self)")
                self = .sendingResponse
            }
            
            mutating func responseComplete() {
                precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
                self = .idle
            }
        }
        
        private static let regex = Regex(pattern: "^\\/([\\w\\d_]+)\\/([\\w\\d_]+)\\/([\\w\\d_]+)$")!
        
        private var buffer: ByteBuffer!
        private var bodyBuffer: ByteBuffer?
        private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
        private var state = State.idle
        private var infoSavedRequestHead: HTTPRequestHead?
        private var infoSavedBodyBytes: Int = 0
        private var keepAlive: Bool = false
        
        private var uuid: UUID!
        private var profiler: LGNCore.Profiler!

        private var serviceName: String?
        private var nodeName: String?
        private var contractName: String?
        private var port: Int!
        
        private var errored: Bool = false
        
        private let client: LGNS.Client
        private let registry: LGNC.ServicesRegistry
        private let hostFormat: String
        
        public init(
            client: LGNS.Client,
            registry: LGNC.ServicesRegistry,
            hostFormat: String
        ) {
            self.client = client
            self.registry = registry
            self.hostFormat = hostFormat
        }
        
        public func handlerAdded(ctx: ChannelHandlerContext) {
            let message: StaticString = "Hello World!"
            self.buffer = ctx.channel.allocator.buffer(capacity: message.count)
            self.buffer.write(staticString: message)
        }
        
        public func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
            switch event {
            case let evt as ChannelEvent where evt == ChannelEvent.inputClosed:
                // The remote peer half-closed the channel. At this time, any
                // outstanding response will now get the channel closed, and
                // if we are idle or waiting for a request body to finish we
                // will close the channel immediately.
                switch self.state {
                case .idle, .waitingForRequestBody:
                    ctx.close(promise: nil)
                case .sendingResponse:
                    self.keepAlive = false
                }
            default:
                ctx.fireUserInboundEventTriggered(event)
            }
        }
        
        public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
            let reqPart = self.unwrapInboundIn(data)
            if let handler = self.handler {
                handler(ctx, reqPart)
                return
            }
            
            switch reqPart {
            case .head(let request):
                self.bodyBuffer = nil
                
                self.uuid = UUID()
                self.profiler = LGNCore.Profiler.begin()

                self.keepAlive = request.isKeepAlive
                
                let matches = HTTPHandler.regex.matches(request.uri)
                if request.method == .POST && matches.count == 1 && matches[0].captureGroups.count == 3 {
                    self.serviceName = matches[0].captureGroups[0]
                    self.nodeName = matches[0].captureGroups[1]
                    self.contractName = matches[0].captureGroups[2]
                    
                    self.handler = self.defaultHandler
                } else {
                    dump(request.headers[canonicalForm: "Cookie"])
                    self.handler = { ctx, req in self.handleJustWrite(ctx: ctx, request: req, statusCode: .notImplemented, string: "501 Not Implemented") }
                }
                self.handler!(ctx, reqPart)
            case .body:
                break
            case .end:
                self.state.requestComplete()
                let content = HTTPServerResponsePart.body(.byteBuffer(self.buffer!.slice()))
                ctx.write(self.wrapOutboundOut(content), promise: nil)
                self.completeResponse(ctx, trailers: nil, promise: nil)
            }
        }
        
        private func completeResponse(_ ctx: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
            self.state.responseComplete()
            
            let promise = self.keepAlive ? promise : (promise ?? ctx.eventLoop.newPromise())
            if !self.keepAlive {
                promise!.futureResult.whenComplete { ctx.close(promise: nil) }
            }
            self.handler = nil
            
            ctx.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
        }
        
        private func handleJustWrite(
            ctx: ChannelHandlerContext,
            request: HTTPServerRequestPart,
            statusCode: HTTPResponseStatus = .ok,
            string: String,
            trailer: (String, String)? = nil,
            delay: TimeAmount = .nanoseconds(0)
        ) {
            switch request {
            case .head(let request):
                self.state.requestReceived()
                ctx.writeAndFlush(self.wrapOutboundOut(.head(httpResponseHead(request: request, status: statusCode))), promise: nil)
            case .body(buffer: _):
                ()
            case .end:
                self.state.requestComplete()

                var buf = ctx.channel.allocator.buffer(capacity: string.utf8.count)
                buf.write(string: string)
                ctx.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
                var trailers: HTTPHeaders? = nil
                if let trailer = trailer {
                    trailers = HTTPHeaders()
                    trailers?.add(name: trailer.0, value: trailer.1)
                }
                
                self.completeResponse(ctx, trailers: trailers, promise: nil)
            }
        }
        
        private func defaultHandler(_ ctx: ChannelHandlerContext, _ request: HTTPServerRequestPart) {
            switch request {
            case .head(let req):
                self.infoSavedRequestHead = req
                self.infoSavedBodyBytes = 0
                
                guard let serviceName = self.serviceName else {
                    LGNC.log("No service provided", prefix: self.uuid)
                    self.handler = { _ctx, _req in self.handleJustWrite(ctx: _ctx, request: _req, statusCode: .badRequest, string: "400 Bad Request") }
                    self.handler!(ctx, request)
                    return
                }
                guard let _ = self.nodeName else {
                    LGNC.log("No node provided for service '\(serviceName)'", prefix: self.uuid)
                    self.handler = { _ctx, _req in self.handleJustWrite(ctx: _ctx, request: _req, statusCode: .badRequest, string: "400 Bad Request") }
                    self.handler!(ctx, request)
                    return
                }
                guard let contractName = self.contractName else {
                    LGNC.log("Contract name not provided for service '\(serviceName)'", prefix: self.uuid)
                    self.handler = { _ctx, _req in self.handleJustWrite(ctx: _ctx, request: _req, statusCode: .badRequest, string: "400 Bad Request") }
                    self.handler!(ctx, request)
                    return
                }
                guard let service = self.registry[serviceName] else {
                    LGNC.log("Service '\(serviceName)' not found", prefix: uuid)
                    self.handler = { _ctx, _req in self.handleJustWrite(ctx: _ctx, request: _req, statusCode: .badRequest, string: "400 Bad Request") }
                    self.handler!(ctx, request)
                    return
                }
                self.port = service.port
                guard let contractInfo = service.contracts[contractName] else {
                    LGNC.log("Contract '\(contractName)' not found in service '\(serviceName)'", prefix: uuid)
                    self.handler = { _ctx, _req in self.handleJustWrite(ctx: _ctx, request: _req, statusCode: .badRequest, string: "400 Bad Request") }
                    self.handler!(ctx, request)
                    return
                }
                guard contractInfo == .Public else {
                    LGNC.log("Contract '\(contractName)' is not public", prefix: uuid)
                    self.handler = { _ctx, _req in self.handleJustWrite(ctx: _ctx, request: _req, statusCode: .badRequest, string: "400 Bad Request") }
                    self.handler!(ctx, request)
                    return
                }
                
                self.state.requestReceived()
            case .body(buffer: var buf):
                self.infoSavedBodyBytes += buf.readableBytes
                if self.bodyBuffer == nil {
                    self.bodyBuffer = buf
                } else {
                    self.bodyBuffer?.write(buffer: &buf)
                }
            case .end:
                guard !self.errored else {
                    return
                }
                
                self.state.requestComplete()
                
                self.buffer.clear()
                
                var buffer = self.bodyBuffer
                if buffer != nil, let bytes = buffer!.readBytes(length: buffer!.readableBytes) {
                    let future = self.client.request(
                        at: .ip(
                            host: self.hostFormat
                                .replacingOccurrences(of: "{NODE}", with: self.nodeName!)
                                .replacingOccurrences(of: "{SERVICE}", with: self.serviceName!.lowercased()),
                            port: self.port
                        ),
                        with: LGNP.Message(
                            URI: self.contractName!,
                            payload: bytes,
                            meta: LGNC.getMeta(
                                clientAddr: ctx.channel.remoteAddrString,
                                userAgent: self.infoSavedRequestHead!.headers["User-Agent"].first ?? ""
                            ),
                            salt: self.client.cryptor.salt.bytes,
                            controlBitmask: self.client.controlBitmask,
                            uuid: self.uuid
                        ),
                        on: ctx.eventLoop
                    )
                    future.whenSuccess { message in
                        self.buffer.write(bytes: message.payload)
                        self.finishRequest(
                            ctx: ctx,
                            status: .ok,
                            additionalHeaders: [
                                "X-LGNC-UUID": message.uuid.string,
                            ]
                        )
                        LGNC.log(
                            "Contract '\(self.serviceName!)::\(self.contractName!)' execution took \(self.profiler.end().rounded(toPlaces: 5)) s",
                            prefix: self.uuid.string
                        )
                    }
                    future.whenFailure { error in
                        LGNCore.log("There was an error while proxying to service: \(error)")
                        if case NIO.ChannelError.connectFailed(_) = error {
                            self.buffer.write(string: "404 Not Found")
                            self.finishRequest(ctx: ctx, status: .notFound)
                        } else {
                            dump(error)
                            self.buffer.write(string: "400 Bad Request")
                            self.finishRequest(ctx: ctx, status: .badRequest)
                        }
                    }
                } else {
                    LGNC.log("Empty payload", prefix: uuid)
                    self.buffer.write(string: "400 Bad Request")
                    self.finishRequest(ctx: ctx, status: .badRequest)
                }
            }
        }
        
        private func finishRequest(
            ctx: ChannelHandlerContext,
            status: HTTPResponseStatus,
            additionalHeaders: [String: String] = [:]
        ) {
            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "\(self.buffer.readableBytes)")
            additionalHeaders.forEach {
                headers.add(name: $0.key, value: $0.value)
            }
            ctx.write(self.wrapOutboundOut(.head(httpResponseHead(request: self.infoSavedRequestHead!, status: status, headers: headers))), promise: nil)
            ctx.write(self.wrapOutboundOut(.body(.byteBuffer(self.buffer))), promise: nil)
            self.completeResponse(ctx, trailers: nil, promise: nil)
        }
    }
}
