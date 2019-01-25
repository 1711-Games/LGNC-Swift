import Entita2
import FDB
import LGNCore
import NIO

public protocol Entita2FDBEntity: E2Entity where Storage == FDB, Identifier: TuplePackable {
    static var subspace: Subspace { get }
}

extension Transaction: AnyTransaction {}

public extension Entita2FDBEntity {
    public static var format: E2.Format {
        return .MsgPack
    }
    
    public static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?> {
        return Self.storage.begin(eventLoop: eventLoop).map { $0 }
    }

    public static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        return Self.subspacePrefix[bytes].asFDBKey()
    }

    public static func IDAsKey(ID: Identifier) -> Bytes {
        return Self.subspacePrefix[ID].asFDBKey()
    }

    public static func doesRelateToThis(tuple: Tuple) -> Bool {
        let flat = tuple.tuple.compactMap { $0 }
        guard flat.count >= 2 else {
            return false
        }
        guard let value = flat[flat.count - 2] as? String, value == self.entityName else {
            return false
        }
        return true
    }

    public func getIDAsKey() -> Bytes {
        return Self.IDAsKey(ID: self.getID())
    }

    public static var subspacePrefix: Subspace {
        return self.subspace[self.entityName]
    }

    public static func loadWithTransaction(
        by ID: Identifier,
        on eventLoop: EventLoop
    ) -> Future<(Self?, Transaction)> {
        return storage
            .begin(eventLoop: eventLoop)
            .then { (transaction) -> Future<(Bytes?, Transaction)> in
                self.storage
                    .load(by: Self.IDAsKey(ID: ID), with: transaction, on: eventLoop)
                    .map { maybeBytes in (maybeBytes, transaction) }
            }
            .thenThrowing { maybeBytes, transaction in
                guard let bytes = maybeBytes else {
                    return (nil, transaction)
                }
                return (
                    try Self(from: bytes, format: Self.format),
                    transaction
                )
            }
    }

    public func save(
        with transaction: Transaction,
        on eventLoop: EventLoop
    ) -> Future<Transaction> {
        return self.getPackedSelf(on: eventLoop)
            .then { payload in
                Self.storage.save(
                    bytes: payload,
                    by: self.getIDAsKey(),
                    with: transaction,
                    on: eventLoop
                )
            }
            .map { _ in transaction }
    }

    internal static func loadAll(
        bySubspace subspace: Subspace,
        limit: Int32 = 0,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return storage.loadAll(
            by: subspace.range,
            limit: limit,
            with: transaction,
            on: eventLoop
        ).thenThrowing { results in
            Dictionary(
                uniqueKeysWithValues: try results.records.map {
                    let instance = try Self(from: $0.value)
                    return (
                        instance.getID(),
                        instance
                    )
                }
            )
        }
    }

    public static func loadAll(
        limit: Int32 = 0,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.loadAll(bySubspace: subspacePrefix, limit: limit, with: transaction, on: eventLoop)
    }

    public static func loadAll(
        by key: FDBKey,
        limit: Int32 = 0,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return loadAll(bySubspace: subspacePrefix[key], limit: limit, with: transaction, on: eventLoop)
    }

    public static func loadAllRaw(
        limit: Int32 = 0,
        mode _: FDB.StreamingMode = .WantAll,
        iteration _: Int32 = 1,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<KeyValuesResult> {
        return storage.loadAll(by: subspacePrefix.range, limit: limit, with: transaction, on: eventLoop)
    }
}

public typealias E2FDBEntity = Entita2FDBEntity
