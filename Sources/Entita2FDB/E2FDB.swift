import Entita2
import FDB
import LGNCore
import NIO

public protocol Entita2FDBEntity: E2Entity where Identifier: FDBTuplePackable, Storage: E2FDBStorage {
    /// Root application FDB Subspace — `/[root_subspace]`
    static var subspace: FDB.Subspace { get }
}

extension FDB.Transaction: AnyTransaction {}
extension AnyFDBTransaction where Self: AnyTransaction {}

public extension Entita2FDBEntity {
    @inlinable static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?> {
        return Self.storage
            .begin(on: eventLoop)
            .map { $0 as? AnyTransaction }
    }

    static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        return Self.subspacePrefix[bytes].asFDBKey()
    }

    @inlinable static func IDAsKey(ID: Identifier) -> Bytes {
        return Self.subspacePrefix[ID].asFDBKey()
    }

    static func doesRelateToThis(tuple: FDB.Tuple) -> Bool {
        let flat = tuple.tuple.compactMap { $0 }
        guard flat.count >= 2 else {
            return false
        }
        guard let value = flat[flat.count - 2] as? String, value == self.entityName else {
            return false
        }
        return true
    }

    func getIDAsKey() -> Bytes {
        return Self.IDAsKey(ID: self.getID())
    }

    /// Current entity-related FDB Subspace — `/[root_subspace]/[entity_name]`
    static var subspacePrefix: FDB.Subspace {
        return self.subspace[self.entityName]
    }

    static func loadWithTransaction(
        by ID: Identifier,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<(Self?, AnyFDBTransaction)> {
        return storage.withTransaction(on: eventLoop) { transaction in
            Self
                .load(by: ID, within: transaction, snapshot: snapshot, on: eventLoop)
                .map { ($0, transaction) }
        }
    }

    static func load(
        by ID: Identifier,
        within transaction: AnyFDBTransaction,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        Self.load(by: ID, within: transaction as? AnyTransaction, snapshot: snapshot, on: eventLoop)
    }

    static func load(
        by ID: Identifier,
        within transaction: AnyTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        Self.storage
            .load(
                by: Self.IDAsKey(ID: ID),
                within: transaction,
                snapshot: snapshot,
                on: eventLoop
            )
            .flatMap { self.afterLoadRoutines0(maybeBytes: $0, on: eventLoop) }
    }

    static func loadAll(
        bySubspace subspace: FDB.Subspace,
        limit: Int32 = 0,
        within transaction: AnyTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<[(ID: Self.Identifier, value: Self)]> {
        return Self.storage.loadAll(
            by: subspace.range,
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        ).flatMapThrowing { results in
            try results.records.map {
                let instance = try Self(from: $0.value)
                return (
                    ID: instance.getID(),
                    value: instance
                )
            }
        }
    }

    static func loadAll(
        limit: Int32 = 0,
        within transaction: AnyTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<[(ID: Self.Identifier, value: Self)]> {
        return Self.loadAll(
            bySubspace: Self.subspacePrefix,
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        )
    }

    static func loadAll(
        by key: AnyFDBKey,
        limit: Int32 = 0,
        within transaction: AnyTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<[(ID: Self.Identifier, value: Self)]> {
        return Self.loadAll(
            bySubspace: Self.subspacePrefix[key],
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        )
    }

    static func loadAllRaw(
        limit: Int32 = 0,
        mode _: FDB.StreamingMode = .wantAll,
        iteration _: Int32 = 1,
        within transaction: AnyTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<FDB.KeyValuesResult> {
        return Self.storage.loadAll(
            by: Self.subspacePrefix.range,
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        )
    }
}

public typealias E2FDBEntity = Entita2FDBEntity
