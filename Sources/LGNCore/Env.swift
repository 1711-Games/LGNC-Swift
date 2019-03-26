import Foundation

public extension LGNCore {
    struct Env {
        private var values: [String: String]

        subscript(index: String) -> String {
            get {
                guard let value = self.get(index) else {
                    LGNCore.log("Value for env key '\(index)' not found")
                    return ""
                }
                return value
            }
            set {
                values[index] = newValue
            }
        }

        init(values: [String: String]) {
            self.values = values
        }

        func get(_ index: String) -> String? {
            return values[index]
        }

        static func log(_ message: String) {
            print(message)
        }

        static func validateAndUnpack(
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
