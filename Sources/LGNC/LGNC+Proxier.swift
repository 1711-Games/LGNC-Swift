import Foundation
import LGNCore
import LGNS
import NIO
import NIOHTTP1

public extension LGNC {
    public class Proxier: Shutdownable {
        private let cryptor: LGNP.Cryptor

        private let bootstrap: ServerBootstrap
        private let client: LGNS.Client
        private var channel: Channel!
        
        public required init(
            registry: LGNC.ServicesRegistry,
            cryptor: LGNP.Cryptor,
            requiredBitmask: ControlBitmask,
            hostFormat: String,
            eventLoopGroup: MultiThreadedEventLoopGroup,
            readTimeout: Time = .seconds(1),
            writeTimeout: Time = .seconds(1)
        ) throws {
            self.cryptor = cryptor
            
            let client = try LGNS.Client(
                cryptor: cryptor,
                controlBitmask: requiredBitmask,
                eventLoopGroup: eventLoopGroup
            )
            self.client = client

            self.bootstrap = ServerBootstrap(group: eventLoopGroup)
                // Specify backlog and enable SO_REUSEADDR for the server itself
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                
                // Set the handlers that are applied to the accepted Channels
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).then {
                        channel.pipeline.add(
                            handler: LGNC.Proxier.HTTPHandler(
                                client: client,
                                registry: registry,
                                hostFormat: hostFormat
                            )
                        )
                    }
                }
                
                // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
                .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            
            SignalObserver.add(self)
        }
        
        public func shutdown(promise: PromiseVoid) {
            print("LGNS: shutting down")
            self.channel.close(promise: promise)
            print("LGNS: goodbye")
        }
        
        public func serve(at target: LGNS.Address, promise: PromiseVoid? = nil) throws {
            self.channel = try self.bootstrap.bind(to: target).wait()
            
            promise?.succeed(result: ())
            
            try self.channel.closeFuture.wait()
        }
    }
}

