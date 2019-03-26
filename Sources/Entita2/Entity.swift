import LGNCore
import NIO

public extension E2 {
    enum Format: String {
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

    static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?>

    static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?>
    static func loadBy(IDBytes: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Self?>
    static func loadByRaw(IDBytes: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Self?>

    func afterLoad0(on eventLoop: EventLoop) -> Future<Void>
    func afterLoad(on eventLoop: EventLoop) -> Future<Void>

    /// Same as `save`, but with executes `beforeInsert` and `afterInsert` before and after insert respectively.
    /// Internal method, do not define
    func insert(on eventLoop: EventLoop) -> Future<Void>
    func save(on eventLoop: EventLoop) -> Future<Void>
    func save(by ID: Identifier?, on eventLoop: EventLoop) -> Future<Void>
    func delete(on eventLoop: EventLoop) -> Future<Void>
    
    /// This method is not intended to be used directly. Use `save` instead.
    func save0(by ID: Identifier?, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    /// This method is not intended to be used directly. Use `delete` instead.
    func delete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func beforeInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func beforeInsert(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterInsert(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterInsert0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func beforeSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func beforeSave(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterSave(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterSave0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func beforeDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func beforeDelete(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterDelete(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterDelete0(with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func getID() -> Identifier
    func getIDAsKey() -> Bytes

    static func IDBytesAsKey(bytes: Bytes) -> Bytes
    static func IDAsKey(ID: Identifier) -> Bytes
}

public extension E2Entity {
    func getID() -> Identifier {
        return self[keyPath: Self.IDKey]
    }

    static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?> {
        return eventLoop.makeSucceededFuture(nil)
    }
}
