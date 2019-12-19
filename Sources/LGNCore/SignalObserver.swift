import Foundation
import NIO
import NIOConcurrencyHelpers

/// Helper class for shutting down all working services after signals like `SIGINT`, `SIGTERM` etc.
/// All new services (like `LGNS.Server`) are automatically registered in this class.
///
/// Recommended usage (put it in `main.swift`):
/** ```
let trap: @convention(c) (Int32) -> Void = { s in
    print("Received signal \(s)")

    /// `SignalObserver.fire` returns a `Future` which is succeded only when all serers are correctly down.
    /// Shouldn't be afraid of blocking `wait()` and `try!` as there is nothing much to lose should we fail :)
    _  = try! SignalObserver.fire(signal: s).wait()

    print("Shutdown routines done")
}

signal(SIGINT, trap)
signal(SIGTERM, trap)
``` */
public class SignalObserver {
    private struct Box {
        weak var value: Shutdownable?
    }

    private static var instances: [Box] = []
    private static var lock: Lock = Lock()

    public static var eventLoop: EventLoop = EmbeddedEventLoop()

    private init() {}

    public class func fire(signal _: Int32) -> Future<Void> {
        var futures: [Future<Void>] = []

        instances.forEach {
            let promise: Promise<Void> = self.eventLoop.makePromise()
            futures.append(promise.futureResult)
            $0.value?.shutdown(promise: promise)
        }
        instances.removeAll()

        return Future<Void>.andAllComplete(futures, on: eventLoop)
    }

    public class func add(_ instance: Shutdownable) {
        self.lock.withLockVoid {
            self.instances.append(Box(value: instance))
        }
    }
}
