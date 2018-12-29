// these are pretty much default for all packages and shouldn't clash with anything
public typealias Byte = UInt8
public typealias Bytes = [Byte]

public extension LGNCore {
    public static func getBytes(_ string: String) -> Bytes {
        return Bytes(string.utf8)
    }

    public static func getBytes<Input>(_ input: Input) -> Bytes {
        return withUnsafeBytes(of: input) { Bytes($0) }
    }
}

public extension ArraySlice where Element == Byte {
    public func cast<Result>() -> Result {
        precondition(
            MemoryLayout<Result>.size == self.count,
            "Memory layout size for result type '\(Result.self)' (\(MemoryLayout<Result>.size) bytes) does not match with given byte array length (\(self.count) bytes)"
        )
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Result.self).pointee
        }
    }
}

public extension Array where Element == Byte {
    public var _string: String {
        return String(bytes: self, encoding: .ascii)!
    }

    public mutating func addNul() {
        self.append(0)
    }

    public func cast<Result>(file: StaticString = #file, line: Int = #line) -> Result {
        precondition(
            MemoryLayout<Result>.size == self.count,
            "Memory layout size for result type '\(Result.self)' (\(MemoryLayout<Result>.size) bytes) does not match with given byte array length (\(self.count) bytes) at \(file):\(line)"
        )
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Result.self).pointee
        }
    }

    public mutating func append(_ bytes: Bytes) {
        self.append(contentsOf: bytes)
    }

    public mutating func prepend(_ bytes: Bytes) {
        self.insert(contentsOf: bytes, at: 0)
    }
}
