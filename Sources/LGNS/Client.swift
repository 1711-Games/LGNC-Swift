import LGNCore
import LGNP
import NIO

public extension LGNS {
    public class Client {
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
        ) throws {
            self.cryptor = cryptor
            self.controlBitmask = controlBitmask
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
            self.eventLoopGroup = eventLoopGroup
        }

        public func request(at address: LGNS.Address, with message: LGNP.Message) -> Future<LGNP.Message> {
            let resultPromise: PromiseLGNP = self.eventLoopGroup.next().newPromise()
            let connectPromise = ClientBootstrap(group: self.eventLoopGroup)
                .connectTimeout(.seconds(3))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.add(handler: IdleStateHandler(readTimeout: self.readTimeout, writeTimeout: self.writeTimeout, allTimeout: self.readTimeout)).then {
                    channel.pipeline.add(handler: LGNS.LGNPCoder(cryptor: self.cryptor, requiredBitmask: self.controlBitmask, validateRequiredBitmask: false)).then {
                    channel.pipeline.add(
                        handler: LGNS.ClientHandler(promise: resultPromise) { message, _ in
                            resultPromise.succeed(result: message)
                            channel.close(promise: nil)
                            return self.eventLoopGroup.next().newSucceededFuture(result: nil)
                        }
                    )
                }}}
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
                .hopTo(eventLoop: eventLoop)
        }
    }
}
