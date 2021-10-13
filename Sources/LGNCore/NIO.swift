import NIO

public extension ClientBootstrap {
    func connect(to address: LGNCore.Address, defaultPort: Int) async throws -> Channel {
        try await { () -> EventLoopFuture<Channel> in
            switch address {
            case let .ip(host, port):
                return self.connect(host: host, port: port)
            case .localhost:
                return self.connect(host: "127.0.0.1", port: defaultPort)
            case let .unixDomainSocket(path):
                return self.connect(unixDomainSocketPath: path)
            }
        }().value
    }
}

public extension ServerBootstrap {
    func bind(to address: LGNCore.Address, defaultPort: Int) async throws -> Channel {
        try await { () -> EventLoopFuture<Channel> in
            switch address {
            case let .ip(host, port):
                return self.bind(host: host, port: port)
            case .localhost:
                return self.bind(host: "127.0.0.1", port: defaultPort)
            case let .unixDomainSocket(path):
                return self.bind(unixDomainSocketPath: path)
            }
        }().value
    }
}
