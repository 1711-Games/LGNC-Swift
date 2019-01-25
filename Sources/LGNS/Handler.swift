import LGNCore
import LGNP
import NIO

internal extension LGNS {
    internal class BaseHandler: ChannelInboundHandler {
        public typealias InboundIn = LGNP.Message
        public typealias InboundOut = LGNP.Message
        public typealias OutboundOut = LGNP.Message

        fileprivate var handlerType: StaticString = ""

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

        internal func sendError(to ctx: ChannelHandlerContext, error: LGNS.E) {
            print("FLUSHING ERROR TO CLIENT")
            print("\(#file):\(#line)")
            print(error)
            let promise: PromiseVoid = ctx.eventLoop.newPromise()
            promise.futureResult.whenComplete { ctx.close(promise: nil) }
            ctx.writeAndFlush(
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
            // ctx.fireErrorCaught(error)
        }

        public func channelInactive(ctx: ChannelHandlerContext) {
            promise?.fail(error: LGNS.E.ConnectionClosed)
            ctx.fireChannelInactive()
        }

        public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
            var profiler: LGNCore.Profiler?
            if type(of: self).profile == true {
                profiler = LGNCore.Profiler.begin()
            }

            var message = unwrapInboundIn(data)
            let remoteAddr = ctx.channel.remoteAddrString
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
                RequestInfo(
                    remoteAddr: remoteAddr,
                    clientAddr: metaDict["ip"] ?? remoteAddr,
                    userAgent: metaDict["ua"] ?? "LGNS",
                    uuid: message.uuid,
                    isSecure: message.controlBitmask.contains(.encrypted),
                    eventLoop: ctx.eventLoop
                )
            )

            promise = nil

            if let profiler = profiler {
                future.whenComplete {
                    LGNCore.log(
                        "LGNS \(type(of: self)) request '\(message.URI)' execution took \(profiler.end().rounded(toPlaces: 5)) s",
                        prefix: message.uuid.string
                    )
                }
            }

            future.whenFailure {
                self.errorCaught(ctx: ctx, error: $0)
            }

            future.whenSuccess {
                guard let message = $0 else {
                    return
                }
                ctx.writeAndFlush(self.wrapInboundOut(message), promise: nil)
                if !message.controlBitmask.contains(.keepAlive) {
                    ctx.close(promise: nil)
                }
            }
        }

        // this must be overriden by ClientHandler and ServerHandler
        fileprivate func handleError(ctx _: ChannelHandlerContext, error _: LGNS.E) {
            // noop
        }

        func errorCaught(ctx: ChannelHandlerContext, error: Error) {
            dump("ERROR CAUGHT: \(error)")
            if let error = error as? LGNS.E {
                handleError(ctx: ctx, error: error)
            } else {
                print("Unknown error: \(error)")
                handleError(ctx: ctx, error: LGNS.E.UnknownError("\(error)"))
            }
        }
    }

    internal final class ServerHandler: BaseHandler {
        override class var profile: Bool {
            return true
        }

        fileprivate override func handleError(ctx: ChannelHandlerContext, error: LGNS.E) {
            sendError(to: ctx, error: error)
        }
    }

    internal class ClientHandler: BaseHandler {
        fileprivate override func handleError(ctx: ChannelHandlerContext, error: LGNS.E) {
            ctx.fireErrorCaught(error)
            promise?.fail(error: error)
        }
    }
}
