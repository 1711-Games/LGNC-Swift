import Foundation
import LGNLog

public enum LGNCore {
    public enum E: Error {
        case CastError(String)
    }
}

/// Represents application environment
public enum AppEnv: String, CaseIterable {
    case local
    case dev
    case qa
    case stage
    case production

    public static let prod: AppEnv = .production

    public static func detect(from env: [String: String] = ProcessInfo.processInfo.environment) -> AppEnv {
        if let rawEnv = env["APP_ENV"], let env = self.init(rawValue: rawEnv) {
            return env
        }

        #if os(macOS)
            Logger.current.info("Falling back to \(self.local) environment")
            return .local
        #else
            Logger.current.info("APP_ENV must be set explicitly in non-macOS environment")
            exit(1)
        #endif
    }
}

public extension LGNCore {
    enum Address: CustomStringConvertible {
        case ip(host: String, port: Int)
        case unixDomainSocket(path: String)
        case localhost

        public static func port(_ port: Int) -> Address {
            return ip(host: "0.0.0.0", port: port)
        }

        public var description: String {
            let result: String

            switch self {
            case let .ip(host, port):
                result = "\(host):\(port)"
            case let .unixDomainSocket(path):
                result = "unix://\(path)"
            case .localhost:
                result = "localhost"
            }

            return result
        }
    }
}
