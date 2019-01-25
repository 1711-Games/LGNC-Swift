import LGNCore

public protocol AnyTransaction {
    func commit() -> Future<Void>
}
