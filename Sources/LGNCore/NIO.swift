import NIO

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
