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
        return Self.IDAsKey(ID: self.getID())
    }
    
    public static func loadBy(IDBytes: Bytes, on eventLoop: EventLoop) -> Future<Self?> {
        return self.loadByRaw(
            IDBytes: self.IDBytesAsKey(bytes: IDBytes),
            on: eventLoop
        )
    }

    public static func loadByRaw(IDBytes: Bytes, on eventLoop: EventLoop) -> Future<Self?> {
        return self.storage.load(
            by: IDBytes,
            on: eventLoop
        ).thenThrowing {
            guard let bytes = $0 else {
                return nil
            }
            return try Self.init(from: bytes, format: Self.format)
        }
    }

    public static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?> {
        return self.loadBy(IDBytes: Self.IDAsKey(ID: ID), on: eventLoop)
    }

    public func beforeInsert0(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeInsert(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterInsert(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }
    
    public func afterInsert0(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }
    
    public func getPackedSelf(on eventLoop: EventLoop) -> Future<Bytes> {
        do {
            return eventLoop.newSucceededFuture(result: try self.pack(to: Self.format))
        } catch {
            return eventLoop.newFailedFuture(error: E.SaveError("Could not save entity: \(error)"))
        }
    }

    public func save(by ID: Identifier? = nil, on eventLoop: EventLoop) -> Future<Void> {
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
                    on: eventLoop
                )
            }
    }

    public func insert(on eventLoop: EventLoop) -> Future<Void> {
        return self
            .beforeInsert0(on: eventLoop)
            .then { self.beforeInsert(on: eventLoop) }
            .then { self.save(on: eventLoop) }
            .then { self.afterInsert(on: eventLoop) }
            .then { self.afterInsert0(on: eventLoop) }
    }
    
    public func beforeDelete0(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func beforeDelete(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterDelete(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }
    
    public func afterDelete0(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func delete(on eventLoop: EventLoop) -> Future<Void> {
        return self
            .beforeDelete0(on: eventLoop)
            .then { self.beforeDelete(on: eventLoop) }
            .then {
                Self.storage.delete(
                    by: self.getIDAsKey(),
                    on: eventLoop
                )
            }
            .then { self.afterDelete(on: eventLoop) }
            .then { self.afterDelete0(on: eventLoop) }
    }
}
