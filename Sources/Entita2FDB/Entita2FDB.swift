import Entita2
import FDB
import NIO

extension FDB: E2Storage {
    public func load(by key: Bytes, on eventLoop: EventLoop) -> EventLoopFuture<Bytes?> {
        return self
            .begin(eventLoop: eventLoop)
            .then { $0.get(key: key) }
            .map { $0.0 }
    }

    public func loadAll(
        by range: RangeFDBKey,
        limit: Int32 = 0,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<KeyValuesResult> {
        return self
            .begin(eventLoop: eventLoop)
            .then { $0.get(range: range, limit: limit) }
            .map { $0.0 }
    }

    public func save(bytes: Bytes, by key: Bytes, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self
            .begin(eventLoop: eventLoop)
            .then { $0.set(key: key, value: bytes, commit: true) }
            .map { _ in () }
    }

    public func delete(by key: Bytes, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self
            .begin(eventLoop: eventLoop)
            .then { $0.clear(key: key, commit: true) }
            .map { _ in () }
    }
}

public protocol Entita2FDBModel: E2Entity where Storage == FDB, Identifier: TuplePackable {
    static var subspace: Subspace { get }
}

public extension Entita2FDBModel {
    public static var format: E2.Format {
        return .MsgPack
    }

    public static func IDAsKey(ID: Identifier) -> Bytes {
        return Self.subspacePrefix[ID].asFDBKey()
    }

    public static func doesRelateToThis(tuple: Tuple) -> Bool {
        let flat = tuple.tuple.compactMap { $0 }
        guard flat.count >= 2 else {
            return false
        }
        guard let value = flat[flat.count - 2] as? String, value == self.entityName else {
            return false
        }
        return true
    }

    public func getIDAsKey() -> Bytes {
        return Self.IDAsKey(ID: self.ID)
    }

    public static var subspacePrefix: Subspace {
        return self.subspace[self.entityName]
    }

    internal static func loadAll(
        bySubspace subspace: Subspace,
        limit: Int32 = 0,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.storage.loadAll(
            by: subspace.range,
            limit: limit,
            on: eventLoop
        ).thenThrowing { results in
            Dictionary(
                uniqueKeysWithValues: try results.records.map {
                    let instance = try Self.init(from: $0.value)
                    return (
                        instance.ID,
                        instance
                    )
                }
            )
        }
    }

    public static func loadAll(
        limit: Int32 = 0,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.loadAll(bySubspace: self.subspacePrefix, limit: limit, on: eventLoop)
    }

    public static func loadAll(
        by key: FDBKey,
        limit: Int32 = 0,
        on eventLoop: EventLoop
    ) -> Future<[Self.Identifier: Self]> {
        return self.loadAll(bySubspace: self.subspacePrefix[key], limit: limit, on: eventLoop)
    }

    public static func loadAllRaw(
        limit: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        on eventLoop: EventLoop
    ) -> Future<KeyValuesResult> {
        return self.storage.loadAll(by: self.subspacePrefix.range, limit: limit, on: eventLoop)
    }
}

public typealias E2FDBModel = Entita2FDBModel
