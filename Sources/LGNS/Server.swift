import LGNCore
import LGNP
import NIO

public typealias Time = TimeAmount
public typealias ControlBitmask = LGNP.Message.ControlBitmask

public extension LGNS {
    typealias Resolver = (LGNP.Message, LGNCore.Context) -> EventLoopFuture<LGNP.Message?>

    static let DEFAULT_PORT = 1711

    class Server: AnyServer {
        public typealias BindTo = LGNCore.Address

        public static var logger: Logger = Logger(label: "LGNS.Server")

        private let requiredBitmask: LGNP.Message.ControlBitmask
        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount
        private let cryptor: LGNP.Cryptor
        private lazy var saltBytes = self.cryptor.salt

        public let eventLoopGroup: EventLoopGroup
        public private(set) var channel: Channel!
        public private(set) var bootstrap: ServerBootstrap!
        public private(set) var isRunning: Bool = false

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
                        LGNS.ServerHandler(resolver: resolver)
                    )
                }

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 64)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

            SignalObserver.add(self)
        }

        deinit {
            if self.isRunning {
                Self.logger.warning("LGNS Server has not been shutdown manually")
                //try! self.shutdown().wait()
            }
        }

//        public func bind(to address: LGNCore.Address) -> Future<Void> {
//            Self.logger.info("LGNS Server: Trying to bind at \(address)")
//
//            let bindFuture = self.bootstrap.bind(to: address)
//
//            bindFuture.whenComplete { result in
//                switch result {
//                case .success(_): Self.logger.info("LGNS Server: Succesfully started on \(address)")
//                case let .failure(error): Self.logger.info("LGNS Server: Could not start on \(address): \(error)")
//                }
//            }
//
//            return bindFuture.map {
//                self.channel = $0
//                self.isRunning = true
//            }
//        }
//
//        public func waitForStop() throws {
//            guard self.isRunning, self.channel != nil else {
//                throw LGNS.E.ServerNotRunning
//            }
//
//            try self.channel.closeFuture.wait()
//        }
//
//        public func shutdown() -> Future<Void> {
//            let promise = self.eventLoopGroup.next().makePromise(of: Void.self)
//
//            Self.logger.info("LGNS Server: Shutting down")
//
//            self.channel.close(promise: promise)
//
//            promise.futureResult.whenComplete { result in
//                switch result {
//                case .success(_): Self.logger.info("LGNS Server: Goodbye")
//                case let .failure(error): Self.logger.info("LGNS Server: Could not shutdown: \(error)")
//                }
//            }
//
//            return promise.futureResult.map {
//                self.isRunning = false
//                self.channel = nil
//            }
//        }
    }
}
