import Foundation
import NIO

public protocol Shutdownable: class {
    func shutdown(promise: PromiseVoid)
}

public class SignalObserver {
    private struct Box {
        weak var value: Shutdownable?
    }

    private static var instances: [Box] = []
    public static var eventLoop: EventLoop = EmbeddedEventLoop()

    private init() {}

    public class func fire(signal _: Int32) -> FutureVoid {
        var futures: [FutureVoid] = []

        self.instances.forEach {
            let promise: PromiseVoid = self.eventLoop.newPromise()
            futures.append(promise.futureResult)
            $0.value?.shutdown(promise: promise)
        }
        self.instances.removeAll()

        return FutureVoid.andAll(futures, eventLoop: self.eventLoop)
    }

    public class func add(_ instance: Shutdownable) {
        self.instances.append(Box(value: instance))
    }
}
