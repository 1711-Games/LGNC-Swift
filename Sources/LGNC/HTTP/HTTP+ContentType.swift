public extension HTTP {
    struct ContentType {
        let type: String
        let options: [String: String]

        var charset: String {
            self.options["charset"] ?? "UTF-8"
        }

        var header: String {
            var result = "\(self.type)"
            self.options.forEach { key, value in
                result += "; \(key)=\(value)"
            }
            return result
        }

        init(type: String, options: [String: String] = [:]) {
            self.type = type
            self.options = options
        }

        init(rawValue: String) {
            let components = rawValue
                .split(separator: ";", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            self.init(
                type: components[0],
                options: components.count == 2
                    ? parseKV(from: components[1])
                    : [:]
            )
        }
    }
}

public extension HTTP.ContentType {
    static let textPlain               = Self.init(type: "text/plain")
    static let textHTML                = Self.init(type: "text/html")
    static let applicationOctetStream  = Self.init(type: "application/octet-stream")
}

extension LGNC.HTTP.Request {
    var isURLEncoded: Bool {
        self.method == .POST
            && self.headers.first(name: "Content-Type")?.starts(with: "application/x-www-form-urlencoded") == true
    }
}
