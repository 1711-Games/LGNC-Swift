import LGNCore
import LGNP
import NIO

internal extension LGNS {
    class BaseHandler: ChannelInboundHandler {
        public typealias InboundIn = LGNP.Message
        public typealias InboundOut = LGNP.Message
        public typealias OutboundOut = LGNP.Message

        fileprivate var handlerType: StaticString = ""
        private let logger = Logger(label: "LGNS.BaseHandler")

        private static let META_SECTION_BYTES: Bytes = [0, 255]
        private static let EOL: Byte = 10

        private let resolver: LGNS.Resolver
        fileprivate var promise: PromiseLGNP?

        fileprivate class var profile: Bool {
            return false
        }

        public init(promise: PromiseLGNP? = nil, resolver: @escaping Resolver) {
            self.promise = promise
            self.resolver = resolver
        }

        internal func sendError(to context: ChannelHandlerContext, error: LGNS.E) {
            print("FLUSHING ERROR TO CLIENT")
            print("\(#file):\(#line)")
            print(error)
            let promise: PromiseVoid = context.eventLoop.makePromise()
            promise.futureResult.whenComplete { _ in context.close(promise: nil) }
            context.writeAndFlush(
                wrapOutboundOut(
                    LGNP.Message(
                        URI: "",
                        payload: error.description.bytes,
                        salt: [],
                        controlBitmask: .containsError
                    )
                ),
                promise: promise
            )
            // context.fireErrorCaught(error)
        }

        public func channelInactive(context: ChannelHandlerContext) {
            self.promise?.fail(LGNS.E.ConnectionClosed)
            context.fireChannelInactive()
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var profiler: LGNCore.Profiler?
            if type(of: self).profile == true {
                profiler = LGNCore.Profiler.begin()
            }

            var message = unwrapInboundIn(data)
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

            let future = resolver(
                message,
                LGNCore.RequestInfo(
                    remoteAddr: remoteAddr,
                    clientAddr: metaDict["ip"] ?? remoteAddr,
                    userAgent: metaDict["ua"] ?? "LGNS",
                    locale: LGNCore.Translation.Locale(metaDict["lc"]),
                    uuid: message.uuid,
                    isSecure: message.controlBitmask.contains(.encrypted),
                    transport: .LGNS,
                    eventLoop: context.eventLoop
                )
            )

            self.promise = nil

            if let profiler = profiler {
                future.whenComplete { _ in
                    self.logger.debug("[\(message.uuid.string)] LGNS \(type(of: self)) request '\(message.URI)' execution took \(profiler.end().rounded(toPlaces: 5)) s")
                }
            }

            future.whenFailure {
                self.errorCaught(context: context, error: $0)
            }

            future.whenSuccess {
                guard let message = $0 else {
                    return
                }
                context.writeAndFlush(self.wrapInboundOut(message), promise: nil)
                if !message.controlBitmask.contains(.keepAlive) {
                    context.close(promise: nil)
                }
            }
        }

        // this must be overriden by ClientHandler and ServerHandler
        fileprivate func handleError(context _: ChannelHandlerContext, error _: LGNS.E) {
            // noop
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            dump("ERROR CAUGHT: \(error)")
            if let error = error as? LGNS.E {
                handleError(context: context, error: error)
            } else {
                print("Unknown error: \(error)")
                handleError(context: context, error: LGNS.E.UnknownError("\(error)"))
            }
        }
    }

    final class ServerHandler: BaseHandler {
        override class var profile: Bool {
            return true
        }

        fileprivate override func handleError(context: ChannelHandlerContext, error: LGNS.E) {
            sendError(to: context, error: error)
        }
    }

    class ClientHandler: BaseHandler {
        fileprivate override func handleError(context: ChannelHandlerContext, error: LGNS.E) {
            context.fireErrorCaught(error)
            promise?.fail(error)
        }
    }
}
