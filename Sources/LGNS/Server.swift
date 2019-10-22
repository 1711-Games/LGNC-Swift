import LGNCore
import LGNP
import NIO

public typealias Time = TimeAmount
public typealias ControlBitmask = LGNP.Message.ControlBitmask

public extension LGNS {
    typealias Resolver = (LGNP.Message, LGNCore.Context) -> EventLoopFuture<LGNP.Message?>

    static let DEFAULT_PORT = 1711

    class Server: Shutdownable {
        public typealias BindTo = LGNCore.Address

        private let requiredBitmask: LGNP.Message.ControlBitmask
        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount
        private let eventLoopGroup: EventLoopGroup
        private let cryptor: LGNP.Cryptor
        private var bootstrap: ServerBootstrap!
        private var channel: Channel!
        lazy var saltBytes = Bytes(self.cryptor.salt.utf8)
        private let logger = Logger(label: "LGNS.Server")

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

            bootstrap = ServerBootstrap(group: self.eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer { channel in
                    channel.pipeline.addHandlers(
                        BackPressureHandler(),
                        IdleStateHandler(readTimeout: self.readTimeout, writeTimeout: self.writeTimeout),
                        LGNS.LGNPCoder(cryptor: self.cryptor, requiredBitmask: self.requiredBitmask),
                        LGNS.ServerHandler(resolver: resolver)
                    )
                }

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 64)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

            SignalObserver.add(self)
        }

        public func shutdown(promise: PromiseVoid) {
            self.logger.info("LGNS Server: shutting down")
            self.channel.close(promise: promise)
            self.logger.info("LGNS Server: goodbye")
        }

        public func serve(at target: BindTo, promise: PromiseVoid? = nil) throws {
            self.channel = try bootstrap.bind(to: target).wait()

            promise?.succeed(())

            try self.channel.closeFuture.wait()
        }
    }
}
