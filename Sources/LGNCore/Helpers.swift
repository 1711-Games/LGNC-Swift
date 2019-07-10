import Foundation

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
    init(bytes: Bytes) {
        _precondition(
            bytes.count == MemoryLayout<UUID>.size,
            "You provided \(bytes.count) bytes, exactly \(MemoryLayout<UUID>.size) is needed for UUID"
        )
        self.init(uuid: bytes.unsafeCast())
    }

    var string: String {
        return uuidString
    }
}

public extension Date {
    var timeIntervalSince: TimeInterval {
        return -timeIntervalSinceNow
    }
}
