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

    public static func IDAsKey(ID: Identifier) -> Bytes {
        return LGNCore.getBytes(Self.entityName + ":") + ID._bytes
    }

    public func getIDAsKey() -> Bytes {
        return Self.IDAsKey(ID: self.ID)
    }
    
    public static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?> {
        return self.storage.load(
            by: Self.IDAsKey(ID: ID),
            on: eventLoop
        ).thenThrowing {
            guard let bytes = $0 else {
                return nil
            }
            return try Self.init(from: bytes, format: Self.format)
        }
    }

    public func beforeInsert(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterInsert(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }
    
    public func getPackedSelf(on eventLoop: EventLoop) -> Future<Bytes> {
        do {
            return eventLoop.newSucceededFuture(result: try self.pack(to: Self.format))
        } catch {
            return eventLoop.newFailedFuture(error: E.SaveError("Could not save entity: \(error)"))
        }
    }

    public func save(on eventLoop: EventLoop) -> Future<Void> {
        return self
            .getPackedSelf(on: eventLoop)
            .then { payload in
                Self.storage.save(
                    bytes: payload,
                    by: self.getIDAsKey(),
                    on: eventLoop
                )
            }
    }

    public func insert(on eventLoop: EventLoop) -> Future<Void> {
        return self
            .beforeInsert(on: eventLoop)
            .then { self.save(on: eventLoop) }
            .then { self.afterInsert(on: eventLoop) }
    }

    public func beforeDelete(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func afterDelete(on eventLoop: EventLoop) -> Future<Void> {
        return eventLoop.newSucceededFuture(result: ())
    }

    public func delete(on eventLoop: EventLoop) -> Future<Void> {
        return self
            .beforeDelete(on: eventLoop)
            .then {
                Self.storage.delete(
                    by: self.getIDAsKey(),
                    on: eventLoop
                )
            }
            .then { self.afterDelete(on: eventLoop) }
    }
}
