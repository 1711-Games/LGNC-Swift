import Foundation
import LGNLog
import NIO
import ServiceLifecycle

public typealias LGNCoreServer = Server

/// A type-erased server type
public protocol Server: AnyObject, ServiceLifecycle.Service {
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
    @Sendable
    func bind() async throws

    /// Performs server shutdown and returns when server is down
    @Sendable
    func shutdown() async throws

    /// Performs server shutdown and returns when server is down
    /// This method **must not** be called in `EventLoop` context, only on dedicated threads/dispatch queues/main thread
    @Sendable
    func shutdown()

    /// Blocks current thread until server is stopped.
    /// This method **must not** be called in `EventLoop` context, only on dedicated threads/dispatch queues/main thread
    func waitForStop() throws
}

public extension Server {
    fileprivate var name: String { "\(type(of: self))" }

    @Sendable
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

    @Sendable
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

    @Sendable
    func shutdown() {
        guard self.channel != nil else {
            return
        }

        Logger.current.info("Shutting down")

        do {
            try self.channel.close().wait()
            self.isRunning = false
            self.channel = nil
            Logger.current.info("Goodbye")
        } catch {
            Logger.current.info("Could not shutdown: \(error)")
        }
    }

    func run() async throws {
        try await withGracefulShutdownHandler {
            try await self.bind()
            _ = try await self.channel.closeFuture.get()
        } onGracefulShutdown: {
            self.shutdown()
        }
    }
}
