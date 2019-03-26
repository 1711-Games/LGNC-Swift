// these are pretty much default for all packages and shouldn't clash with anything
public typealias Byte = UInt8
public typealias Bytes = [Byte]

public extension LGNCore {
    static func getBytes(_ string: String) -> Bytes {
        return Bytes(string.utf8)
    }

    static func getBytes<Input>(_ input: Input) -> Bytes {
        return withUnsafeBytes(of: input) { Bytes($0) }
    }
}

public extension ArraySlice where Element == Byte {
    func cast<Result>() -> Result {
        precondition(
            MemoryLayout<Result>.size == count,
            "Memory layout size for result type '\(Result.self)' (\(MemoryLayout<Result>.size) bytes) does not match with given byte array length (\(count) bytes)"
        )
        return withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Result.self).pointee
        }
    }
}

public extension Array where Element == Byte {
    var _string: String {
        return String(bytes: self, encoding: .ascii)!
    }

    mutating func addNul() {
        append(0)
    }

    func cast<Result>(file: StaticString = #file, line: Int = #line) -> Result {
        precondition(
            MemoryLayout<Result>.size == count,
            "Memory layout size for result type '\(Result.self)' (\(MemoryLayout<Result>.size) bytes) does not match with given byte array length (\(count) bytes) at \(file):\(line)"
        )
        return withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Result.self).pointee
        }
    }

    mutating func append(_ bytes: Bytes) {
        append(contentsOf: bytes)
    }

    mutating func prepend(_ bytes: Bytes) {
        insert(contentsOf: bytes, at: 0)
    }
}
