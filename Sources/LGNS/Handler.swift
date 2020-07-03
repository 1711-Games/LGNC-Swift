import LGNCore
import LGNP
import NIO

internal extension LGNS {
    class BaseHandler: ChannelInboundHandler {
        public typealias InboundIn = LGNP.Message
        public typealias InboundOut = LGNP.Message
        public typealias OutboundOut = LGNP.Message

        fileprivate var handlerType: StaticString = ""

        private static let META_SECTION_BYTES: Bytes = [0, 255]
        private static let EOL: Byte = 10

        private let resolver: LGNS.Resolver
        public var promise: Promise<(LGNP.Message, LGNCore.Context)>?

        fileprivate class var profile: Bool {
            false
        }

        public private(set) var isOpen: Bool = false
        public var logger: Logger

        public init(
            promise: Promise<(LGNP.Message, LGNCore.Context)>? = nil,
            logger: Logger = Logger(label: "LGNS.BaseHandler"),
            resolver: @escaping Resolver
        ) {
            self.promise = promise
            self.logger = logger
            self.resolver = resolver

            self.logger[metadataKey: "ID"] = "\(ObjectIdentifier(self).hashValue)"
            self.logger.debug("Handler initialized")
        }

        deinit {
            self.logger.debug("Handler deinitialized")
        }

        internal func sendError(to context: ChannelHandlerContext, error: ErrorTupleConvertible) {
            print("FLUSHING ERROR TO CLIENT")
            print("\(#file):\(#line)")
            print(error)
            let promise: PromiseVoid = context.eventLoop.makePromise()
            promise.futureResult.whenComplete { _ in context.close(promise: nil) }
            context.writeAndFlush(
                wrapOutboundOut(
                    LGNP.Message(
                        URI: "",
                        payload: LGNCore.getBytes("\(error.tuple.code) \(error.tuple.message)"),
                        controlBitmask: .containsError
                    )
                ),
                promise: promise
            )
            // context.fireErrorCaught(error)
        }

        func channelActive(context: ChannelHandlerContext) {
            self.isOpen = true
            context.fireChannelActive()
        }

        public func channelInactive(context: ChannelHandlerContext) {
            self.isOpen = false
            self.promise?.fail(LGNS.E.ConnectionClosed)
            context.fireChannelInactive()
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var profiler: LGNCore.Profiler?
            if Self.profile == true {
                profiler = LGNCore.Profiler.begin()
            }

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
                eventLoop: context.eventLoop
            )

            if profiler != nil {
                requestContext.logger.debug(
                    """
                    About to serve request at URI '\(message.URI)' \
                    from remoteAddr \(remoteAddr) (clientAddr \(clientAddr)) by \
                    clientID '\(clientID ?? "UNKNOWN")' (userAgent '\(userAgent)'), locale \(locale)
                    """
                )
            }

            let resultFuture = self.resolver(message, requestContext)

            self.cleanup()

            if let profiler = profiler {
                resultFuture.whenComplete { _ in
                    requestContext.logger.debug("""
                        LGNS \(type(of: self)) request '\(message.URI)' execution \
                        took \(profiler.end().rounded(toPlaces: 5)) s
                        """
                    )
                }
            }

            resultFuture.whenFailure {
                requestContext.logger.debug("Writing error to channel")
                self.errorCaught(context: context, error: $0)
            }

            resultFuture.whenSuccess {
                guard let message = $0 else {
                    requestContext.logger.debug("No LGNP message returned from resolver, do nothing")
                    return
                }

                requestContext.logger.debug("Writing LGNP message to channel")
                context.writeAndFlush(self.wrapInboundOut(message), promise: nil)

                if !message.controlBitmask.contains(.keepAlive) {
                    requestContext.logger.debug("Closing the channel as keepAlive is 'false'")
                    context.close(promise: nil)
                }
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
        }
    }

    final class ServerHandler: BaseHandler {
        override class var profile: Bool {
            return true
        }

        fileprivate override func handleError(context: ChannelHandlerContext, error: ErrorTupleConvertible) {
            self.sendError(to: context, error: error)
        }
    }

    class ClientHandler: BaseHandler {
        fileprivate override func handleError(context: ChannelHandlerContext, error: ErrorTupleConvertible) {
            context.fireErrorCaught(error)
            self.promise?.fail(error)
        }
    }
}
