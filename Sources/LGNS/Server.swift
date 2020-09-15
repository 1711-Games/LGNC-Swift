import LGNCore
import LGNP
import NIO

public typealias Time = TimeAmount
public typealias ControlBitmask = LGNP.Message.ControlBitmask

public extension LGNS {
    typealias Resolver = (LGNP.Message, LGNCore.Context) -> EventLoopFuture<LGNP.Message?>

    static let DEFAULT_PORT = 1711

    /// A LGNS server
    class Server: AnyServer {
        public typealias BindTo = LGNCore.Address

        public static var logger: Logger = Logger(label: "LGNS.Server")
        public static let defaultPort: Int = LGNS.DEFAULT_PORT

        private let requiredBitmask: LGNP.Message.ControlBitmask
        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount
        private let cryptor: LGNP.Cryptor

        public let eventLoopGroup: EventLoopGroup
        public var channel: Channel!
        public private(set) var bootstrap: ServerBootstrap!
        public var isRunning: Bool = false

        public required init(
            cryptor: LGNP.Cryptor,
            requiredBitmask: ControlBitmask,
            eventLoopGroup: EventLoopGroup,
            readTimeout: Time = .seconds(1),
            writeTimeout: Time = .seconds(1),
            resolver: @escaping Resolver
        ) {
            self.cryptor = cryptor
            self.requiredBitmask = requiredBitmask
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
            self.eventLoopGroup = eventLoopGroup

            self.bootstrap = ServerBootstrap(group: self.eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer { channel in
                    channel.pipeline.addHandlers(
                        BackPressureHandler(),
                        IdleStateHandler(readTimeout: self.readTimeout, writeTimeout: self.writeTimeout),
                        LGNS.LGNPCoder(cryptor: self.cryptor, requiredBitmask: self.requiredBitmask),
                        LGNS.ServerHandler(logger: Self.logger, resolver: resolver)
                    )
                }

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 64)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        }

        deinit {
            if self.isRunning {
                Self.logger.warning("LGNS Server has not been shutdown manually")
                try! self.shutdown().wait()
            }
        }
    }
}
