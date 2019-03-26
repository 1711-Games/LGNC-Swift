import LGNCore
import NIO

public extension E2Entity {
    static var fullEntityName: Bool {
        return false
    }

    @inlinable
    static var entityName: String {
        let components = String(reflecting: Self.self).components(separatedBy: ".")
        return components[
            (Self.fullEntityName ? 1 : components.count - 1)...
        ].joined(separator: ".")
    }

    static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        return LGNCore.getBytes(Self.entityName + ":") + bytes
    }

    static func IDAsKey(ID: Identifier) -> Bytes {
        return Self.IDBytesAsKey(bytes: ID._bytes)
    }

    func getIDAsKey() -> Bytes {
        return Self.IDAsKey(ID: getID())
    }

    static func loadBy(
        IDBytes: Bytes,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        return Self.loadByRaw(
            IDBytes: IDBytesAsKey(bytes: IDBytes),
            on: eventLoop
        )
    }

    static func loadByRaw(
        IDBytes: Bytes,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        return Self.storage.load(
            by: IDBytes,
            with: transaction,
            on: eventLoop
        ).flatMapThrowing {
            guard let bytes = $0 else {
                return nil
            }
            return try Self(from: bytes, format: Self.format)
        }
        .flatMap { (maybeModel: Self?) -> Future<Self?> in
            guard let model = maybeModel else {
                return eventLoop.makeSucceededFuture(nil)
            }
            return model
                .afterLoad0(on: eventLoop)
                .flatMap { model.afterLoad(on: eventLoop) }
                .map { _ in model }
        }
    }

    static func load(
        by ID: Identifier,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        return Self.loadByRaw(IDBytes: Self.IDAsKey(ID: ID), on: eventLoop)
    }

    func afterLoad0(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterLoad(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func beforeSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func beforeSave(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterSave(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func beforeInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func beforeInsert(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterInsert(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func beforeDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func beforeDelete(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    func afterDelete(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.makeSucceededFuture(())
    }

    // Though this method isn't actually asynchronous,
    // it's deliberately stated as Future<Bytes> to eliminate `throws` keyword
    func getPackedSelf(on eventLoop: EventLoop) -> Future<Bytes> {
        do {
            return eventLoop.makeSucceededFuture(try pack(to: Self.format))
        } catch {
            return eventLoop.makeFailedFuture(E2.E.SaveError("Could not save entity: \(error)"))
        }
    }

    //MARK: - Public 0-methods
    
    // This method is not intended to be used directly. Use save() method.
    func save0(
        by ID: Identifier? = nil,
        with transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        let IDBytes: Bytes
        if let ID = ID {
            IDBytes = Self.IDAsKey(ID: ID)
        } else {
            IDBytes = self.getIDAsKey()
        }

        return self
            .getPackedSelf(on: eventLoop)
            .flatMap { payload in
                Self.storage.save(
                    bytes: payload,
                    by: IDBytes,
                    with: transaction,
                    on: eventLoop
                )
            }
    }
    
    // This method is not intended to be used directly. Use save() method.
    func delete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return Self.storage.delete(
            by: self.getIDAsKey(),
            with: transaction,
            on: eventLoop
        )
    }
    
    // This method is not intended to be used directly
    func commit0(transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return transaction?.commit() ?? eventLoop.makeSucceededFuture(())
    }

    // MARK: - Public CRUD methods

    func insert(on eventLoop: EventLoop) -> Future<Void> {
        return Self.begin(on: eventLoop)
            .flatMap { transaction in
                self
                    .beforeInsert0(with: transaction, on: eventLoop)
                    .flatMap { self.beforeInsert(with: transaction, on: eventLoop) }
                    .flatMap { self.save0(by: nil, with: transaction, on: eventLoop) }
                    .flatMap { self.afterInsert(with: transaction, on: eventLoop) }
                    .flatMap { self.afterInsert0(with: transaction, on: eventLoop) }
                    .flatMap { self.commit0(transaction: transaction, on: eventLoop) }
            }
    }

    func save(on eventLoop: EventLoop) -> Future<Void> {
        return self.save(by: nil, on: eventLoop)
    }

    func save(by ID: Identifier? = nil, on eventLoop: EventLoop) -> Future<Void> {
        return Self.begin(on: eventLoop)
            .flatMap { transaction in
                self
                    .beforeSave0(with: transaction, on: eventLoop)
                    .flatMap { self.beforeSave(with: transaction, on: eventLoop) }
                    .flatMap { self.save0(by: ID, with: transaction, on: eventLoop) }
                    .flatMap { self.afterSave(with: transaction, on: eventLoop) }
                    .flatMap { self.afterSave0(with: transaction, on: eventLoop) }
                    .flatMap { self.commit0(transaction: transaction, on: eventLoop) }
            }
    }
    
    func delete(on eventLoop: EventLoop) -> Future<Void> {
        return Self.begin(on: eventLoop)
            .flatMap { transaction in
                self
                    .beforeDelete0(with: transaction, on: eventLoop)
                    .flatMap { self.beforeDelete(with: transaction, on: eventLoop) }
                    .flatMap { self.delete0(with: transaction, on: eventLoop) }
                    .flatMap { self.afterDelete(with: transaction, on: eventLoop) }
                    .flatMap { self.afterDelete0(with: transaction, on: eventLoop) }
                    .flatMap { self.commit0(transaction: transaction, on: eventLoop) }
        }
    }
}
