import LGNCore
import NIO

public extension E2Entity {
    public static var fullEntityName: Bool {
        return true
    }

    public static var entityName: String {
        let components = String(reflecting: Self.self).components(separatedBy: ".")
        return components[
            (Self.fullEntityName ? 1 : components.count - 1)...
        ].joined(separator: ".")
    }

    public static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        return LGNCore.getBytes(Self.entityName + ":") + bytes
    }

    public static func IDAsKey(ID: Identifier) -> Bytes {
        return Self.IDBytesAsKey(bytes: ID._bytes)
    }

    public func getIDAsKey() -> Bytes {
        return Self.IDAsKey(ID: getID())
    }

    public static func loadBy(
        IDBytes: Bytes,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        return Self.loadByRaw(
            IDBytes: IDBytesAsKey(bytes: IDBytes),
            on: eventLoop
        )
    }

    public static func loadByRaw(
        IDBytes: Bytes,
        with transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        return Self.storage.load(
            by: IDBytes,
            with: transaction,
            on: eventLoop
        ).thenThrowing {
            guard let bytes = $0 else {
                return nil
            }
            return try Self(from: bytes, format: Self.format)
        }
        .then { (maybeModel: Self?) -> Future<Self?> in
            guard let model = maybeModel else {
                return eventLoop.newSucceededFuture(result: nil)
            }
            return model
                .afterLoad0(on: eventLoop)
                .then { model.afterLoad(on: eventLoop) }
                .map { _ in model }
        }
    }

    public static func load(
        by ID: Identifier,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        return Self.loadByRaw(IDBytes: Self.IDAsKey(ID: ID), on: eventLoop)
    }

    public func afterLoad0(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterLoad(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeSave(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterSave(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeInsert(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterInsert(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeDelete(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterDelete(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    // Though this method isn't actually asynchronous,
    // it's deliberately stated as Future<Bytes> to eliminate `throws` keyword
    public func getPackedSelf(on eventLoop: EventLoop) -> Future<Bytes> {
        do {
            return eventLoop.newSucceededFuture(result: try pack(to: Self.format))
        } catch {
            return eventLoop.newFailedFuture(error: E2.E.SaveError("Could not save entity: \(error)"))
        }
    }

    //MARK: - Public 0-methods
    
    // This method is not intended to be used directly. Use save() method.
    public func save0(
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
            .then { payload in
                Self.storage.save(
                    bytes: payload,
                    by: IDBytes,
                    with: transaction,
                    on: eventLoop
                )
            }
    }
    
    // This method is not intended to be used directly. Use save() method.
    public func delete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return Self.storage.delete(
            by: self.getIDAsKey(),
            with: transaction,
            on: eventLoop
        )
    }
    
    // This method is not intended to be used directly
    public func commit0(transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return transaction?.commit() ?? eventLoop.newSucceededFuture(result: ())
    }

    // MARK: - Public CRUD methods

    public func insert(on eventLoop: EventLoop) -> Future<Void> {
        return Self.begin(on: eventLoop)
            .then { transaction in
                self
                    .beforeInsert0(with: transaction, on: eventLoop)
                    .then { self.beforeInsert(with: transaction, on: eventLoop) }
                    .then { self.save0(by: nil, with: transaction, on: eventLoop) }
                    .then { self.afterInsert(with: transaction, on: eventLoop) }
                    .then { self.afterInsert0(with: transaction, on: eventLoop) }
                    .then { self.commit0(transaction: transaction, on: eventLoop) }
            }
    }

    public func save(by ID: Identifier? = nil, on eventLoop: EventLoop) -> Future<Void> {
        return Self.begin(on: eventLoop)
            .then { transaction in
                self
                    .beforeSave0(with: transaction, on: eventLoop)
                    .then { self.beforeSave(with: transaction, on: eventLoop) }
                    .then { self.save0(by: ID, with: transaction, on: eventLoop) }
                    .then { self.afterSave(with: transaction, on: eventLoop) }
                    .then { self.afterSave0(with: transaction, on: eventLoop) }
                    .then { self.commit0(transaction: transaction, on: eventLoop) }
            }
    }
    
    public func delete(on eventLoop: EventLoop) -> Future<Void> {
        return Self.begin(on: eventLoop)
            .then { transaction in
                self
                    .beforeDelete0(with: transaction, on: eventLoop)
                    .then { self.beforeDelete(with: transaction, on: eventLoop) }
                    .then { self.delete0(with: transaction, on: eventLoop) }
                    .then { self.afterDelete(with: transaction, on: eventLoop) }
                    .then { self.afterDelete0(with: transaction, on: eventLoop) }
                    .then { self.commit0(transaction: transaction, on: eventLoop) }
        }
    }
}
