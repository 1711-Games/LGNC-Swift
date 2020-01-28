import LGNCore
import NIO

public extension E2 {
    /// Serialization format
    enum Format: String, CaseIterable {
        case JSON, MsgPack
    }
}

/// A root entity type in Entita2
public protocol E2Entity: Codable {
    /// Type of ID field of entity
    associatedtype Identifier: Identifiable

    /// Type of storage for entity
    associatedtype Storage: E2Storage

    /// Path to ID field
    typealias IDKeyPath = KeyPath<Self, Identifier>

    /// Serialization format for all entities of this kind
    static var format: E2.Format { get }

    /// Storage delegate for all entities of this kind
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

    /// Path to ID property
    static var IDKey: IDKeyPath { get }

    /// Initializes an E2 model from serialized bytes in given format
    init(from bytes: Bytes, format: E2.Format) throws

    /// Packs current model into given format bytes
    func pack(to format: E2.Format) throws -> Bytes

    /// Begins a transaction if `Storage` is transactional
    static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?>

    /// Tries to load an entity from storage by given ID
    static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?>

    /// Tries to load an entity from storage by given ID bytes within given transaction
    static func loadBy   (IDBytes: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Self?>

    /// Tries to load an entity from storage by given ID raw bytes within given transaction.
    /// For details and format of raw ID see `Self.IDBytesAsKey`
    static func loadByRaw(IDBytes: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Self?>

    /// Executes some system routines after successful entity load.
    /// Do not define or execute this method, instead go for `afterLoad`
    func afterLoad0(on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines after successful entity load.
    /// You may define this method in order to implement custom logic
    func afterLoad(on eventLoop: EventLoop) -> Future<Void>

    /// Same as `save`, but with executes `beforeInsert` and `afterInsert` before and after insert respectively.
    /// Do not define or execute this method
    func insert(commit: Bool, on eventLoop: EventLoop) -> Future<Void>

    /// Saves current entity to storage and optionally commits current transaction if possible
    func save(commit: Bool, on eventLoop: EventLoop) -> Future<Void>

    /// Saves current entity to storage by given identifier and optionally commits current transaction if possible
    func save(by ID: Identifier?, commit: Bool, on eventLoop: EventLoop) -> Future<Void>

    /// Deletes current entity from storage and optionally commits current transaction if possible
    func delete(commit: Bool, on eventLoop: EventLoop) -> Future<Void>
    
    /// Executes some system routines for saving the entity to storage
    /// Do not define or execute this method
    func save0(by ID: Identifier?, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines for deleting the entity from the storage
    /// Do not define or execute this method
    func delete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines before inserting an entity.
    /// Do not define or execute this method
    func beforeInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines before inserting an entity.
    /// Do execute this method
    func beforeInsert (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines after inserting an entity.
    /// Do execute this method
    func afterInsert  (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines after inserting an entity.
    /// Do not define or execute this method
    func afterInsert0 (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines before saving an entity.
    /// Do not define or execute this method
    func beforeSave0  (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines before saving an entity.
    /// Do not execute this method
    func beforeSave   (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines after saving an entity.
    /// Do not execute this method
    func afterSave    (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines after saving an entity.
    /// Do not define or execute this method
    func afterSave0   (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines before deleting an entity.
    /// Do not define or execute this method
    func beforeDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines before deleting an entity.
    /// Do not execute this method
    func beforeDelete (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some routines after deleting an entity.
    /// Do not execute this method
    func afterDelete  (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Executes some system routines after deleting an entity.
    /// Do not define or execute this method
    func afterDelete0 (within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Returns an ID of current entity
    func getID() -> Identifier

    /// Returns ID bytes of current entity
    func getIDAsKey() -> Bytes

    /// Converts given bytes to key bytes
    static func IDBytesAsKey(bytes: Bytes) -> Bytes

    /// Converts given identifier to key bytes
    static func IDAsKey(ID: Identifier) -> Bytes
}

public extension E2Entity {
    func getID() -> Identifier {
        self[keyPath: Self.IDKey]
    }

    static func begin(on eventLoop: EventLoop) -> Future<AnyTransaction?> {
        eventLoop.makeSucceededFuture(nil)
    }
}
