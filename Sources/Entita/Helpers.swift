internal protocol Flattenable {
    var flattened: Any? { get }
}

extension Optional: Flattenable {
    var flattened: Any? {
        switch self {
        case .some(let x as Flattenable): return x.flattened
        case .some(let x): return x
        case .none: return nil
        }
    }
}

public protocol ScalarValue {}

extension String: ScalarValue {}
extension Character: ScalarValue {}
extension UnicodeScalar: ScalarValue {}
extension Bool: ScalarValue {}
extension Float32: ScalarValue {}
extension Float64: ScalarValue {}
extension UInt8: ScalarValue {}
extension Int8: ScalarValue {}
extension UInt16: ScalarValue {}
extension Int16: ScalarValue {}
extension UInt32: ScalarValue {}
extension Int32: ScalarValue {}
extension UInt64: ScalarValue {}
extension Int64: ScalarValue {}
extension UInt: ScalarValue {}
extension Int: ScalarValue {}
