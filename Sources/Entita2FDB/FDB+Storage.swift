import LGNCore
import FDB
import NIO

extension FDB: E2Storage {
    public func unwrapAnyTransactionOrBegin(
        _ anyTransaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Transaction> {
        if let transaction = anyTransaction as? Transaction {
            return eventLoop.newSucceededFuture(result: transaction)
        } else {
            return self.begin(eventLoop: eventLoop)
        }
    }
    
    public func load(by key: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Bytes?> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { transaction in transaction.get(key: key) }
            .map { $0.0 }
    }
    
    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<KeyValuesResult> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { $0.get(range: range, limit: limit) }
            .map { $0.0 }
    }
    
    public func save(
        bytes: Bytes,
        by key: Bytes,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { transaction in transaction.set(key: key, value: bytes) }
            .map { _ in () }
    }
    
    public func delete(by key: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .then { $0.clear(key: key) }
            .map { _ in () }
    }
}
