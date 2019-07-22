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
