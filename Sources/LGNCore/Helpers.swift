import Foundation

// autoreleasepool is objc-exclusive thing
#if !os(macOS)
    public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
        return try body()
    }
#endif

public extension Float {
    /// Rounds the double to decimal places value
    public func rounded(toPlaces places: Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}

public extension UUID {
    public init(bytes: Bytes) {
        precondition(bytes.count == 16, "You provided \(bytes.count) bytes, exactly 16 is needed for UUID")
        self.init(uuid: bytes.cast())
    }
    
    public var string: String {
        return self.uuidString
    }
}

public extension Date {
    public var timeIntervalSince: TimeInterval {
        return -self.timeIntervalSinceNow
    }
}
