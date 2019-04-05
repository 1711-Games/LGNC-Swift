import Foundation
import Logging

public extension LGNCore {
    struct Logger: LogHandler {
        public var metadata: Logging.Logger.Metadata = [:]
        public var logLevel: Logging.Logger.Level = .info

        public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
            get {
                return self.metadata[key]
            }
            set {
                self.metadata[key] = newValue
            }
        }

        public func log(
            level: Logging.Logger.Level,
            message: Logging.Logger.Message,
            metadata: Logging.Logger.Metadata?,
            file: String,
            function: String,
            line: UInt
        ) {
            let date = Date().description.replacingOccurrences(of: " +0000", with: "")
            let _file = file.split(separator: "/").last!

            let metadataString: String
            if let metadata = metadata {
                // TODO: safer metadataString
                let jsonData = try! JSONSerialization.data(withJSONObject: metadata)
                metadataString = " | Metadata: \(String(data: jsonData, encoding: .ascii)!)"
            } else {
                metadataString = ""
            }

            print("[\(date) @ \(_file):\(line)]: \(message)\(metadataString)")
        }
    }
}

public extension LGNCore {
    static func _log(_ message: String, prefix: String? = nil, file: String = #file, line: Int = #line) {
        let _file = file.split(separator: "/").last!
        let _prefix: String
        if let prefix = prefix {
            _prefix = " [\(prefix)]"
        } else {
            _prefix = ""
        }
        print("[\(Date().description.replacingOccurrences(of: " +0000", with: "")) @ \(_file):\(line)]\(_prefix): \(message)")
    }
}
