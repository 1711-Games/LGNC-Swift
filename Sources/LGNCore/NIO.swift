import NIO

public extension EventLoopFuture {
    // TODO deprecate
    func mapThrowing<NewValue>(
        file: StaticString = #file,
        line: UInt = #line,
        _ callback: @escaping (Value) throws -> NewValue
    ) -> Future<NewValue> {
        return self.flatMapThrowing(file: file, line: line, callback)
    }
}

public extension EventLoop {
    /// Creates and returns a new void `EventLoopFuture` that is already marked as success.
    /// Notifications will be done using this `EventLoop` as execution `NIOThread`.
    ///
    /// - parameters:
    ///     - result: the value that is used by the `EventLoopFuture`.
    /// - returns: a succeeded `EventLoopFuture`.
    func makeSucceededFuture(file: StaticString = #file, line: UInt = #line) -> EventLoopFuture<Void> {
        return self.makeSucceededFuture((), file: file, line: line)
    }
}

public extension ClientBootstrap {
    func connect(to address: LGNCore.Address, defaultPort: Int) -> Future<Channel> {
        switch address {
        case let .ip(host, port):
            return self.connect(host: host, port: port)
        case .localhost:
            return self.connect(host: "127.0.0.1", port: defaultPort)
        case let .unixDomainSocket(path):
            return self.connect(unixDomainSocketPath: path)
        }
    }
}

public extension ServerBootstrap {
    func bind(to address: LGNCore.Address, defaultPort: Int) -> Future<Channel> {
        switch address {
        case let .ip(host, port):
            return self.bind(host: host, port: port)
        case .localhost:
            return self.bind(host: "127.0.0.1", port: defaultPort)
        case let .unixDomainSocket(path):
            return self.bind(unixDomainSocketPath: path)
        }
    }
}
