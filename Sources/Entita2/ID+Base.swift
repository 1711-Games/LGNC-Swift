import LGNCore

public protocol Identifiable: Hashable {
    var _bytes: Bytes { get }
}

public extension E2 {
    struct ID<Value: Codable & Hashable>: Identifiable {
        internal let value: Value

        public var _bytes: Bytes {
            return LGNCore.getBytes(value)
        }

        public init(value: Value) {
            self.value = value
        }
    }
}

extension E2.ID: Equatable {}
