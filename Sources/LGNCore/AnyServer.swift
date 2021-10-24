import Foundation
import LGNLog
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
        Logger.current.info("Trying to bind at \(self.address)")

        do {
            self.channel = try await self.bootstrap.bind(to: self.address, defaultPort: Self.defaultPort)
            self.isRunning = true
            Logger.current.info("Succesfully started on \(self.address)")
        } catch {
            Logger.current.info("Could not start on \(self.address): \(error)")
            throw error
        }
    }

    func waitForStop() throws {
        guard self.isRunning, self.channel != nil else {
            Logger.current.warning("Trying to wait for a server that is not running")
            return
        }

        try self.channel.closeFuture.wait()
    }

    func shutdown() async throws {
        guard self.channel != nil else {
            return
        }

        Logger.current.info("Shutting down")

        do {
            try await self.channel.close()
            self.isRunning = false
            self.channel = nil
            Logger.current.info("Goodbye")
        } catch {
            Logger.current.info("Could not shutdown: \(error)")
        }
    }
}
