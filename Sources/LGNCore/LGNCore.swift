import Foundation

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
            Logger(label: "LGNCore.AppEnv").info("Falling back to \(self.local) environment")
            return .local
        #else
            Logger(label: "LGNCore.AppEnv").info("APP_ENV must be set explicitly in non-macOS environment")
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

public extension LGNCore {
    enum ContentType: String, CaseIterable, Sendable {
        case MsgPack
        case JSON
        case XML
        case HTML
        case Text
    }
}

public extension LGNCore.ContentType {
    fileprivate static let HTTPHeaderMsgPack = "application/msgpack"
    fileprivate static let HTTPHeaderJSON = "application/json"
    fileprivate static let HTTPHeaderXML = "application/xml"
    fileprivate static let HTTPHeaderHTML = "text/html"
    fileprivate static let HTTPHeaderText = "text/plain"

    var HTTPHeader: String {
        let result: String

        switch self {
        case .MsgPack: result = Self.HTTPHeaderMsgPack
        case .JSON: result = Self.HTTPHeaderJSON
        case .XML: result = Self.HTTPHeaderXML
        case .HTML: result = Self.HTTPHeaderHTML
        case .Text: result = Self.HTTPHeaderText
        }

        return result
    }

    init?(fromHTTPHeader input: String) {
        let result: Self?

        switch input.lowercased() {
        case Self.HTTPHeaderMsgPack: result = .MsgPack
        case Self.HTTPHeaderJSON: result = .JSON
        case Self.HTTPHeaderXML: result = .XML
        case Self.HTTPHeaderHTML: result = .HTML
        case Self.HTTPHeaderText: result = .Text
        default: result = nil
        }

        guard let result = result else {
            return nil
        }

        self = result
    }
}
