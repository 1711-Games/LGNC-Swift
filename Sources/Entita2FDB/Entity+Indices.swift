import LGNCore
import NIO

public extension E2 {
    public class Index<M: Entita2FDBIndexedEntity> {
        internal let path: PartialKeyPath<M>

        public init<V: TuplePackable>(_ path: KeyPath<M, V>) {
            self.path = path
        }

        internal func getTuplePackableValue(from instance: M) -> TuplePackable? {
            return (instance[keyPath: self.path] as? TuplePackable)
        }
    }
}

public protocol Entita2FDBIndexedEntity: E2FDBEntity {
    static var indices: [String: E2.Index<Self>] { get }
    static var idxSubspace: Subspace { get }

    static func getIndexKeyForIndex(name: TuplePackable, value: TuplePackable) -> FDBKey

    static func loadByIndex(
        name: String,
        value: TuplePackable,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Self?>
    static func existsByIndex(name: String, value: TuplePackable, on eventLoop: EventLoop) -> Future<Bool>

    func getIndexIndexSubspace() -> Subspace
}

public extension Entita2FDBIndexedEntity {
    public static var idxSubspace: Subspace {
        return Self.subspace["idx"]
    }

    fileprivate func getIndexValueFrom(index: E2.Index<Self>) -> TuplePackable? {
        return index.getTuplePackableValue(from: self)
    }

    public func getIndexIndexSubspace() -> Subspace {
        return Subspace(self.getIDAsKey())["idx"]
    }
    
    public static func getIndexKeyForIndex(name: TuplePackable, value: TuplePackable) -> FDBKey {
        return Self.idxSubspace[Self.entityName][name][value]
    }

    private func createIndex(
        _ indexName: TuplePackable,
        for index: E2.Index<Self>,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        guard let value = self.getIndexValueFrom(index: index) else {
            return eventLoop.newFailedFuture(
                error: E2.E.IndexError(
                    "Could not get tuple packable value for index '\(indexName)' in entity '\(Self.entityName)'"
                )
            )
        }
        let indexIndexSubspace = self.getIndexIndexSubspace()
        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { $0.set(key: Self.getIndexKeyForIndex(name: indexName, value: value), value: self.getIDAsKey()) }
            .then { $0.set(key: indexIndexSubspace[indexName][value], value: []) }
            .map { _ in () }
    }

    public func afterInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return EventLoopFuture<Void>.andAll(
            Self.indices.map { self.createIndex($0.key, for: $0.value, with: transaction, on: eventLoop) },
            eventLoop: eventLoop
        )
    }

    public func afterDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return EventLoopFuture<Void>.andAll(
            Self.indices.map { indexName, index in
                guard let value = self.getIndexValueFrom(index: index) else {
                    return eventLoop.newSucceededFuture(result: ())
                }
                return Self.storage
                    .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
                    .then { $0.clear(key: Self.getIndexKeyForIndex(name: indexName, value: value)) }
                    .map { _ in () }
            },
            eventLoop: eventLoop
        ).then {
            Self.storage
                .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
                .then { $0.clear(range: Subspace(self.getIDAsKey()).range) }
                .map { _ in () }
        }
    }

    fileprivate func updateIndices(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        let IDKeySubspace = self.getIndexIndexSubspace()
        let future: Future<Void> = Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { $0.get(range: IDKeySubspace.range) }
            .then { tuple in
                let (keyValueRecords, transaction) = tuple

                var result: Future<Void> = eventLoop.newSucceededFuture(result: ())

                for record in keyValueRecords.records {
                    let key = Tuple(from: record.key)
                    let tuples = key.tuple.compactMap { $0 }
                    guard tuples.count >= 2 else {
                        continue
                    }
                    let indexNameErased = tuples[tuples.count - 2]
                    let indexValue = tuples[tuples.count - 1]
                    
                    guard let indexName = indexNameErased as? String else {
                        return eventLoop.newFailedFuture(
                            error: E2.E.IndexError(
                                "Could not cast '\(indexNameErased)' as String in entity '\(Self.entityName)'"
                            )
                        )
                    }
                    guard let index = Self.indices[indexName] else {
                        return eventLoop.newFailedFuture(
                            error: E2.E.IndexError(
                                "No index \(indexName) in entity '\(Self.entityName)'"
                            )
                        )
                    }
                    guard let propertyValue = self.getIndexValueFrom(index: index) else {
                        return eventLoop.newFailedFuture(
                            error: E2.E.IndexError(
                                "Could not get property value for index \(indexName) in entity '\(Self.entityName)'"
                            )
                        )
                    }
                    let probablyNewIndexKey = Self.getIndexKeyForIndex(name: indexName, value: propertyValue)
                    let previousIndexKey = Self.getIndexKeyForIndex(name: indexName, value: indexValue)
                    
                    if previousIndexKey.asFDBKey() != probablyNewIndexKey.asFDBKey() {
                        result = result
                            .then { transaction.clear(key: previousIndexKey) }
                            .then { _ in transaction.clear(key: key) }
                            .then { _ in self.createIndex(indexName, for: index, with: transaction, on: eventLoop) }
                    }
                }

                return result
            }
        return future
    }

    public func afterSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.updateIndices(with: transaction, on: eventLoop)
    }

    private static func isValidIndex(name: String) -> Bool {
        guard let _ = Self.indices[name] else {
            LGNCore.log("Index '\(name)' not found in entity '\(Self.entityName)' (available indices: \(Self.indices.keys.joined(separator: ", ")))")
            return false
        }
        return true
    }

    public static func loadByIndex(
        name: String,
        value: TuplePackable,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        guard Self.isValidIndex(name: name) else {
            return eventLoop.newSucceededFuture(result: nil)
        }

        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { $0.get(key: Self.getIndexKeyForIndex(name: name, value: value)) }
            .then { maybeIDBytes, transaction in
                guard let IDBytes = maybeIDBytes else {
                    return eventLoop.newSucceededFuture(result: nil)
                }
                return Self.loadByRaw(IDBytes: IDBytes, with: transaction, on: eventLoop)
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
}
