import LGNCore
import NIO
import FDB

public extension E2 {
    class Index<M: Entita2FDBIndexedEntity> {
        internal let path: PartialKeyPath<M>
        internal let unique: Bool

        public init<V: FDBTuplePackable>(_ path: KeyPath<M, V>, unique: Bool) {
            self.path = path
            self.unique = unique
        }

        internal func getTuplePackableValue(from instance: M) -> FDBTuplePackable? {
            return (instance[keyPath: self.path] as? FDBTuplePackable)
        }
    }
}

public protocol Entita2FDBIndexedEntity: E2FDBEntity {
    static var indices: [String: E2.Index<Self>] { get }
    static var indexSubspace: FDB.Subspace { get }
    var indexIndexSubspace: FDB.Subspace { get }

    func getIndexKeyForIndex(_ index: E2.Index<Self>, name: FDBTuplePackable, value: FDBTuplePackable) -> AnyFDBKey
    func getIndexIndexKeyForIndex(name: FDBTuplePackable, value: FDBTuplePackable) -> AnyFDBKey
    static func getIndexKeyForUniqueIndex(name: FDBTuplePackable, value: FDBTuplePackable) -> AnyFDBKey

    static func loadByIndex(
        name: String,
        value: FDBTuplePackable,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Self?>
    static func existsByIndex(name: String, value: FDBTuplePackable, on eventLoop: EventLoop) -> Future<Bool>
}

public extension Entita2FDBIndexedEntity {
    static var indexSubspace: FDB.Subspace {
        return Self.subspace["idx"][Self.entityName]
    }

    var indexIndexSubspace: FDB.Subspace {
        return Self.indexSubspace["idx", self.getID()]
    }

    fileprivate func getIndexValueFrom(index: E2.Index<Self>) -> FDBTuplePackable? {
        return index.getTuplePackableValue(from: self)
    }

    static func getGenericIndexSubspaceForIndex(
        name: FDBTuplePackable,
        value: FDBTuplePackable
    ) -> FDB.Subspace {
        return Self.indexSubspace[name][value]
    }

    static func getIndexKeyForUniqueIndex(
        name: FDBTuplePackable,
        value: FDBTuplePackable
    ) -> AnyFDBKey {
        return Self.getGenericIndexSubspaceForIndex(name: name, value: value)
    }

    func getIndexKeyForIndex(
        _ index: E2.Index<Self>,
        name: FDBTuplePackable,
        value: FDBTuplePackable
    ) -> AnyFDBKey {
        var result = Self.getGenericIndexSubspaceForIndex(name: name, value: value)

        if !index.unique {
            result = result[self.getID()]
        }

        return result
    }

    func getIndexIndexKeyForIndex(name: FDBTuplePackable, value: FDBTuplePackable) -> AnyFDBKey {
        return self.indexIndexSubspace[name][value]
    }

    private func createIndex(
        _ indexName: FDBTuplePackable,
        for index: E2.Index<Self>,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        guard let value = self.getIndexValueFrom(index: index) else {
            return eventLoop.makeFailedFuture(
                E2.E.IndexError(
                    "Could not get tuple packable value for index '\(indexName)' in entity '\(Self.entityName)'"
                )
            )
        }

        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.set(key: self.getIndexKeyForIndex(index, name: indexName, value: value), value: self.getIDAsKey()) }
            .flatMap { $0.set(key: self.getIndexIndexKeyForIndex(name: indexName, value: value), value: []) }
            .map { _ in () }
    }

    func afterInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return EventLoopFuture<Void>.andAllSucceed(
            Self.indices.map { self.createIndex($0.key, for: $0.value, with: transaction, on: eventLoop) },
            on: eventLoop
        )
    }

    func afterDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return EventLoopFuture<Void>.andAllSucceed(
            Self.indices.map { indexName, index in
                guard let value = self.getIndexValueFrom(index: index) else {
                    return eventLoop.makeSucceededFuture(())
                }
                return Self.storage
                    .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
                    .flatMap { $0.clear(key: self.getIndexKeyForIndex(index, name: indexName, value: value)) }
                    .flatMap { $0.clear(key: self.getIndexIndexKeyForIndex(name: indexName, value: value)) }
                    .map { _ in () }
            },
            on: eventLoop
        )
    }

    fileprivate func updateIndices(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        let future: Future<Void> = Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.get(range: self.indexIndexSubspace.range) }
            .flatMap { keyValueRecords, transaction in
                print("self.indexIndexSubspace")
                dump(self.indexIndexSubspace)
                print("keyValueRecords")
                dump(keyValueRecords)
                var result: Future<Void> = eventLoop.makeSucceededFuture(())

                for record in keyValueRecords.records {
                    let key: FDB.Tuple

                    do {
                        key = try FDB.Tuple(from: record.key)
                    } catch { continue }

                    let tuples = key.tuple.compactMap { $0 }
                    guard tuples.count >= 2 else {
                        continue
                    }
                    let indexNameErased = tuples[tuples.count - 2]
                    let indexValue = tuples[tuples.count - 1]
                    
                    guard let indexName = indexNameErased as? String else {
                        return eventLoop.makeFailedFuture(
                            E2.E.IndexError(
                                "Could not cast '\(indexNameErased)' as String in entity '\(Self.entityName)'"
                            )
                        )
                    }
                    guard let index = Self.indices[indexName] else {
                        return eventLoop.makeFailedFuture(
                            E2.E.IndexError(
                                "No index '\(indexName)' in entity '\(Self.entityName)'"
                            )
                        )
                    }
                    guard let propertyValue = self.getIndexValueFrom(index: index) else {
                        return eventLoop.makeFailedFuture(
                            E2.E.IndexError(
                                "Could not get property value for index '\(indexName)' in entity '\(Self.entityName)'"
                            )
                        )
                    }

                    let probablyNewIndexKey = self.getIndexKeyForIndex(index, name: indexName, value: propertyValue)
                    let previousIndexKey = self.getIndexKeyForIndex(index, name: indexName, value: indexValue)
                    
                    if previousIndexKey.asFDBKey() != probablyNewIndexKey.asFDBKey() {
                        result = result
                            .flatMap { _ in transaction.clear(key: previousIndexKey) }
                            .flatMap { _ in transaction.clear(key: key) }
                            .flatMap { _ in self.createIndex(indexName, for: index, with: transaction, on: eventLoop) }
                    }
                }

                return result
            }
        return future
    }

    func afterSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.updateIndices(with: transaction, on: eventLoop)
    }

    private static func isValidIndex(name: String) -> Bool {
        guard let _ = Self.indices[name] else {
            let additionalInfo = "(available indices: \(Self.indices.keys.joined(separator: ", ")))"
            Logger(label: "E2FDB").error("Index '\(name)' not found in entity '\(Self.entityName)' \(additionalInfo)")
            return false
        }
        return true
    }

    static func loadByIndex(
        name: String,
        value: FDBTuplePackable,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        guard Self.isValidIndex(name: name) else {
            return eventLoop.makeSucceededFuture(nil)
        }

        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.get(key: Self.getIndexKeyForUniqueIndex(name: name, value: value)) }
            .flatMap { maybeIDBytes, transaction in
                guard let IDBytes = maybeIDBytes else {
                    return eventLoop.makeSucceededFuture(nil)
                }
                return Self.loadByRaw(IDBytes: IDBytes, with: transaction, on: eventLoop)
            }
    }

    static func existsByIndex(name: String, value: FDBTuplePackable, on eventLoop: EventLoop) -> Future<Bool> {
        guard Self.isValidIndex(name: name) else {
            return eventLoop.makeSucceededFuture(false)
        }

        return self.storage.withTransaction(on: eventLoop) { transaction in
            return transaction
                .get(key: Self.getIndexKeyForUniqueIndex(name: name, value: value))
                .map { maybeIDBytes, _ in maybeIDBytes != nil }
        }
    }
}
