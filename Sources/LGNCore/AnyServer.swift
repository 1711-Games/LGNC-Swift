import Foundation
import Logging
import NIO

/// A type-erased server type
public protocol AnyServer: AnyObject {
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
    /// Method returns when server is started
    func bind() async throws

    /// Performs server shutdown and returns when server is down
    func shutdown() async throws

    /// Blocks current thread until server is stopped.
    /// This method **must not** be called in `EventLoop` context, only on dedicated threads/dispatch queues/main thread
    func waitForStop() throws
}

public extension AnyServer {
    fileprivate var name: String { "\(type(of: self))" }

    func bind() async throws {
        Self.logger.info("LGNS Server: Trying to bind at \(self.address)")

        do {
            self.channel = try await self.bootstrap.bind(to: self.address, defaultPort: Self.defaultPort)
            self.isRunning = true
            Self.logger.info("LGNS Server: Succesfully started on \(self.address)")
        } catch {
            Self.logger.info("LGNS Server: Could not start on \(self.address): \(error)")
        }
    }

    func waitForStop() throws {
        guard self.isRunning, self.channel != nil else {
            Self.logger.warning("Trying to wait for a server that is not running")
            return
        }

        try self.channel.closeFuture.wait()
    }

    func shutdown() async throws {
        Self.logger.info("LGNS Server: Shutting down")

        do {
            try await self.channel.close()
            self.isRunning = false
            self.channel = nil
            Self.logger.info("LGNS Server: Goodbye")
        } catch {
            Self.logger.info("LGNS Server: Could not shutdown: \(error)")
        }
    }
}
