import LGNCore
import NIO

public extension E2Entity {
    /// Defines whether full name for ID should be full or short
    /// Defaults to `false` (hence short)
    static var fullEntityName: Bool {
        false
    }

    @inlinable static var entityName: String {
        let components = String(reflecting: Self.self).components(separatedBy: ".")
        return components[
            (Self.fullEntityName ? 1 : components.count - 1)...
        ].joined(separator: ".")
    }

    static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        LGNCore.getBytes(Self.entityName + ":") + bytes
    }

    static func IDAsKey(ID: Identifier) -> Bytes {
        Self.IDBytesAsKey(bytes: ID._bytes)
    }

    func getIDAsKey() -> Bytes {
        Self.IDAsKey(ID: getID())
    }

    static func loadBy(
        IDBytes: Bytes,
        within transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        Self.loadByRaw(
            IDBytes: Self.IDBytesAsKey(bytes: IDBytes),
            on: eventLoop
        )
    }

    static func loadByRaw(
        IDBytes: Bytes,
        within transaction: AnyTransaction? = nil,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        Self.storage
            .load(by: IDBytes, within: transaction, on: eventLoop)
            .flatMap { self.afterLoadRoutines0(maybeBytes: $0, on: eventLoop) }
    }

    static func load(
        by ID: Identifier,
        on eventLoop: EventLoop
    ) -> Future<Self?> {
        Self.loadByRaw(IDBytes: Self.IDAsKey(ID: ID), on: eventLoop)
    }

    static func afterLoadRoutines0(maybeBytes: Bytes?, on eventLoop: EventLoop) -> Future<Self?> {
        guard let bytes = maybeBytes else {
            return eventLoop.makeSucceededFuture(nil)
        }
        let entity: Self
        do {
            entity = try Self(from: bytes, format: Self.format)
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
        return entity
            .afterLoad0(on: eventLoop)
            .flatMap { entity.afterLoad(on: eventLoop) }
            .map { _ in entity }
    }

    func afterLoad0(on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterLoad(on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func beforeSave0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func beforeSave(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterSave0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterSave(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func beforeInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func beforeInsert(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterInsert(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func beforeDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func beforeDelete(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    func afterDelete(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
    }

    /// Though this method isn't actually asynchronous,
    /// it's deliberately stated as `Future<Bytes>` to get rid of `throws` keyword
    func getPackedSelf(on eventLoop: EventLoop) -> Future<Bytes> {
        return eventLoop.submit {
            let result: Bytes

            do {
                result = try self.pack(to: Self.format)
            } catch {
                throw E2.E.SaveError("Could not save entity: \(error)")
            }

            return result
        }
    }

    //MARK: - Public 0-methods
    
    /// This method is not intended to be used directly. Use `save()` method.
    func save0(
        by ID: Identifier? = nil,
        within transaction: AnyTransaction?,
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
                    within: transaction,
                    on: eventLoop
                )
            }
    }

    /// This method is not intended to be used directly. Use `save()` method.
    func delete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        Self.storage.delete(
            by: self.getIDAsKey(),
            within: transaction,
            on: eventLoop
        )
    }

    /// This method is not intended to be used directly
    func commit0(transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        return transaction?.commit() ?? eventLoop.makeSucceededFuture(())
    }

    internal func commit0IfNecessary(
        commit: Bool,
        transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        if commit {
            return self.commit0(transaction: transaction, on: eventLoop)
        }
        return eventLoop.makeSucceededFuture()
    }

    // MARK: - Public CRUD methods

    func insert(commit: Bool = true, on eventLoop: EventLoop) -> Future<Void> {
        Self
            .begin(on: eventLoop)
            .flatMap { transaction in self.insert(commit: commit, within: transaction, on: eventLoop) }
    }

    /// Inserts current entity to DB within given transaction
    func insert(commit: Bool = true, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
            .flatMap { self.beforeInsert0(within: transaction, on: eventLoop) }
            .flatMap { self.beforeInsert(within: transaction, on: eventLoop) }
            .flatMap { self.save0(by: nil, within: transaction, on: eventLoop) }
            .flatMap { self.afterInsert(within: transaction, on: eventLoop) }
            .flatMap { self.afterInsert0(within: transaction, on: eventLoop) }
            .flatMap { self.commit0IfNecessary(commit: commit, transaction: transaction, on: eventLoop) }
    }

    /// Saves current entity to DB within given transaction
    func save(commit: Bool = true, on eventLoop: EventLoop) -> Future<Void> {
        self.save(by: nil, commit: commit, on: eventLoop)
    }

    func save(by ID: Identifier? = nil, commit: Bool = true, on eventLoop: EventLoop) -> Future<Void> {
        Self
            .begin(on: eventLoop)
            .flatMap { transaction in self.save(by: ID, commit: commit, within: transaction, on: eventLoop) }
    }

    /// Saves current entity to DB within given transaction
    func save(
        by ID: Identifier? = nil,
        commit: Bool = true,
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> Future<Void> {
        eventLoop.makeSucceededFuture()
            .flatMap { self.beforeSave0(within: transaction, on: eventLoop) }
            .flatMap { self.beforeSave(within: transaction, on: eventLoop) }
            .flatMap { self.save0(by: ID, within: transaction, on: eventLoop) }
            .flatMap { self.afterSave(within: transaction, on: eventLoop) }
            .flatMap { self.afterSave0(within: transaction, on: eventLoop) }
            .flatMap { self.commit0IfNecessary(commit: commit, transaction: transaction, on: eventLoop) }
    }

    func delete(commit: Bool = true, on eventLoop: EventLoop) -> Future<Void> {
        Self
            .begin(on: eventLoop)
            .flatMap { transaction in self.delete(commit: commit, within: transaction, on: eventLoop) }
    }

    /// Deletes current entity from DB within given transaction
    func delete(commit: Bool = true, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
        eventLoop.makeSucceededFuture()
            .flatMap { self.beforeDelete0(within: transaction, on: eventLoop) }
            .flatMap { self.beforeDelete(within: transaction, on: eventLoop) }
            .flatMap { self.delete0(within: transaction, on: eventLoop) }
            .flatMap { self.afterDelete(within: transaction, on: eventLoop) }
            .flatMap { self.afterDelete0(within: transaction, on: eventLoop) }
            .flatMap { self.commit0IfNecessary(commit: commit, transaction: transaction, on: eventLoop) }
    }
}
