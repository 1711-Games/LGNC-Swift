import Foundation

public extension LGNCore {
    public struct Env {
        private var values: [String: String]

        public subscript(index: String) -> String {
            get {
                return get(index)!
            }
            set {
                values[index] = newValue
            }
        }

        public init(values: [String: String]) {
            self.values = values
        }

        public func get(_ index: String) -> String? {
            return values[index]
        }

        public static func log(_ message: String) {
            print(message)
        }

        public static func validateAndUnpack(
            params: [String],
            defaultParams: [String: String] = [:]
        ) -> Env {
            var result: [String: String] = [:]
            var errors: [String] = []
            for name in params {
                if let value = ProcessInfo.processInfo.environment[name] {
                    result[name] = value
                } else if let value = defaultParams[name], value != "" {
                    result[name] = value
                } else {
                    errors.append(name)
                }
            }
            guard errors.count == 0 else {
                for name in errors {
                    log("Missing required env param \(name)")
                }
                exit(1)
            }
            return Env(values: result)
        }
    }
}
