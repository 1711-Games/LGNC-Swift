import Foundation
import NIO
import NIOHTTP1
import LGNCore

internal extension LGNC.HTTP {
    final class Handler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
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
                guard let contentTypeString = request.head.headers["Content-Type"].first else {
                    self.sendBadRequestResponse(context: context, message: "400 Bad Request (Content-Type header missing)")
                    return
                }
                contentType = LGNCore.ContentType(rawValue: contentTypeString)
            }

            let payloadBytes: Bytes
            if let body = request.body, let bytes = body.getBytes(at: 0, length: body.readableBytes) {
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

            Task.detached {
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

            context.eventLoop.makeSucceededFuture(())
                .flatMap { context.writeAndFlush(head) }
                .flatMap { context.writeAndFlush(body) }
                .flatMap { context.writeAndFlush(end) }
                .flatMapError { error in
                    self.logger.error("Could not send response: \(error)")
                    return context.eventLoop.makeSucceededFuture(())
                }
                .flatMap { close ? context.close() : context.eventLoop.makeSucceededFuture(()) }
                .whenComplete { _ in }
        }

    }
}
