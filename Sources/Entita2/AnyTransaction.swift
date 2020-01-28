import NIO

/// A very abstract transaction
public protocol AnyTransaction {
    /// Commits current transaction
    func commit() -> EventLoopFuture<Void>
}
