import Foundation

/// Any shutdownable service (most commonly, a server)
public protocol Shutdownable: class {
    /// A method which must eventually shutdown current service and complete provided promise with `Void` or an error
    func shutdown(promise: PromiseVoid)
}

public protocol Server: Shutdownable {
    func serve(at address: LGNCore.Address, promise: PromiseVoid?) throws
    func nonBlockingServe(at address: LGNCore.Address, queue: DispatchQueue, promise: PromiseVoid?)
}
