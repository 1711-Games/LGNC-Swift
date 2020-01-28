public typealias _ID = Identifier

/// A struct representing any identifier
///
/// There is a reason why this is not done via Foundation UUID - our ids might not be exactly in UUID format
public struct Identifier {
    private var value: String
    public var string: String {
        return self.get()
    }

    public init(_ value: String) {
        self.value = value
    }

    public init(_ ID: Identifier) {
        self.init(ID.get())
    }

    public func get() -> String {
        return value
    }
}

extension Identifier: CustomStringConvertible {
    public var description: String {
        return self.get()
    }
}

extension Identifier: Hashable {}
