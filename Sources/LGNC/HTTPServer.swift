import Foundation
import LGNCore
import LGNP
import LGNPContenter
import LGNS
import NIO
import NIOHTTP1
import AsyncHTTPClient

public extension LGNC {
    enum HTTP {
        public typealias ResolverResult = (body: Bytes, headers: [(name: String, value: String)])
        public typealias Resolver = (Request) async throws -> ResolverResult

        public static let HEADER_PREFIX = "HEADER__"
        public static let COOKIE_META_KEY_PREFIX = HEADER_PREFIX + "Set-Cookie: "
    }
}

public extension LGNCore.ContentType {
    init?(from HTTPHeader: String) {
        let result: LGNCore.ContentType

        switch HTTPHeader {
        case "text/plain": result = .PlainText
        case "application/xml": result = .XML
        case "application/json": result = .JSON
        case "application/msgpack": result = .MsgPack
        default: return nil
        }

        self = result
    }

    var header: String {
        let result: String

        switch self {
        case .PlainText: result = "text/plain"
        case .XML: result = "application/xml"
        case .JSON: result = "application/json"
        case .MsgPack: result = "application/msgpack"
        }

        return result
    }
}

public extension LGNC.HTTP {
    struct Request {
        public let URI: String
        public let headers: HTTPHeaders
        public let remoteAddr: String
        public let body: Bytes
        public let uuid: UUID
        public let contentType: LGNCore.ContentType
        public let method: HTTPMethod
        public let meta: LGNC.Entity.Meta
        public let eventLoop: EventLoop
    }
}

public extension LGNC.HTTP {
    class Server: AnyServer {
        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount

        public static let logger: Logger = Logger(label: "LGNC.HTTP")
        public static var defaultPort: Int = 8080

        public let address: LGNCore.Address
        public let eventLoopGroup: EventLoopGroup
        public var channel: Channel!
        public var bootstrap: ServerBootstrap!
        public var isRunning: Bool = false

        public required init(
            address: LGNCore.Address,
            eventLoopGroup: EventLoopGroup,
            service: Service.Type,
            webSocketRouter: WebsocketRouter.Type? = nil,
            readTimeout: Time = .minutes(1),
            writeTimeout: Time = .minutes(1),
            resolver: @escaping Resolver
        ) {
            self.address = address
            self.eventLoopGroup = eventLoopGroup
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout

            let httpHandlers: [ChannelHandler & RemovableChannelHandler] = [
                NIOHTTPServerRequestAggregator(maxContentLength: 1_000_000),
                LGNC.HTTP.Handler(resolver: resolver),
            ]

            self.bootstrap = ServerBootstrap(group: self.eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelInitializer { channel in
                    var upgrader: NIOHTTPServerUpgradeConfiguration? = nil
                    if let webSocketRouterType = webSocketRouter {
                        let webSocketRouter = webSocketRouterType.init(channel: channel, service: service)
                        upgrader = (
                            upgraders: [ webSocketRouter.upgrader ],
                            completionHandler: { context in
                                for handler in httpHandlers {
                                    context.channel.pipeline.removeHandler(handler, promise: nil)
                                }
                            }
                        )
                    }

                    return channel.pipeline
                        .configureHTTPServerPipeline(withServerUpgrade: upgrader, withErrorHandling: true)
                        .flatMap { channel.pipeline.addHandlers(httpHandlers) }
                }
                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 64)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        }

        deinit {
            if self.isRunning {
                Self.logger.warning("HTTP Server has not been shutdown manually")
            }
        }
    }
}

internal extension Array {
    func appending<S: Sequence>(contentsOf newElements: S) -> Self where S.Element == Self.Element {
        var copy = self

        copy.append(contentsOf: newElements)

        return copy
    }
}

internal extension LGNC.HTTP {
    final class Handler: ChannelInboundHandler, RemovableChannelHandler {
        typealias InboundIn = NIOHTTPServerRequestFull
        typealias OutboundOut = HTTPServerResponsePart

        private let resolver: Resolver
        private let requestID = UUID()

        private lazy var logger: Logger = {
            var logger = Logger(label: "LGNC.HTTP.Handler")

            logger[metadataKey: "requestID"] = "\(self.requestID.string)"

            return logger
        }()

        public init(resolver: @escaping Resolver) {
            self.resolver = resolver
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let profiler = LGNCore.Profiler.begin()

            let request = self.unwrapInboundIn(data)

            self.logger.debug("About to serve \(request.head.method) \(request.head.uri)")

            guard [.POST, .GET].contains(request.head.method) else {
                return self.sendResponse(context: context, status: .notImplemented, body: "501 Not Implemented")
            }

            let method = request.head.method

            let URI = String(request.head.uri.dropFirst())
            let contentType: LGNCore.ContentType

            if method == .GET {
                contentType = .JSON
            } else {
                guard
                    let contentTypeString = request.head.headers["Content-Type"].first,
                    let _contentType = LGNCore.ContentType.init(from: contentTypeString.lowercased())
                else {
                    self.sendBadRequestResponse(context: context, message: "400 Bad Request (Content-Type header missing)")
                    return
                }
                contentType = _contentType
            }

            let payloadBytes: Bytes
            if var body = request.body, let bytes = body.readBytes(length: body.readableBytes) {
                payloadBytes = bytes
            } else if method == .GET {
                payloadBytes = []
            } else {
                self.sendBadRequestResponse(context: context, message: "400 Bad Request (no body)")
                return
            }

            let meta = request.head.headers["Cookie"].parseCookies()

            logger.debug("Request is \(contentType). Payload: \(contentType == .JSON ? payloadBytes._string : "\(payloadBytes.count) bytes"), meta: \(meta)")

            let resolverRequest = Request(
                URI: URI,
                headers: request.head.headers,
                remoteAddr: request.head.headers["X-Real-IP"].first ?? context.channel.remoteAddrString,
                body: payloadBytes,
                uuid: self.requestID,
                contentType: contentType,
                method: method,
                meta: meta,
                eventLoop: context.eventLoop
            )

            let resolverResultPromise = context.eventLoop.makePromise(of: ResolverResult.self)

            detach {
                do {
                    resolverResultPromise.succeed(try await self.resolver(resolverRequest))
                } catch {
                    resolverResultPromise.fail(error)
                }
            }

            let headers = [
                ("Server", "LGNC \(LGNC.VERSION)"),
            ]

            resolverResultPromise.futureResult.whenSuccess { body, additionalHeaders in
                self.sendResponse(
                    context: context,
                    status: .ok,
                    body: context.channel.allocator.buffer(bytes: body),
                    close: request.head.isKeepAlive == false,
                    headers: .init(headers.appending(contentsOf: additionalHeaders))
                )
            }

            resolverResultPromise.futureResult.whenFailure { error in
                self.logger.error("There was an error while processing request '\(resolverRequest.URI)': \(error)")
                self.sendResponse(
                    context: context,
                    status: .internalServerError,
                    body: "500 Internal Server Error",
                    close: true,
                    headers: .init(headers)
                )
            }

            resolverResultPromise.futureResult.whenComplete { _ in
                self.logger.debug(
                    "HTTP request '\(resolverRequest.URI)' execution took \(profiler.end().rounded(toPlaces: 5)) s"
                )
            }
        }

        func sendBadRequestResponse(context: ChannelHandlerContext, message: String) {
            self.sendResponse(context: context, status: .badRequest, body: message)
        }

        func sendResponse(
            context: ChannelHandlerContext,
            status: HTTPResponseStatus,
            body: String,
            close: Bool = true,
            headers: HTTPHeaders = [:]
        ) {
            self.sendResponse(
                context: context,
                status: status,
                body: context.channel.allocator.buffer(string: body),
                close: close,
                headers: headers
            )
        }

        func sendResponse(
            context: ChannelHandlerContext,
            status: HTTPResponseStatus,
            body: ByteBuffer,
            close: Bool,
            headers: HTTPHeaders = [:]
        ) {
            let head = self.wrapOutboundOut(
                .head(
                    HTTPResponseHead(
                        version: .http1_1,
                        status: status,
                        headers: headers
                    )
                )
            )
            let body = self.wrapOutboundOut(.body(.byteBuffer(body)))
            let end = self.wrapOutboundOut(.end(nil))

            context.eventLoop.makeSucceededFuture()
                .flatMap { context.writeAndFlush(head) }
                .flatMap { context.writeAndFlush(body) }
                .flatMap { context.writeAndFlush(end) }
                .flatMapError { error in
                    self.logger.error("Could not send response: \(error)")
                    return context.eventLoop.makeSucceededFuture()
                }
                .flatMap { close ? context.close() : context.eventLoop.makeSucceededFuture() }
                .whenComplete { _ in }
        }
        
    }
}
