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
    
    static var format: E2.Format { get }
    static var storage: Storage { get }
    static var entityName: String { get }
    static var fullEntityName: Bool { get }
    
    var ID: Identifier { get }

    init(from bytes: Bytes, format: E2.Format) throws
    func pack(to format: E2.Format) throws -> Bytes

    static func load(by ID: Identifier, on eventLoop: EventLoop) -> Future<Self?>
    func save(on eventLoop: EventLoop) -> Future<Void>
    func delete(on eventLoop: EventLoop) -> Future<Void>

    static func IDAsKey(ID: Identifier) -> Bytes
    func getIDAsKey() -> Bytes
//    static func _getKeyFrom(entity: Self) -> Bytes
//    static func _getKeyFrom(ID: Identifier) -> Bytes
}
