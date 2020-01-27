import LGNCore
import LGNP
import NIO

public extension LGNS {
    // todo add delegate
    class Client {
        public typealias Response = (LGNP.Message, LGNCore.Context)

        public static var logger = Logger(label: "LGNS.Client")

        public let controlBitmask: LGNP.Message.ControlBitmask
        public let eventLoopGroup: EventLoopGroup
        public let cryptor: LGNP.Cryptor

        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount

        public var channel: Channel? = nil
        private var clientHandler: LGNS.ClientHandler? = nil
        public var responsePromise: Promise<Response>? = nil

        public var isConnected: Bool {
            self.channel?.isActive == true
        }

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

        deinit {
            assert(!self.isConnected, "LGNS.Client must be disconnected explicitly")
        }

        public func connectIfNeeded(at address: LGNCore.Address) -> Future<Void> {
            if self.isConnected {
                return self.eventLoopGroup.next().makeSucceededFuture()
            }

            return self.connect(at: address)
        }

        public func connect(at address: LGNCore.Address, reconnectIfNeeded: Bool = true) -> Future<Void> {
            let eventLoop = self.eventLoopGroup.next()

            guard self.channel == nil else {
                return eventLoop.makeSucceededFuture()
            }

            var resultFuture: Future<Void> = eventLoop.makeSucceededFuture()

            if self.channel?.isActive == false && reconnectIfNeeded == true {
                resultFuture = self.disconnect()
            }

            return resultFuture.flatMap {
                let connectProfiler = LGNCore.Profiler.begin()

                let clientHandler = LGNS.ClientHandler() { message, context in
                    self.responsePromise?.succeed((message, context))
                    if !message.controlBitmask.contains(.keepAlive), let channel = self.channel {
                        return channel.close().map { nil }
                    }
                    return self.eventLoopGroup.next().makeSucceededFuture(nil)
                }
                self.clientHandler = clientHandler

                let connectFuture = ClientBootstrap(group: self.eventLoopGroup)
                    .connectTimeout(.seconds(3))
                    .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                    .channelInitializer { channel in
                        channel.pipeline.addHandlers(
                            IdleStateHandler(
                                readTimeout: self.readTimeout,
                                writeTimeout: self.writeTimeout,
                                allTimeout: self.readTimeout
                            ),
                            LGNS.LGNPCoder(
                                cryptor: self.cryptor,
                                requiredBitmask: self.controlBitmask,
                                validateRequiredBitmask: false
                            ),
                            clientHandler
                        )
                    }
                    .connect(to: address, defaultPort: LGNS.Server.defaultPort)

                connectFuture.whenComplete { result in
                    let resultString: String
                    switch result {
                    case .success(let channel):
                        self.channel = channel
                        resultString = "succeeded"
                    case .failure(let error):
                        self.responsePromise?.fail(error)
                        resultString = "failed"
                    }

                    Self.logger.debug(
                        "Connection to \(address) \(resultString) in \(connectProfiler.end().rounded(toPlaces: 4))s"
                    )
                }

                return connectFuture.map { _ in Void() }
            }
        }

        public func disconnect(on eventLoop: EventLoop? = nil) -> Future<Void> {
            guard let channel = self.channel else {
                return (eventLoop ?? self.eventLoopGroup.next()).makeSucceededFuture()
            }

            return channel.close().map {
                self.channel = nil
                self.responsePromise = nil
                self.clientHandler = nil
            }
        }

        public func request(
            at address: LGNCore.Address,
            with message: LGNP.Message,
            on eventLoop: EventLoop? = nil
        ) -> Future<Response> {
            if self.responsePromise != nil {
                Self.logger.warning("Trying to do a request while there is an existing promise")
            }

            let eventLoop = eventLoop ?? self.eventLoopGroup.next()

            let responsePromise: Promise<Response> = eventLoop.makePromise()
            self.responsePromise = responsePromise
            self.clientHandler?.promise = self.responsePromise

            return self
                .connectIfNeeded(at: address)
                .flatMap { self.channel!.writeAndFlush(message) }
                .flatMap { responsePromise.futureResult }
                .flatMap { response in
                    let result: Future<Void>

                    if !message.controlBitmask.contains(.keepAlive) {
                        result = self.disconnect()
                    } else {
                        result = eventLoop.makeSucceededFuture()
                    }

                    return result.map { response }
                }
        }

        public func singleRequest(
            at address: LGNCore.Address,
            with message: LGNP.Message,
            on eventLoop: EventLoop? = nil
        ) -> Future<Response> {
            let cloned = self.cloned()

            return cloned
                .request(at: address, with: message, on: eventLoop)
                .flatMap { response in cloned.disconnect(on: eventLoop).map { response } }
        }

        public func cloned() -> Self {
            Self(
                cryptor: self.cryptor,
                controlBitmask: self.controlBitmask,
                eventLoopGroup: self.eventLoopGroup,
                readTimeout: self.readTimeout,
                writeTimeout: self.writeTimeout
            )
        }
    }
}
