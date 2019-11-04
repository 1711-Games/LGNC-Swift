import LGNCore
import NIO

public protocol E2Storage {
    /// Tries to load bytes from storage for given key within a transaction
    func load(by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Bytes?>

    /// Saves given bytes at given key within a transaction
    func save(bytes: Bytes, by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>

    /// Deletes a given key (and value) from storage within a transaction
    func delete(by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
}
