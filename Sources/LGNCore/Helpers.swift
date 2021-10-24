import Foundation
import LGNLog

extension UUID: @unchecked Sendable {}

// autoreleasepool is objc-exclusive thing
#if !os(macOS)
    public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
        return try body()
    }
#endif

public extension Float {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places: Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}

/// Performs a sanity check and exits the application with `fatalError` if check was unsuccessful
///
/// This is a temporary function until stdlib `precondition` (with identical interface) is fixed and normalized
/// (currently it omits the error message and stack trace in `release` builds)
public func _precondition(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = String(),
    file: StaticString = #file, line: UInt = #line
) {
    guard condition() == true else {
        fatalError("Precondition failed: \(message())", file: file, line: line)
    }
}

public extension UUID {
    /// A helper function for UUID initialization from byte array (it should be exactly 16 bytes)
    init(bytes: Bytes) throws {
        self.init(uuid: try bytes.cast())
    }

    /// A helper var for casting UUID to string HEX form (just an alias for `UUID.uuidString`)
    var string: String {
        return uuidString
    }
}

public extension Date {
    var timeIntervalSince: TimeInterval {
        return -timeIntervalSinceNow
    }
}

public extension Sequence {
    @inlinable
    func map<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        let initialCapacity = self.underestimatedCount
        var result = ContiguousArray<T>()
        result.reserveCapacity(initialCapacity)

        var iterator = self.makeIterator()

        // Add elements up to the initial capacity without checking for regrowth.
        for _ in 0..<initialCapacity {
            result.append(try await transform(iterator.next()!))
        }
        // Add remaining elements, if any.
        while let element = iterator.next() {
            result.append(try await transform(element))
        }
        return Array(result)
    }

    @inlinable
    func compactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        try await self
            .map(transform)
            .compactMap { $0 }
    }
}

public extension LGNCore {
    typealias KV = (key: String, value: String)

    static func parseKV(from input: String) -> [String: String] {
        .init(
            input
                .components(separatedBy: ";")
                .compactMap { (rawPair: String) -> KV? in
                    let parsedPair = rawPair
                        .trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: "=")

                    guard parsedPair.count == 2 else {
                        return nil
                    }

                    return KV(
                        key: parsedPair[0].trimmingCharacters(in: .whitespaces),
                        value: parsedPair[1]
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: .init(charactersIn: "\""))
                    )
                },
            uniquingKeysWith: { first, second in first }
        )
    }
}
