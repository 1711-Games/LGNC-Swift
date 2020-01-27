import Foundation
import Logging
import NIO

/// Any shutdownable service (most commonly, a server)
public protocol Shutdownable: class {
    /// A method which must eventually shutdown current service and fulfill a returned future with `Void` or an error
    func shutdown() -> Future<Void>
}

public protocol AnyServer: Shutdownable {
    /// Indicates whether server is running (and serving requests) or not
    var isRunning: Bool { get set }

    var channel: Channel! { get set }

    var bootstrap: ServerBootstrap! { get }

    var eventLoopGroup: EventLoopGroup { get }

    static var logger: Logger { get }
    static var defaultPort: Int { get }

    /// Binds to a given address and starts a server,
    /// `Void` future is fulfilled when server is started
    func bind(to address: LGNCore.Address) -> Future<Void>

    /// Blocks current thread until server is stopped.
    /// This method **must not** be called in `EventLoop` context, only on dedicated threads/dispatch queues/main thread
    func waitForStop() throws
}

public extension AnyServer {
    fileprivate var name: String { "\(type(of: self))" }

    func bind(to address: LGNCore.Address) -> Future<Void> {
        Self.logger.info("LGNS Server: Trying to bind at \(address)")

        let bindFuture: Future<Channel> = self.bootstrap.bind(to: address, defaultPort: Self.defaultPort)

        bindFuture.whenComplete { result in
            switch result {
            case .success(_): Self.logger.info("LGNS Server: Succesfully started on \(address)")
            case let .failure(error): Self.logger.info("LGNS Server: Could not start on \(address): \(error)")
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

    func shutdown() -> Future<Void> {
        let promise: Promise<Void> = self.eventLoopGroup.next().makePromise()

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
