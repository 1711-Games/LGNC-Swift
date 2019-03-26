import LGNCore
import LGNP
import NIO

public extension LGNS {
    class Client {
        public let controlBitmask: LGNP.Message.ControlBitmask
        public let eventLoopGroup: EventLoopGroup
        public let cryptor: LGNP.Cryptor
        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount

        public required init(
            cryptor: LGNP.Cryptor,
            controlBitmask: ControlBitmask,
            eventLoopGroup: EventLoopGroup,
            readTimeout: Time = .seconds(1),
            writeTimeout: Time = .seconds(1)
        ) {
            self.cryptor = cryptor
            self.controlBitmask = controlBitmask
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
            self.eventLoopGroup = eventLoopGroup
        }

        public func request(at address: LGNS.Address, with message: LGNP.Message) -> Future<LGNP.Message> {
            let resultPromise: PromiseLGNP = eventLoopGroup.next().makePromise()
            let connectPromise = ClientBootstrap(group: eventLoopGroup)
                .connectTimeout(.seconds(3))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(IdleStateHandler(readTimeout: self.readTimeout, writeTimeout: self.writeTimeout, allTimeout: self.readTimeout)).flatMap {
                        channel.pipeline.addHandler(LGNS.LGNPCoder(cryptor: self.cryptor, requiredBitmask: self.controlBitmask, validateRequiredBitmask: false)).flatMap {
                            channel.pipeline.addHandler(
                                LGNS.ClientHandler(promise: resultPromise) { message, _ in
                                    resultPromise.succeed(message)
                                    channel.close(promise: nil)
                                    return self.eventLoopGroup.next().makeSucceededFuture(nil)
                                }
                            )
                } } }
                .connect(to: address)
            connectPromise.whenSuccess { channel in
                _ = channel.writeAndFlush(message)
            }
            connectPromise.whenFailure(resultPromise.fail)
            return resultPromise.futureResult
        }

        public func request(
            at address: LGNS.Address,
            with message: LGNP.Message,
            on eventLoop: EventLoop
        ) -> Future<LGNP.Message> {
            return self
                .request(at: address, with: message)
                .hop(to: eventLoop)
        }
    }
}
