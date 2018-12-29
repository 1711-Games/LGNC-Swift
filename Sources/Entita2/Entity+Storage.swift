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
    
    public func save(on eventLoop: EventLoop) -> Future<Void> {
        do {
            return Self.storage.save(
                bytes: try self.pack(to: Self.format),
                by: self.getIDAsKey(),
                on: eventLoop
            )
        } catch {
            return eventLoop.newFailedFuture(error: E.SaveError("Could not save entity: \(error)"))
        }
    }
    
    public func delete(on eventLoop: EventLoop) -> Future<Void> {
        return Self.storage.delete(
            by: self.getIDAsKey(),
            on: eventLoop
        )
    }
}
