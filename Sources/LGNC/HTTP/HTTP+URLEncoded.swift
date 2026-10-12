import NIOHTTP1

extension HTTP {
    /// Parses a query string or an `application/x-www-form-urlencoded` body.
    ///
    /// Keys and values are percent-decoded after splitting (so that encoded `&` and `=` stay within values),
    /// `+` means a space. Values `true`/`false` and integers become `Bool` and `Int`.
    static func parseQueryParams(_ input: String) -> [String: Any] {
        func decode(_ component: Substring) -> String? {
            component.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }

        var result: [String: Any] = [:]

        for component in input.split(separator: "&") {
            let kv = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, let key = decode(kv[0]), let rawValue = decode(kv[1]) else {
                continue
            }

            let value: Any
            if let bool = Bool(rawValue) {
                value = bool
            } else if let int = Int(rawValue) {
                value = int
            } else {
                value = rawValue
            }
            result[key] = value
        }

        return result
    }
}
