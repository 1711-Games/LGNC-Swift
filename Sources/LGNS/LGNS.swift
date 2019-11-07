import LGNCore
import LGNP
import NIO

public typealias Byte = UInt8
public typealias Bytes = [Byte]

public typealias PromiseLGNP = EventLoopPromise<LGNP.Message>
public typealias PromiseVoid = EventLoopPromise<Void>

public enum LGNS {
    public static var logger: Logger = Logger(label: "LGNS")
}
