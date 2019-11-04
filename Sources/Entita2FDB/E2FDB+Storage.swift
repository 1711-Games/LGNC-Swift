import LGNCore
import FDB
import NIO

public protocol E2FDBStorage: E2Storage, AnyFDB {
    func unwrapAnyTransactionOrBegin(
        _ anyTransaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<AnyFDBTransaction>

    func commitIfNecessary(
        commit: Bool,
        transaction: AnyFDBTransaction,
        on eventLoop: EventLoop
    ) -> Future<Void>

    func load(
        by key: Bytes,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Bytes?>

    func load(
        by key: Bytes,
        within transaction: AnyTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<Bytes?>

    func loadAll(
        by range: FDB.RangeKey,
        limit: Int32,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<FDB.KeyValuesResult>

    func loadAll(
        by range: FDB.RangeKey,
        limit: Int32,
        within transaction: AnyTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<FDB.KeyValuesResult>

    func save(
        bytes: Bytes,
        by key: Bytes,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void>

    func delete(by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
}

extension FDB: E2FDBStorage {
    @inlinable public func unwrapAnyTransactionOrBegin(
        _ anyTransaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<AnyFDBTransaction> {
        if let transaction = anyTransaction as? AnyFDBTransaction {
            return eventLoop.makeSucceededFuture(transaction)
        } else {
            E2.logger.notice("Beginning a new transaction")
            return self.begin(on: eventLoop)
        }
    }

    @inlinable public func commitIfNecessary(
        commit: Bool,
        transaction: AnyFDBTransaction,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        guard commit else {
            return eventLoop.makeSucceededFuture()
        }
        return transaction.commit()
    }

    public func load(
        by key: Bytes,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Bytes?> {
        return self.load(by: key, within: transaction, snapshot: false, on: eventLoop)
    }

    public func load(
        by key: Bytes,
        within transaction: AnyTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<Bytes?> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { transaction in transaction.get(key: key, snapshot: snapshot) }
            .map { $0.0 }
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<FDB.KeyValuesResult> {
        return self.loadAll(by: range, limit: limit, within: transaction, snapshot: false, on: eventLoop)
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within transaction: AnyTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> Future<FDB.KeyValuesResult> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.get(range: range, limit: limit, snapshot: snapshot) }
            .map { $0.0 }
    }

    public func save(
        bytes: Bytes,
        by key: Bytes,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.set(key: key, value: bytes) }
            .flatMap { self.commitIfNecessary(commit: transaction == nil, transaction: $0, on: eventLoop) }
    }

    public func delete(by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.clear(key: key) }
            .flatMap { self.commitIfNecessary(commit: transaction == nil, transaction: $0, on: eventLoop) }
    }
}
