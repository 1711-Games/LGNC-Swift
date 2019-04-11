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

public extension UUID {
    init(bytes: Bytes) {
        precondition(
            bytes.count == MemoryLayout<UUID>.size,
            "You provided \(bytes.count) bytes, exactly \(MemoryLayout<UUID>.size) is needed for UUID"
        )
        self.init(uuid: bytes.cast())
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
