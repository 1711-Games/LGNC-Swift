import LGNCore
import NIO

public extension E2 {
    public enum Format: String {
        case JSON, MsgPack
    }
}

public protocol E2Entity: Codable {
    associatedtype Identifier: Identifiable
    associatedtype Storage: E2Storage

    typealias IDKeyPath = KeyPath<Self, Identifier>

    static var format: E2.Format { get }
    static var storage: Storage { get }
    static var entityName: String { get }
    static var fullEntityName: Bool { get }
    static var IDKey: IDKeyPath { get }

    init(from bytes: Bytes, format: E2.Format) throws
    func pack(to format: E2.Format) throws -> Bytes

    static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?>
    static func loadBy(IDBytes: Bytes, on eventLoop: EventLoop) -> Future<Self?>
    static func loadByRaw(IDBytes: Bytes, on eventLoop: EventLoop) -> Future<Self?>

    /// Same as `save`, but with executes `beforeInsert` and `afterInsert` before and after insert respectively
    // Internal method, do not define
    func beforeInsert0(on eventLoop: EventLoop) -> Future<Void>
    func beforeInsert(on eventLoop: EventLoop) -> Future<Void>
    func insert(on eventLoop: EventLoop) -> Future<Void>
    func afterInsert(on eventLoop: EventLoop) -> Future<Void>
    // Internal method, do not define
    func afterInsert0(on eventLoop: EventLoop) -> Future<Void>

    func save(by ID: Identifier?, on eventLoop: EventLoop) -> Future<Void>

    func beforeDelete0(on eventLoop: EventLoop) -> Future<Void>
    func beforeDelete(on eventLoop: EventLoop) -> Future<Void>
    func delete(on eventLoop: EventLoop) -> Future<Void>
    func afterDelete(on eventLoop: EventLoop) -> Future<Void>
    func afterDelete0(on eventLoop: EventLoop) -> Future<Void>

    func getID() -> Identifier
    func getIDAsKey() -> Bytes

    static func IDBytesAsKey(bytes: Bytes) -> Bytes
    static func IDAsKey(ID: Identifier) -> Bytes
}

public extension E2Entity {
    public func getID() -> Identifier {
        return self[keyPath: Self.IDKey]
    }
}
