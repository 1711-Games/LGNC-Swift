import Entita2
import LGNCore
import FDB
import NIO

public typealias E2FDBIndex = Entita2FDBIndex

public protocol Entita2FDBModel: E2Entity where Storage == FDB, Identifier: TuplePackable {
    static var subspace: Subspace { get }
    static var indices: [String: Entita2FDBIndex<Self>] { get }
    
    static func loadByIndex(name: String, value: TuplePackable, on eventLoop: EventLoop) -> Future<Self?>
    static func existsByIndex(name: String, value: TuplePackable, on eventLoop: EventLoop) -> Future<Bool>
}

public class Entita2FDBIndex<T: Entita2FDBModel> {
    public unowned let path: PartialKeyPath<T>
    public let type: Any.Type
    public var previousValue: Any! = nil

    public init(_ path: PartialKeyPath<T>) {
        self.path = path
    }

    private func compare0<T: Comparable>(t: T.Type, lhs: Any, rhs: Any) -> Bool {
        guard let lhs = lhs as? T, let rhs = rhs as? T else { return false }

        return lhs == rhs
    }

    public func compare<T: Comparable>(with originalValue: T) -> Bool {
        return self.compare0(t: T.self, lhs: self.previousValue!, rhs: originalValue)
    }
}

extension FDB: E2Storage {
    public func load(by key: Bytes, on eventLoop: EventLoop) -> Future<Bytes?> {
        return self
            .begin(eventLoop: eventLoop)
            .then { transaction in
                self
                    .load(by: key, with: transaction, on: eventLoop)
                    .then { maybeBytes in transaction.commit().map { _ in maybeBytes } }
            }
    }
    
    public func load(
        by key: Bytes,
        with transaction: Transaction,
        on eventLoop: EventLoop
    ) -> Future<Bytes?> {
        return transaction
            .get(key: key)
            .map { $0.0 }
    }

    public func loadAll(
        by range: RangeFDBKey,
        limit: Int32 = 0,
        on eventLoop: EventLoop
    ) -> Future<KeyValuesResult> {
        return self
            .begin(eventLoop: eventLoop)
            .then { $0.get(range: range, limit: limit) }
            .map { $0.0 }
    }

    public func save(bytes: Bytes, by key: Bytes, on eventLoop: EventLoop) -> Future<Void> {
        return self
            .begin(eventLoop: eventLoop)
            .then { transaction in
                self
                    .save(bytes: bytes, by: key, with: transaction, on: eventLoop)
                    .then { transaction.commit() }
            }
    }
    
    public func save(
        bytes: Bytes,
        by key: Bytes,
        with transaction: Transaction,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        return transaction
            .set(key: key, value: bytes)
            .map { _ in () }
    }

    public func delete(by key: Bytes, on eventLoop: EventLoop) -> Future<Void> {
        return self
            .begin(eventLoop: eventLoop)
            .then { $0.clear(key: key, commit: true) }
            .map { _ in () }
    }
}

public extension Entita2FDBModel {
    public static var indices: [String: Entita2FDBIndex<Self>] {
        return [:]
    }

    public static var format: E2.Format {
        return .MsgPack
    }
    
    public static var idxSubspace: Subspace {
        return Self.subspace["idx"]
    }
    
    public static func getIndexKeyForIndex(name: String, value: TuplePackable) -> FDBKey {
        return Self.idxSubspace[Self.entityName][name][value]
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
    
    fileprivate func getIndexValueFrom(index path: PartialKeyPath<Self>) -> TuplePackable? {
        guard let value = self[keyPath: path] as? TuplePackable else {
            LGNCore.log("Invalid index '\(path)' for entity '\(Self.entityName)', not converting to TuplePackable")
            return nil
        }
        return value
    }

    public func afterLoad0(on eventLoop: EventLoop) -> Future<Void> {
        for (_, index) in Self.indices {
            index.previousValue = self[keyPath: index.path]
        }
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterInsert0(on eventLoop: EventLoop) -> Future<Void> {
        return EventLoopFuture<Void>.andAll(
            Self.indices.map { indexName, index in
                guard let value = self.getIndexValueFrom(index: index.path) else {
                    return eventLoop.newSucceededFuture(result: ())
                }
                return Self.storage
                    .begin(eventLoop: eventLoop)
                    .then {
                        $0.set(
                            key: Self.getIndexKeyForIndex(name: indexName, value: value),
                            value: self.getID()._bytes,
                            commit: true
                        )
                    }
                    .map { _ in () }
            },
            eventLoop: eventLoop
        )
    }

    public func afterSave0(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return EventLoopFuture<Void>.andAll(
            Self.indices.map { indexName, index in
                guard index.compare(with: self[keyPath: index.path] as! Comparable) else {
                    return eventLoop.newSucceededFuture(result: ())
                }
            },
            eventLoop: eventLoop
        )
    }

    public func afterDelete0(on eventLoop: EventLoop) -> Future<Void> {
        return EventLoopFuture<Void>.andAll(
            Self.indices.map { indexName, index in
                guard let value = self.getIndexValueFrom(index: index.path) else {
                    return eventLoop.newSucceededFuture(result: ())
                }
                return Self.storage
                    .begin(eventLoop: eventLoop)
                    .then { $0.clear(key: Self.getIndexKeyForIndex(name: indexName, value: value), commit: true) }
                    .map { _ in () }
            },
            eventLoop: eventLoop
        )
    }

    private static func isValidIndex(name: String) -> Bool {
        guard let _ = Self.indices[name] else {
            LGNCore.log("Index '\(name)' not found in entity '\(Self.entityName)' (available indices: \(Self.indices.keys.joined(separator: ", ")))")
            return false
        }
        return true
    }
    
    public static func loadByIndex(name: String, value: TuplePackable, on eventLoop: EventLoop) -> Future<Self?> {
        guard Self.isValidIndex(name: name) else {
            return eventLoop.newSucceededFuture(result: nil)
        }

        return self.storage
            .begin(eventLoop: eventLoop)
            .then { $0.get(key: Self.getIndexKeyForIndex(name: name, value: value)) }
            .then { maybeIDBytes, _ in
                guard let IDBytes = maybeIDBytes else {
                    return eventLoop.newSucceededFuture(result: nil)
                }
                return Self.loadBy(IDBytes: IDBytes, on: eventLoop)
            }
    }
    
    public static func existsByIndex(name: String, value: TuplePackable, on eventLoop: EventLoop) -> Future<Bool> {
        guard Self.isValidIndex(name: name) else {
            return eventLoop.newSucceededFuture(result: false)
        }
        
        return self.storage
            .begin(eventLoop: eventLoop)
            .then { $0.get(key: Self.getIndexKeyForIndex(name: name, value: value)) }
            .map { maybeIDBytes, _ in maybeIDBytes != nil }
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
        return self.storage
            .begin(eventLoop: eventLoop)
            .then { (transaction) -> Future<(Bytes?, Transaction)> in
                dump(ID)
                dump(Self.IDAsKey(ID: ID)._string)
                return self.storage
                    .load(by: Self.IDAsKey(ID: ID), with: transaction, on: eventLoop)
                    .map { maybeBytes in (maybeBytes, transaction) }
            }
            .thenThrowing { (maybeBytes, transaction) in
                guard let bytes = maybeBytes else {
                    return (nil, transaction)
                }
                return (
                    try Self.init(from: bytes, format: Self.format),
                    transaction
                )
            }
    }

    public func save(
        with transaction: Transaction,
        on eventLoop: EventLoop
    ) -> Future<Transaction> {
        return self
            .getPackedSelf(on: eventLoop)
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
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.storage.loadAll(
            by: subspace.range,
            limit: limit,
            on: eventLoop
        ).thenThrowing { results in
            Dictionary(
                uniqueKeysWithValues: try results.records.map {
                    let instance = try Self.init(from: $0.value)
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
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.loadAll(bySubspace: self.subspacePrefix, limit: limit, on: eventLoop)
    }

    public static func loadAll(
        by key: FDBKey,
        limit: Int32 = 0,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.loadAll(bySubspace: self.subspacePrefix[key], limit: limit, on: eventLoop)
    }

    public static func loadAllRaw(
        limit: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        on eventLoop: EventLoop
    ) -> Future<KeyValuesResult> {
        return self.storage.loadAll(by: self.subspacePrefix.range, limit: limit, on: eventLoop)
    }
}

public typealias E2FDBModel = Entita2FDBModel
