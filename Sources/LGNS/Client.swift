import LGNCore
import LGNP
import NIO
import LGNLog

public extension LGNS {
    // todo add delegate

    /// A client for LGNS servers
    class Client {
        /// Response tuple type
        public typealias Response = (LGNP.Message, LGNCore.Context)

        public let controlBitmask: LGNP.Message.ControlBitmask
        public let cryptor: LGNP.Cryptor

        private let readTimeout: TimeAmount
        private let writeTimeout: TimeAmount

        public var channel: Channel? = nil
        private var clientHandler: LGNS.ClientHandler? = nil

        // todo: deprecate
        public var responsePromise: EventLoopPromise<Response>? = nil
        public let eventLoopGroup: EventLoopGroup

        /// Returns `true` if connection is alive
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

        /// Connects to a remote LGNS server at given address
        public func connect(at address: LGNCore.Address, reconnectIfNeeded: Bool = true) async throws {
            guard !self.isConnected else {
                return
            }

            if self.channel?.isActive == false && reconnectIfNeeded == true {
                try await self.disconnect()
            }

            let connectProfiler = LGNCore.Profiler()

            let clientHandler = LGNS.ClientHandler(promise: self.responsePromise, profiler: connectProfiler) { message in
                Logger.current.debug("Got LGNS response: \(message._payloadAsString)")
                self.responsePromise?.succeed((message, LGNCore.Context.current))
                return nil
            }

            self.clientHandler = clientHandler

            let bootstrap = ClientBootstrap(group: self.eventLoopGroup)
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

            let resultString: String

            do {
                self.channel = try await bootstrap.connect(to: address, defaultPort: LGNS.Server.defaultPort)
                resultString = "succeeded"
            } catch {
                self.responsePromise?.fail(error)
                resultString = "failed (\(error))"
            }

            Logger.current.debug(
                "Connection to \(address) \(resultString) in \(connectProfiler.mark("connection established").elapsed.rounded(toPlaces: 4))s"
            )
        }

        fileprivate func disconnectRoutine() {
            self.channel = nil
            self.responsePromise = nil
            self.clientHandler = nil
        }

        /// Disconnects from a remote LGNS server
        public func disconnect() async throws {
            defer { self.disconnectRoutine() }

            guard let channel = self.channel, channel.isActive, self.clientHandler?.isOpen == true else {
                return
            }

            do {
                try await channel.close()
            } catch ChannelError.alreadyClosed {
                // it's kinda fine
                return
            }
        }

        /// Sends a message to a remote LGNS server at given address.
        ///
        /// This method is not thread-safe, because an existing connection might be established, and other event loop might be waiting for a response.
        /// If you want to have a shared client for multi thread event loop group, use `singleRequest(at:with:on)` method which clones current instance
        /// every time for each request.
        public func request(
            at address: LGNCore.Address,
            with message: LGNP.Message,
            on eventLoop: EventLoop? = nil,
            file: String = #file, line: Int = #line
        ) async throws -> LGNP.Message {
            if self.responsePromise != nil {
                Logger.current.warning("Trying to do a request while there is an existing promise (@ \(file):\(line)")
            }

            let responsePromise: EventLoopPromise<Response> = (eventLoop ?? self.eventLoopGroup.next()).makePromise()
            self.responsePromise = responsePromise

            try await self.connect(at: address)
            try await self.channel?.writeAndFlush(message)
            let result = try await responsePromise.futureResult.get()

            if !result.0.controlBitmask.contains(.keepAlive) {
                try await self.disconnect()
            }

            self.responsePromise = nil

            return result.0
        }

        /// Sends a single message to a remote LGNS server at given address.
        ///
        /// This method differs from `request(at:with:on:)` because it clones current client instance before sending a request.
        public func singleRequest(
            at address: LGNCore.Address,
            with message: LGNP.Message,
            on eventLoop: EventLoop? = nil
        ) async throws -> LGNP.Message {
            let cloned = self.cloned()

            let result = try await cloned.request(at: address, with: message, on: eventLoop)

            try await cloned.disconnect()

            return result
        }

        /// Clones current client instance
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
