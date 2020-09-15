import LGNCore
import LGNP
import NIO

public typealias PromiseLGNP = EventLoopPromise<LGNP.Message>

public enum LGNS {
    public static var logger: Logger = Logger(label: "LGNS")
}
