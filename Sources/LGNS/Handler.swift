import LGNCore
import LGNP
import NIO
import _Concurrency

internal extension LGNS {
    class BaseHandler: ChannelInboundHandler {
        enum State {
            case WaitingForInbound
            case InboundReceived
        }

        public typealias InboundIn = LGNP.Message
        public typealias InboundOut = LGNP.Message
        public typealias OutboundOut = LGNP.Message

        fileprivate var state: State = .WaitingForInbound

        private static let META_SECTION_BYTES: Bytes = [0, 255]
        private static let EOL: Byte = 10

        open private(set) var kind: String = "Base"

        private let resolver: LGNS.Resolver
        public var promise: EventLoopPromise<(LGNP.Message, LGNCore.Context)>?

        fileprivate class var profile: Bool {
            false
        }

        public private(set) var isOpen: Bool = false
        public var logger: Logger

        public init(
            promise: EventLoopPromise<(LGNP.Message, LGNCore.Context)>? = nil,
            logger: Logger = Logger(label: "LGNS.BaseHandler"),
            file: String = #file, line: Int = #line,
            resolver: @escaping Resolver
        ) {
            self.promise = promise
            self.logger = logger
            self.resolver = resolver

            self.logger[metadataKey: "ID"] = "\(ObjectIdentifier(self).hashValue)"
            self.logger.trace("Handler initialized from \(file):\(line)")
        }

        deinit {
            self.logger.trace("Handler deinitialized")
        }

        internal func sendError(to context: ChannelHandlerContext, error: ErrorTupleConvertible) {
            print("FLUSHING ERROR TO CLIENT")
            print("\(#file):\(#line)")
            print(error)
            context.eventLoop.makeSucceededFuture()
                .flatMap { () -> EventLoopFuture<Void> in
                    context.writeAndFlush(
                        self.wrapOutboundOut(
                            LGNP.Message(
                                URI: "",
                                payload: LGNCore.getBytes("\(error.tuple.code) \(error.tuple.message)"),
                                controlBitmask: .containsError
                            )
                        )
                    )
                }
                .map { () -> Void in context.close(promise: nil) }
                .whenComplete { _ in }
        }

        func channelActive(context: ChannelHandlerContext) {
            self.isOpen = true
            self.logger.trace("Became active (\(context.remoteAddress?.description ?? "unknown addr"))")
            context.fireChannelActive()
        }

        public func channelInactive(context: ChannelHandlerContext) {
            self.isOpen = false
            self.logger.trace("Became inactive")
            if self.state == .WaitingForInbound {
                self.promise?.fail(LGNS.E.ConnectionClosed)
            }
            context.fireChannelInactive()
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var logger = LGNCore.Context.current.logger
            logger[metadataKey: "LGNS.Handler"] = "\(self.kind)"

            logger.debug("Channel read (\(context.remoteAddress?.description ?? "unknown addr"))")

            guard self.state == .WaitingForInbound else {
                logger.error("Invalid handler state: expected \(State.WaitingForInbound), actual: \(state)")
                return
            }

            self.state = .InboundReceived

            let message = self.unwrapInboundIn(data)
            let remoteAddr = context.channel.remoteAddrString

            var metaDict: [String: String] = [:]
            if let metaBytes = message.meta, metaBytes.starts(with: BaseHandler.META_SECTION_BYTES) {
                for line in metaBytes[BaseHandler.META_SECTION_BYTES.count...].split(separator: BaseHandler.EOL) {
                    let exploded = line.split(separator: 0)
                    guard exploded.count == 2 else {
                        continue
                    }
                    guard
                        let key = String(bytes: exploded[0], encoding: .ascii),
                        let value = String(bytes: exploded[1], encoding: .ascii)
                    else {
                        continue
                    }
                    metaDict[key] = value
                }
            }

            let clientAddr: String = metaDict["ip"] ?? remoteAddr
            let clientID: String? = metaDict["cid"]
            let userAgent: String = metaDict["ua"] ?? "LGNS"
            let locale = LGNCore.i18n.Locale(
                maybeLocale: metaDict["lc"],
                allowedLocales: LGNCore.i18n.translator.allowedLocales
            )

            let requestContext = LGNCore.Context(
                remoteAddr: remoteAddr,
                clientAddr: clientAddr,
                clientID: clientID,
                userAgent: userAgent,
                locale: locale,
                uuid: message.uuid,
                isSecure: message.controlBitmask.contains(.encrypted) || message.controlBitmask.hasSignature,
                transport: .LGNS,
                meta: metaDict,
                eventLoop: context.eventLoop
            )

            if Self.profile {
                logger.debug(
                    """
                    About to serve request at URI '\(message.URI)' \
                    from remoteAddr \(remoteAddr) (clientAddr \(clientAddr)) by \
                    clientID '\(clientID ?? "UNKNOWN")' (userAgent '\(userAgent)'), locale \(locale)
                    """
                )
            }

            let promise = context.eventLoop.makePromise(of: LGNP.Message?.self)

            var profiler: LGNCore.Profiler?
            if Self.profile == true {
                profiler = LGNCore.Profiler.begin()
            }

            detach {
                await LGNCore.Context.$current.withValue(requestContext) {
                    do {
                        promise.succeed(try await self.resolver(message))
                    } catch {
                        promise.fail(error)
                    }
                }
            }

            promise.futureResult.whenSuccess { result in
                guard let message = result else {
                    logger.debug("No LGNP message returned from resolver, do nothing")
                    return
                }

                logger.debug("Writing LGNP message to channel")

                context
                    .eventLoop.makeSucceededFuture()
                    .flatMap { () -> EventLoopFuture<Void> in context.writeAndFlush(self.wrapInboundOut(message)) }
                    .flatMap { () -> EventLoopFuture<Void> in
                        message.controlBitmask.contains(.keepAlive)
                            ? context.eventLoop.makeSucceededFuture()
                            : self.close(context: context)
                    }
                    .whenComplete { _ in }
            }

            promise.futureResult.whenFailure { error in
                logger.debug("Writing error to channel: \(error)")
                self.errorCaught(context: context, error: error)
            }

            promise.futureResult.whenComplete { _ in
                if let profiler = profiler {
                    logger.debug("""
                    LGNS \(type(of: self)) request '\(message.URI)' execution \
                    took \(profiler.end().rounded(toPlaces: 5)) s
                    """
                    )
                }

                self.cleanup()
            }
        }

        // this must be overriden by ClientHandler and ServerHandler
        fileprivate func handleError(context _: ChannelHandlerContext, error _: ErrorTupleConvertible) {
            // noop
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            dump("ERROR CAUGHT: \(error)")
            if let error = error as? ErrorTupleConvertible {
                self.handleError(context: context, error: error)
            } else {
                print("Unknown error: \(error)")
                self.handleError(context: context, error: LGNS.E.UnknownError("\(error)"))
            }
        }

        fileprivate func cleanup() {
            self.promise = nil
            self.state = .WaitingForInbound
        }

        fileprivate func close(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            LGNCore.Context.current.logger.debug("Closing the channel")

            return context.close().flatMapErrorThrowing { error in
                switch error {
                case ChannelError.alreadyClosed: return
                default: throw error
                }
            }
        }
    }

    final class ServerHandler: BaseHandler {
        override var kind: String {
            "Server"
        }

        override class var profile: Bool {
            true
        }

        fileprivate override func handleError(context: ChannelHandlerContext, error: ErrorTupleConvertible) {
            self.sendError(to: context, error: error)
        }
    }

    class ClientHandler: BaseHandler {
        override var kind: String {
            "Client"
        }

        fileprivate override func handleError(context: ChannelHandlerContext, error: ErrorTupleConvertible) {
            context.fireErrorCaught(error)
            if self.state == .WaitingForInbound {
                self.promise?.fail(error)
            }
        }
    }
}
