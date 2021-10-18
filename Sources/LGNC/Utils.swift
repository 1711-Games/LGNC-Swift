import LGNCore

extension ArraySlice where Element == Byte {
    var _string: String {
        String(bytes: self, encoding: .ascii)!
    }
}

extension Array {
    func appending<S: Sequence>(contentsOf newElements: S) -> Self where S.Element == Self.Element {
        var copy = self

        copy.append(contentsOf: newElements)

        return copy
    }
}

extension LGNC {
    static func packMeta(_ dict: [String: String]) -> Bytes {
        var result = Bytes([0, 255])
        for (k, v) in dict {
            result.append(contentsOf: Bytes("\(k)\u{00}\(v)".replacingOccurrences(of: "\n", with: "").utf8))
            result.append(10) // EOL
        }
        return result
    }
}
