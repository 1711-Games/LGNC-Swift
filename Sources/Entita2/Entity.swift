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

    /// Entity name for identifying in DB
    ///
    /// Default implementation: current class name
    static var entityName: String { get }

    /// Flag indicating whether to use full class name as `entityName` in default implementation
    /// (including module name and preceding namespace)
    ///
    /// Default implementation: `false`
    static var fullEntityName: Bool { get }
    static var IDKey: IDKeyPath { get }

    init(from bytes: Bytes, format: E2.Format) throws
    func pack(to format: E2.Format) throws -> Bytes

    static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?>

    static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?>
    static func loadBy(IDBytes: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Self?>
    static func loadByRaw(IDBytes: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Self?>

    func afterLoad0(on eventLoop: EventLoop) -> Future<Void>
    func afterLoad(on eventLoop: EventLoop) -> Future<Void>

    /// Same as `save`, but with executes `beforeInsert` and `afterInsert` before and after insert respectively.
    /// Internal method, do not define
    func insert(commit: Bool, on eventLoop: EventLoop) -> Future<Void>
    func save(commit: Bool, on eventLoop: EventLoop) -> Future<Void>
    func save(by ID: Identifier?, commit: Bool, on eventLoop: EventLoop) -> Future<Void>
    func delete(commit: Bool, on eventLoop: EventLoop) -> Future<Void>
    
    /// This method is not intended to be used directly. Use `save` instead.
    func save0(by ID: Identifier?, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    /// This method is not intended to be used directly. Use `delete` instead.
    func delete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func beforeInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func beforeInsert(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterInsert(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func beforeSave0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func beforeSave(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterSave(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterSave0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    func beforeDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func beforeDelete(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterDelete(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func afterDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

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
