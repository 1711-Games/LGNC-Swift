import NIO

/// A very abstract transaction
public protocol AnyTransaction {
    func commit() -> EventLoopFuture<Void>
}
