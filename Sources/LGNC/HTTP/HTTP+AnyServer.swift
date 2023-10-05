import Foundation
import LGNCore
import LGNLog
import LGNP
import LGNPContenter
import LGNS
import NIO
import NIOHTTP1
import AsyncHTTPClient

public extension LGNC.HTTP {
    class Server: LGNCoreServer, @unchecked Sendable {
        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount

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

            self.bootstrap = ServerBootstrap(group: self.eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelInitializer { channel in
                    let profiler = LGNCore.Profiler()

                    let httpHandlers: [ChannelHandler & RemovableChannelHandler] = [
                        NIOHTTPServerRequestAggregator(maxContentLength: 1_000_000),
                        LGNC.HTTP.Handler(resolver: resolver, profiler: profiler),
                    ]

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
                Logger.current.warning("HTTP Server has not been shutdown manually")
            }
        }
    }
}
