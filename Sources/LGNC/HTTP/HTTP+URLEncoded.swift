import NIOHTTP1

extension HTTP {
    static func parseQueryParams(_ input: String) -> [String: Any] {
        guard let input = input.removingPercentEncoding else {
            return [:]
        }
        var result: [String: Any] = [:]

        for component in input.split(separator: "&") {
            let kv = component.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else {
                continue
            }

            let key = String(kv[0])
            let value: Any
            let rawValue = String(kv[1])
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
