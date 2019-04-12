import Foundation
import Logging

extension Logging.Logger.MetadataValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(string):
            try string.encode(to: encoder)
        case let .stringConvertible(stringConvertible):
            try stringConvertible.description.encode(to: encoder)
        case let .dictionary(metadata):
            try metadata.encode(to: encoder)
        case let .array(array):
            try array.encode(to: encoder)
        }
    }
}

public extension LGNCore {
    struct Logger: LogHandler {
        enum E: Error {
            case DataToJSONConvertionError
        }

        public var metadata = Logging.Logger.Metadata()

        public static var logLevel: Logging.Logger.Level = .info

        private var _logLevel: Logging.Logger.Level? = nil
        public var logLevel: Logging.Logger.Level {
            get {
                return self._logLevel ?? Logger.logLevel
            }
            set {
                self._logLevel = newValue
            }
        }

        private let encoder = JSONEncoder()

        public var label: String

        public init(label: String) {
            self.label = label
        }

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
            let preamble = "\(date) @ \(_file):\(line)"

            var prettyMetadata: String? = nil
            var mergedMetadata = self.metadata
            if let metadata = metadata {
                mergedMetadata = self.metadata.merging(metadata, uniquingKeysWith: { _, new in new })
            }
            if !mergedMetadata.isEmpty {
                do {
                    let JSONData = try self.encoder.encode(mergedMetadata)
                    guard let string = String(data: JSONData, encoding: .ascii) else {
                        throw E.DataToJSONConvertionError
                    }
                    prettyMetadata = string
                } catch {
                    print("Could not encode metadata '\(mergedMetadata)' to JSON: \(error)")
                }
            }

            let _label: String = (self.logLevel <= .debug ? label : nil).map { " [\($0)]" } ?? ""

            print("[\(preamble)]\(_label) [\(level)]: \(message)\(prettyMetadata.map { " (metadata: \($0))" } ?? "")")
        }

        private func prettify(_ metadata: Logging.Logger.Metadata) -> String? {
            return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
        }
    }
}
