import LGNCore
import NIO

public protocol E2Storage {
    func load(by key: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Bytes?>
    func save(bytes: Bytes, by key: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
    func delete(by key: Bytes, with transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void>
}
