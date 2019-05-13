import Foundation
import LGNCore
import LGNP
import LGNPContenter
import LGNS
import NIO
import NIOHTTP1

public extension LGNC {
    struct HTTP {
        public typealias Resolver = (Request) -> Future<(body: Bytes, headers: [(name: String, value: String)])>
    }
}

public extension LGNC.HTTP {
    enum ContentType: String {
        case PlainText = "text/plain"
        case XML = "application/xml"
        case JSON = "application/json"
        case MsgPack = "application/msgpack"
    }

    struct Request {
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
    class Server: Shutdownable {
        public typealias BindTo = LGNS.Address

        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount
        private let eventLoopGroup: EventLoopGroup
        private var bootstrap: ServerBootstrap!
        private var logger: Logger = Logger(label: "LGNC.HTTP")

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

            bootstrap = ServerBootstrap(group: self.eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                        channel.pipeline.addHandler(Handler(resolver: resolver))
                } }

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 64)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

            SignalObserver.add(self)
        }

        public func shutdown(promise: PromiseVoid) {
            self.logger.info("HTTP Server: shutting down")
            channel.close(promise: promise)
            self.logger.info("HTTP Server: goodbye")
        }

        public func serve(at target: BindTo, promise: PromiseVoid? = nil) throws {
            channel = try bootstrap.bind(to: target).wait()

            promise?.succeed(())

            try channel.closeFuture.wait()
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
    final class Handler: ChannelInboundHandler {
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
        private var logger: Logger = Logger(label: "LGNC.HTTP.Handler")

        private var errored: Bool = false

        private let resolver: Resolver

        public init(
            resolver: @escaping Resolver
        ) {
            self.resolver = resolver
        }

        public func handlerAdded(context: ChannelHandlerContext) {
            let message: StaticString = "Hello World!"
            buffer = context.channel.allocator.buffer(capacity: message.utf8CodeUnitCount)
            buffer.writeStaticString(message)
        }

        public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            switch event {
            case let evt as ChannelEvent where evt == ChannelEvent.inputClosed:
                // The remote peer half-closed the channel. At this time, any
                // outstanding response will now get the channel closed, and
                // if we are idle or waiting for a request body to finish we
                // will close the channel immediately.
                switch state {
                case .idle, .waitingForRequestBody:
                    context.close(promise: nil)
                case .sendingResponse:
                    keepAlive = false
                }
            default:
                context.fireUserInboundEventTriggered(event)
            }
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let reqPart = unwrapInboundIn(data)
            if let handler = self.handler {
                handler(context, reqPart)
                return
            }

            switch reqPart {
            case let .head(request):
                bodyBuffer = nil

                self.uuid = UUID()
                self.logger[metadataKey: "UUID"] = "\(self.uuid.string)"
                self.profiler = LGNCore.Profiler.begin()

                keepAlive = request.isKeepAlive

                if [.POST, .GET].contains(request.method) {
                    handler = defaultHandler
                } else {
                    handler = { context, req in
                        self.handleJustWrite(
                            context: context,
                            request: req,
                            statusCode: .notImplemented,
                            string: "501 Not Implemented"
                        )
                    }
                }
                handler!(context, reqPart)
            case .body:
                break
            case .end:
                state.requestComplete()
                let content = HTTPServerResponsePart.body(.byteBuffer(buffer!.slice()))
                context.write(wrapOutboundOut(content), promise: nil)
                completeResponse(context, trailers: nil, promise: nil)
            }
        }

        private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
            state.responseComplete()

            let promise = keepAlive ? promise : (promise ?? context.eventLoop.makePromise())
            if !keepAlive {
                promise!.futureResult.whenComplete { _ in context.close(promise: nil) }
            }
            handler = nil

            context.writeAndFlush(wrapOutboundOut(.end(trailers)), promise: promise)
        }

        private func handleJustWrite(
            context: ChannelHandlerContext,
            request: HTTPServerRequestPart,
            statusCode: HTTPResponseStatus = .ok,
            string: String,
            trailer: (String, String)? = nil,
            delay _: TimeAmount = .nanoseconds(0)
        ) {
            switch request {
            case let .head(request):
                state.requestReceived()
                context.writeAndFlush(wrapOutboundOut(.head(httpResponseHead(request: request, status: statusCode))), promise: nil)
            case .body(buffer: _):
                ()
            case .end:
                state.requestComplete()

                var buf = context.channel.allocator.buffer(capacity: string.utf8.count)
                buf.writeString(string)
                context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
                var trailers: HTTPHeaders?
                if let trailer = trailer {
                    trailers = HTTPHeaders()
                    trailers?.add(name: trailer.0, value: trailer.1)
                }

                completeResponse(context, trailers: trailers, promise: nil)
            }
        }

        private func sendBadRequest(message: String = "400 Bad Request", to context: ChannelHandlerContext) {
            self.logger.debug("Bad request: \(message)")
            buffer.writeString(message)
            finishRequest(context: context, status: .badRequest)
        }

        private func defaultHandler(_ context: ChannelHandlerContext, _ request: HTTPServerRequestPart) {
            switch request {
            case let .head(req):
                infoSavedRequestHead = req
                infoSavedBodyBytes = 0

                state.requestReceived()
            case var .body(buffer: buf):
                infoSavedBodyBytes += buf.readableBytes
                if bodyBuffer == nil {
                    bodyBuffer = buf
                } else {
                    bodyBuffer?.writeBuffer(&buf)
                }
            case .end:
                guard !errored else {
                    return
                }

                self.state.requestComplete()

                self.buffer.clear()

                guard infoSavedRequestHead!.method == .POST else {
                    self.sendBadRequest(message: "400 Bad Request (POST method only)", to: context)
                    return
                }

                guard
                    let contentTypeString = self.infoSavedRequestHead!.headers["Content-Type"].first,
                    let contentType = ContentType(rawValue: contentTypeString.lowercased())
                else {
                    self.sendBadRequest(message: "400 Bad Request (Content-Type header missing)", to: context)
                    return
                }

                let uri = String(infoSavedRequestHead!.uri.dropFirst())
                let payloadBytes: Bytes
                if var buffer = self.bodyBuffer, let bytes = buffer.readBytes(length: buffer.readableBytes) {
                    payloadBytes = bytes
                } else {
                    self.sendBadRequest(to: context)
                    return
                }

                let request = Request(
                    URI: uri,
                    headers: infoSavedRequestHead!.headers,
                    remoteAddr: context.channel.remoteAddrString,
                    body: payloadBytes,
                    uuid: uuid,
                    contentType: contentType,
                    method: infoSavedRequestHead!.method,
                    eventLoop: context.eventLoop
                )
                let future = resolver(request)
                future.whenComplete { _ in
                    self.logger.debug(
                        "HTTP request '\(request.URI)' execution took \(self.profiler.end().rounded(toPlaces: 5)) s"
                    )
                }
                var headers = [
                    "LGNC-UUID": self.uuid.string,
                    "Server": "LGNC \(LGNC.VERSION)",
                ]
                future.whenSuccess { (body, additionalHeaders) in
                    self.buffer.writeBytes(body)
                    headers["Content-Type"] = request.contentType.rawValue

                    for (name, value) in additionalHeaders {
                        headers[name] = value
                    }

                    self.finishRequest(
                        context: context,
                        status: .ok,
                        additionalHeaders: headers
                    )
                }
                future.whenFailure { error in
                    self.logger.error("There was an error while processing request '\(request.URI)': \(error)")
                    self.buffer.writeString("500 Internal Server Error")
                    self.finishRequest(
                        context: context,
                        status: .internalServerError,
                        additionalHeaders: headers
                    )
                }
            }
        }

        private func finishRequest(
            context: ChannelHandlerContext,
            status: HTTPResponseStatus,
            additionalHeaders: [String: String] = [:]
        ) {
            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
            additionalHeaders.forEach {
                headers.add(name: $0.key, value: $0.value)
            }
            context.write(wrapOutboundOut(.head(httpResponseHead(request: infoSavedRequestHead!, status: status, headers: headers))), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            completeResponse(context, trailers: nil, promise: nil)
        }
    }
}
