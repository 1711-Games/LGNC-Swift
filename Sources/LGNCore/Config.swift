import Logging

public protocol AnyConfigKey: Hashable, RawRepresentable, CaseIterable where RawValue == String {}

public extension LGNCore {
    struct Config<Key: AnyConfigKey> {
        public enum E: Error {
            case MissingEntries([Key])
        }

        public static var empty: Config {
            return Config(storage: [:])
        }

        private let storage: [Key: String]
        private let logger = Logging.Logger(label: "LGNCore.Config")

        fileprivate init(storage: [Key: String]) {
            self.storage = storage
        }

        public init(
            env: AppEnv,
            rawConfig: [AnyHashable: String],
            localConfig: [Key: String] = [:]
        ) throws {
            var errors: [Key] = []
            var storage: [Key: String] = [:]

            for key in Key.allCases {
                let value: String

                if let _value = rawConfig[key.rawValue] {
                    value = _value
                } else if env == .local, let _value = localConfig[key] {
                    value = _value
                } else {
                    errors.append(key)
                    continue
                }

                storage[key] = value
            }

            guard errors.count == 0 else {
                throw E.MissingEntries(errors)
            }

            self.init(storage: storage)
        }

        public subscript(key: Key) -> String {
            guard let value = self.storage[key] else {
                self.logger.critical("Config value for key '\(key)' missing (how is this possible?)")
                return "__\(key)__MISSING__"
            }
            return value
        }

        public func get(_ rawKey: String) -> String? {
            guard let key = Key(rawValue: rawKey) else {
                return nil
            }
            return self[key]
        }
    }
}
