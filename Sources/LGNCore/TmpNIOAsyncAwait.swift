import NIO

// tmp
extension EventLoopFuture {
    @inlinable
    public var value: Value {
        get async throws {
            try await withUnsafeThrowingContinuation { cont in
                self.whenComplete { result in
                    switch result {
                    case .success(let value):
                        cont.resume(returning: value)
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }
}

extension Channel {
    @inlinable
    public func writeAndFlush<T>(_ any: T) async throws {
        try await self.writeAndFlush(any).value
    }
}

extension ChannelOutboundInvoker {
//    public func register(file: StaticString = #file, line: UInt = #line) async throws {
//        try await self.register(file: file, line: line).get()
//    }
//
//    public func bind(to address: SocketAddress, file: StaticString = #file, line: UInt = #line) async throws {
//        try await self.bind(to: address, file: file, line: line).get()
//    }
//
//    public func connect(to address: SocketAddress, file: StaticString = #file, line: UInt = #line) async throws {
//        try await self.connect(to: address, file: file, line: line).get()
//    }
//
    public func writeAndFlush(_ data: NIOAny, file: StaticString = #file, line: UInt = #line) async throws {
        try await self.writeAndFlush(data, file: file, line: line).value
    }

    public func close(mode: CloseMode = .all, file: StaticString = #file, line: UInt = #line) async throws {
        try await self.close(mode: mode, file: file, line: line).value
    }

//    public func triggerUserOutboundEvent(_ event: Any, file: StaticString = #file, line: UInt = #line) async throws {
//        try await self.triggerUserOutboundEvent(event, file: file, line: line).get()
//    }
}
