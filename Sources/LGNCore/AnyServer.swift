import Foundation
import Logging
import NIO

/// A type-erased server type
public protocol AnyServer: class {
    /// Indicates whether server is running (and serving requests) or not
    var isRunning: Bool { get set }

    /// A NIO Channel
    var channel: Channel! { get set }

    /// A NIO ServerBootstrap
    var bootstrap: ServerBootstrap! { get }

    var eventLoopGroup: EventLoopGroup { get }

    var address: LGNCore.Address { get }

    static var logger: Logger { get }
    static var defaultPort: Int { get }

    /// Binds to an address and starts a server,
    /// `Void` future is fulfilled when server is started
    func bind() -> EventLoopFuture<Void>

    /// Performs server shutdown and return a `Void` future when server is down
    func shutdown() -> EventLoopFuture<Void>

    /// Blocks current thread until server is stopped.
    /// This method **must not** be called in `EventLoop` context, only on dedicated threads/dispatch queues/main thread
    func waitForStop() throws
}

public extension AnyServer {
    fileprivate var name: String { "\(type(of: self))" }

    func bind() -> EventLoopFuture<Void> {
        Self.logger.info("LGNS Server: Trying to bind at \(self.address)")

        let bindFuture: EventLoopFuture<Channel> = self.bootstrap.bind(to: self.address, defaultPort: Self.defaultPort)

        bindFuture.whenComplete { result in
            switch result {
            case .success(_): Self.logger.info("LGNS Server: Succesfully started on \(self.address)")
            case let .failure(error): Self.logger.info("LGNS Server: Could not start on \(self.address): \(error)")
            }
        }

        return bindFuture.map {
            self.channel = $0
            self.isRunning = true
        }
    }

    func waitForStop() throws {
        guard self.isRunning, self.channel != nil else {
            Self.logger.warning("Trying to wait for a server that is not running")
            return
        }

        try self.channel.closeFuture.wait()
    }

    func shutdown() -> EventLoopFuture<Void> {
        let promise: PromiseVoid = self.eventLoopGroup.next().makePromise()

        Self.logger.info("LGNS Server: Shutting down")

        self.channel.close(promise: promise)

        promise.futureResult.whenComplete { result in
            switch result {
            case .success(_): Self.logger.info("LGNS Server: Goodbye")
            case let .failure(error): Self.logger.info("LGNS Server: Could not shutdown: \(error)")
            }
        }

        return promise.futureResult.map {
            self.isRunning = false
            self.channel = nil
        }
    }
}
