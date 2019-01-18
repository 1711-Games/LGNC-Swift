import Foundation
import LGNCore
import LGNP
import LGNS
import NIO
import NIOHTTP1
import LGNPContenter

public extension LGNC {
    public struct HTTP {
        public typealias Resolver = (Request) -> Future<Bytes>
    }
}

public extension LGNC.HTTP {
    public enum ContentType: String {
        case PlainText = "text/plain"
        case XML = "application/xml"
        case JSON = "application/json"
        case MsgPack = "application/msgpack"
    }

    public struct Request {
        public let URI: String
        public let headers: HTTPHeaders
        public let remoteAddr: String
        public let body: Bytes
        public let uuid: UUID
        public let contentType: ContentType
        public let method: HTTPMethod
        public let eventLoop: EventLoop
    }
}

public extension LGNC.HTTP {
    public class Server: Shutdownable {
        public typealias BindTo = LGNS.Address

        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount
        private let eventLoopGroup: EventLoopGroup
        private var bootstrap: ServerBootstrap!

        private var channel: Channel!

        public required init(
            eventLoopGroup: EventLoopGroup,
            readTimeout: Time = .minutes(1),
            writeTimeout: Time = .minutes(1),
            resolver: @escaping Resolver
        ) {
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
            self.eventLoopGroup = eventLoopGroup

            self.bootstrap = ServerBootstrap(group: self.eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).then {
                    channel.pipeline.add(handler: Handler(resolver: resolver))
                }}

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 64)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

            SignalObserver.add(self)
        }

        public func shutdown(promise: PromiseVoid) {
            LGNCore.log("HTTP Server: shutting down")
            self.channel.close(promise: promise)
            LGNCore.log("HTTP Server: goodbye")
        }

        public func serve(at target: BindTo, promise: PromiseVoid? = nil) throws {
            self.channel = try self.bootstrap.bind(to: target).wait()

            promise?.succeed(result: ())

            try self.channel.closeFuture.wait()
        }
    }
}

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

internal extension LGNC.HTTP {
    internal final class Handler: ChannelInboundHandler {
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

        private var buffer: ByteBuffer!
        private var bodyBuffer: ByteBuffer?
        private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
        private var state = State.idle
        private var infoSavedRequestHead: HTTPRequestHead?
        private var infoSavedBodyBytes: Int = 0
        private var keepAlive: Bool = false

        private var uuid: UUID!
        private var profiler: LGNCore.Profiler!

        private var errored: Bool = false

        private let resolver: Resolver

        public init(
            resolver: @escaping Resolver
        ) {
            self.resolver = resolver
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

                if [.POST, .GET].contains(request.method) {
                    self.handler = self.defaultHandler
                } else {
                    self.handler = { ctx, req in
                        self.handleJustWrite(
                            ctx: ctx,
                            request: req,
                            statusCode: .notImplemented,
                            string: "501 Not Implemented"
                        )
                    }
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

        private func sendBadRequest(message: String = "400 Bad Request", to ctx: ChannelHandlerContext) {
            LGNCore.log(message, prefix: uuid.string)
            self.buffer.write(string: message)
            self.finishRequest(ctx: ctx, status: .badRequest)
        }

        private func defaultHandler(_ ctx: ChannelHandlerContext, _ request: HTTPServerRequestPart) {
            switch request {
            case .head(let req):
                self.infoSavedRequestHead = req
                self.infoSavedBodyBytes = 0

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

                guard self.infoSavedRequestHead!.method == .POST else {
                    self.sendBadRequest(message: "400 Bad Request (POST method only)", to: ctx)
                    return
                }

                guard
                    let contentTypeString = self.infoSavedRequestHead!.headers["Content-Type"].first,
                    let contentType = ContentType(rawValue: contentTypeString.lowercased())
                else {
                    self.sendBadRequest(message: "400 Bad Request (Content-Type header missing)", to: ctx)
                    return
                }

                let uri = String(self.infoSavedRequestHead!.uri.dropFirst())
                let payloadBytes: Bytes
                if var buffer = self.bodyBuffer, let bytes = buffer.readBytes(length: buffer.readableBytes) {
                    payloadBytes = bytes
                } /*else if uri.contains("?"), let params = URLComponents(string: String(uri))?.queryItems {
                    let payloadDict = Dictionary(
                        uniqueKeysWithValues: params
                            .map { (param) -> (String, Any)? in
                                guard let value = param.value else {
                                    return nil
                                }
                                return (
                                    param.name,
                                    (value.isNumber ? (Int(value) ?? -1) : value) as Any
                                )
                            }
                            .compactMap { $0 }
                    )
                    do {
                        switch contentType {
                        case .MsgPack: payloadBytes = try payloadDict.getMsgPack()
                        case .JSON: payloadBytes = try payloadDict.getJSON()
                        default:
                            self.sendBadRequest(message: "400 Bad Request (Invalid Content-Type)", to: ctx)
                            return
                        }
                    } catch {
                        LGNCore.log("Error while packing query: \(error)", prefix: self.uuid.string)
                        self.sendBadRequest(message: "400 Bad Request (Invalid Content-Type)", to: ctx)
                        return
                    }
                } */else {
                    self.sendBadRequest(to: ctx)
                    return
                }

                let request = Request(
                    URI: uri,
                    headers: self.infoSavedRequestHead!.headers,
                    remoteAddr: ctx.channel.remoteAddrString,
                    body: payloadBytes,
                    uuid: self.uuid,
                    contentType: contentType,
                    method: self.infoSavedRequestHead!.method,
                    eventLoop: ctx.eventLoop
                )
                let future = self.resolver(request)
                future.whenComplete {
                    LGNCore.log(
                        "HTTP request '\(request.URI)' execution took \(self.profiler.end().rounded(toPlaces: 5)) s",
                        prefix: self.uuid.string
                    )
                }
                var headers = [
                    "LGNC-UUID": self.uuid.string,
                    "Server": "LGNC \(LGNC.VERSION)",
                ]
                future.whenSuccess { bytes in
                    self.buffer.write(bytes: bytes)
                    headers["Content-Type"] = request.contentType.rawValue
                    self.finishRequest(
                        ctx: ctx,
                        status: .ok,
                        additionalHeaders: headers
                    )
                }
                future.whenFailure { error in
                    LGNCore.log(
                        "There was an error while processing request '\(request.URI)': \(error)",
                        prefix: self.uuid.string
                    )
                    self.buffer.write(string: "500 Internal Server Error")
                    self.finishRequest(
                        ctx: ctx,
                        status: .internalServerError,
                        additionalHeaders: headers
                    )
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
