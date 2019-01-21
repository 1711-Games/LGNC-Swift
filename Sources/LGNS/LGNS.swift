import LGNCore
import LGNP
import NIO

public typealias Byte = UInt8
public typealias Bytes = [Byte]

public typealias PromiseLGNP = EventLoopPromise<LGNP.Message>
public typealias PromiseVoid = EventLoopPromise<Void>

public struct LGNS {}

public extension LGNS {
    public enum Address: CustomStringConvertible {
        case ip(host: String, port: Int)
        case unixDomainSocket(path: String)
        case localhost
        
        public static func port(_ port: Int) -> Address {
            return self.ip(host: "0.0.0.0", port: port)
        }
        
        public var description: String {
            switch self {
            case let .ip(host, port):
                return "\(host):\(port)"
            case let .unixDomainSocket(path):
                return "unix://\(path)"
            default:
                return "unknown address"
            }
        }
    }
}
