import LGNCore

/// A protocol for anything that identifies something and can be represented as bytes
public protocol Identifiable: Hashable {
    var _bytes: Bytes { get }
}

public extension E2 {
    struct ID<Value: Codable & Hashable>: Identifiable {
        public let value: Value

        @inlinable public var _bytes: Bytes {
            LGNCore.getBytes(value)
        }

        public init(value: Value) {
            self.value = value
        }
    }
}

extension E2.ID: Equatable {}
