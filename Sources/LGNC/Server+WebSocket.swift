import Foundation
import LGNCore
import Entita
import NIO
import NIOHTTP1
import NIOWebSocket
import LGNPContenter

public protocol WebsocketRouter: AnyObject {
    var upgrader: HTTPServerProtocolUpgrader { get }
    var service: Service.Type { get }
    var requestID: UUID { get set }
    var logger: Logger { get set }
    var channel: Channel { get }
    var baseContext: LGNCore.Context! { get set }
    var contentType: LGNCore.ContentType { get }

    init(channel: Channel, service: Service.Type)

    func shouldUpgrade(head: HTTPRequestHead) async throws -> HTTPHeaders?
    func upgradePipelineHandler(head: HTTPRequestHead) async throws
    func route(request: LGNC.WebSocket.Request) async throws -> LGNC.WebSocket.Response?
}

public extension WebsocketRouter {
    var upgrader: HTTPServerProtocolUpgrader {
        NIOWebSocketServerUpgrader(
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) -> EventLoopFuture<HTTPHeaders?> in
                let promise = channel.eventLoop.makePromise(of: HTTPHeaders?.self)

                self.baseContext = LGNCore.Context(
                    remoteAddr: channel.remoteAddrString,
                    clientAddr: head.headers["X-Real-IP"].first ?? channel.remoteAddrString,
                    userAgent: head.headers["User-Agent"].first ?? "",
                    locale: LGNCore.i18n.Locale(
                        maybeLocale: head.headers["Accept-Language"].first,
                        allowedLocales: LGNCore.i18n.translator.allowedLocales
                    ),
                    uuid: UUID(),
                    isSecure: false,
                    transport: .WebSocket,
                    meta: [:],
                    eventLoop: channel.eventLoop
                )

                detach {
                    do {
                        guard let webSocketURI = self.service.webSocketURI else {
                            self.logger.critical("Tried to upgrade HTTP to WebSocket while Service doesn't have a WebSocket URI")
                            throw LGNC.WebSocket.E.InvalidUpgradeURI
                        }
                        guard head.uri.count > 0 else {
                            self.logger.critical("Tried to upgrade HTTP to WebSocket: URI too short")
                            throw LGNC.WebSocket.E.InvalidUpgradeURI
                        }
                        var URI = head.uri
                        if URI.first == "/" {
                            URI.removeFirst()
                        }
                        guard URI == webSocketURI else {
                            self.logger.critical("Tried to upgrade HTTP to WebSocket by invalid URI '\(head.uri)' (expected '\(webSocketURI)')")
                            throw LGNC.WebSocket.E.InvalidUpgradeURI
                        }

                        promise.succeed(try await self.shouldUpgrade(head: head))
                    } catch {
                        self.logger.error("Could not execute \(#function): \(error)")
                        promise.fail(error)
                    }
                }

                return promise.futureResult
            },
            upgradePipelineHandler: { (channel: Channel, head: HTTPRequestHead) -> EventLoopFuture<Void> in
                let promise = channel.eventLoop.makePromise(of: Void.self)

                detach {
                    do {
                        promise.succeed(try await self.upgradePipelineHandler(head: head))
                    } catch {
                        self.logger.error("Could not execute \(#function): \(error)")
                        promise.fail(error)
                    }
                }

                return promise.futureResult
            }
        )
    }

    func upgradePipelineHandler(head: HTTPRequestHead) async throws {
        try await self.channel.pipeline.addHandler(LGNC.WebSocket.Handler(router: self)).get()
    }

    func executeContract(
        clientRequestID: String,
        URI: String,
        dict: Entita.Dict
    ) async throws -> LGNC.WebSocket.Response {
        try await Task.withLocal(\.context, boundTo: self.baseContext) {
            LGNC.WebSocket.Response(
                clientRequestID: clientRequestID,
                frame: WebSocketFrame(
                    fin: true,
                    opcode: .text,
                    data: self.channel.allocator.buffer(
                        bytes: try [
                            "RequestID": clientRequestID,
                            "Response": try await self.service
                                .executeContract(URI: URI, dict: dict)
                                .getDictionary()
                        ].pack(to: self.contentType)
                    )
                ),
                close: false
            )
        }
    }
}

public extension LGNC {
    enum WebSocket {}
}

public extension LGNC.WebSocket {
    enum E: Error {
        case NoService
        case DecodeError
        case InvalidUpgradeURI
    }

    struct Request {
        public let remoteAddr: String
        public let body: Bytes
        public let eventLoop: EventLoop
    }
}

extension LGNC.WebSocket {
    class Handler: ChannelInboundHandler {
        typealias InboundIn = WebSocketFrame
        typealias OutboundOut = WebSocketFrame

        private let router: WebsocketRouter
        private var awaitingClose = false

        init(router: WebsocketRouter) {
            self.router = router

            print("init \(Self.self) \(ObjectIdentifier(self))")
        }

        deinit {
            print("deinit \(Self.self) \(ObjectIdentifier(self))")
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            dump(error)
            print(error)
            print(#line)
            context.fireErrorCaught(error)
        }

        public func handlerAdded(context: ChannelHandlerContext) {
            self.sendPing(context: context)
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let frame = self.unwrapInboundIn(data)

            let logger = Task.local(\.context).logger

            let payload: Bytes

            switch frame.opcode {
            case .connectionClose:
                return self.receivedClose(context: context, frame: frame)
            case .ping:
                return self.pong(context: context, frame: frame)
            case .pong:
                logger.debug("Received pong")
                return
            case .continuation:
                return
            case .binary, .text:
                var data = frame.unmaskedData
                guard let bytes = data.readBytes(length: data.readableBytes) else {
                    return
                }
                payload = bytes
            default:
                logger.notice("Unknown frame opcode: \(frame.opcode)")
                return self.closeOnError(context: context)
            }

            let promise = context.eventLoop.makePromise(of: Response?.self)

            let request = Request(
                remoteAddr: context.channel.remoteAddrString,
                body: payload,
                eventLoop: context.eventLoop
            )

            detach {
                do {
                    promise.succeed(try await self.router.route(request: request))
                } catch {
                    promise.fail(error)
                }
            }

            promise.futureResult.whenComplete { result in
                let responseFrame: WebSocketFrame
                let close: Bool

                switch result {
                case .success(let maybeResponse):
                    guard let response = maybeResponse else {
                        return
                    }
                    responseFrame = response.frame
                    close = response.close
                case .failure(let error):
                    // log
                    dump(["error": error])
                    responseFrame = LGNC.WebSocket.errorFrame
                    close = true
                }

                context
                    .writeAndFlush(self.wrapOutboundOut(responseFrame))
                    .map {
                        if close {
                            context.close(promise: nil)
                        }
                    }
                    .whenComplete { _ in }
            }
        }

        public func channelReadComplete(context: ChannelHandlerContext) {
            context.flush()
        }

        private func sendPing(context: ChannelHandlerContext) {
            guard context.channel.isActive else { return }
            guard !self.awaitingClose else { return }

            context
                .writeAndFlush(self.wrapOutboundOut(WebSocketFrame(fin: true, opcode: .ping, data: ByteBuffer())))
                .map {
                    context.eventLoop.scheduleTask(in: .seconds(10), { self.sendPing(context: context) })
                }
                .whenFailure { (_: Error) in context.close(promise: nil)}
        }

        private func receivedClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
            if self.awaitingClose {
                context.close(promise: nil)
            } else {
                var data = frame.unmaskedData
                _ = context
                    .write(
                        self.wrapOutboundOut(
                            WebSocketFrame(
                                fin: true,
                                opcode: .connectionClose,
                                data: data.readSlice(length: 2) ?? ByteBuffer()
                            )
                        )
                    )
                    .map { () in context.close(promise: nil) }
            }
        }

        private func pong(context: ChannelHandlerContext, frame: WebSocketFrame) {
            var frameData = frame.data
            if let maskingKey = frame.maskKey {
                frameData.webSocketUnmask(maskingKey)
            }

            context.write(self.wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: frameData)), promise: nil)
        }

        private func closeOnError(context: ChannelHandlerContext) {
            var data = context.channel.allocator.buffer(capacity: 2)
            data.write(webSocketErrorCode: .protocolError)

            context
                .write(self.wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: data)))
                .whenComplete { (_: Result<Void, Error>) in context.close(mode: .output, promise: nil) }

            awaitingClose = true
        }
    }
}

extension LGNC.WebSocket {
    public static var errorFrame: WebSocketFrame {
        WebSocketFrame(fin: true, opcode: .text, data: .init(staticString: "internal server error"))
    }

    public struct Response {
        let clientRequestID: String
        let frame: WebSocketFrame
        let close: Bool

        public init(clientRequestID: String, frame: WebSocketFrame, close: Bool = false) {
            self.clientRequestID = clientRequestID
            self.frame = frame
            self.close = close
        }
    }

    open class SimpleRouter: WebsocketRouter {
        public let channel: Channel
        public let service: Service.Type
        public var allowedURIs: [String]
        public var requestID: UUID = UUID()
        public var logger: Logger
        public var baseContext: LGNCore.Context!
        public let contentType: LGNCore.ContentType = .JSON

        public required init(channel: Channel, service: Service.Type) {
            self.channel = channel
            self.service = service
            self.allowedURIs = service.webSocketContracts.map { $0.URI }

            var logger = Logger(label: "LGNC.WebSocket")
            logger[metadataKey: "requestID"] = "\(self.requestID.string)"

            self.logger = logger
        }

        open func shouldUpgrade(head: HTTPRequestHead) async throws -> HTTPHeaders? {
            return HTTPHeaders()
        }

        open func route(request: Request) async throws -> Response? {
            var clientRequestID: String = "unknown"
            let response: Response

            do {
                let input = try request.body.unpack(from: self.contentType)
                guard let URI = input["URI"] as? String else {
                    return nil
                }
                guard self.allowedURIs.contains(URI) else {
                    self.logger.info("No URI in request")
                    throw LGNC.ContractError.URINotFound(URI)
                }
                guard let _clientRequestID = input["RequestID"] as? String else {
                    self.logger.info("No RequestID in request")
                    throw E.DecodeError
                }
                clientRequestID = _clientRequestID
                guard let dict = input["Request"] as? Entita.Dict else {
                    self.logger.info("No Request in request")
                    throw E.DecodeError
                }

                response = try await self.executeContract(clientRequestID: clientRequestID, URI: URI, dict: dict)
            } catch LGNPContenter.E.UnpackError {
                return nil
            } catch {
                self.logger.error("Error while executing contract: \(error)")
                response = Response(clientRequestID: clientRequestID, frame: LGNC.WebSocket.errorFrame, close: false)
            }

            return response
        }
    }
}
