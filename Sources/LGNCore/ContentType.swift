public extension LGNCore {
    struct ContentType: Sendable {
        public let type: String
        public let options: [String: String]

        public var charset: String {
            self.options["charset"] ?? "UTF-8"
        }

        public var header: String {
            var result = "\(self.type)"
            self.options.forEach { key, value in
                result += "; \(key)=\(value)"
            }
            return result
        }

        public init(type: String, options: [String: String] = [:]) {
            self.type = type
            self.options = options
        }

        public init(rawValue: String) {
            let components = rawValue
                .split(separator: ";", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            self.init(
                type: components[0],
                options: components.count == 2
                    ? LGNCore.parseKV(from: components[1])
                    : [:]
            )
        }
    }
}

public extension LGNCore.ContentType {
    static let MsgPack                 = Self.init(type: "text/plain")
    static let JSON                    = Self.init(type: "application/json")
    static let XML                     = Self.init(type: "application/xml")
    static let TextHTML                = Self.init(type: "text/html")
    static let TextPlain               = Self.init(type: "text/plain")
    static let ApplicationOctetStream  = Self.init(type: "application/octet-stream")
}

extension LGNCore.ContentType: Equatable {
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.type.lowercased() == rhs.type.lowercased() && lhs.options == rhs.options
    }
}
