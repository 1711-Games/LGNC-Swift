public typealias _ID = Identifier

// There is a reason why this is not done via Foundation UUID - these ids may not be exactly in guid format

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

extension Identifier: Hashable {
//    public var hashValue: Int {
//        return get().hash
//    }
//
//    public static func == (lhs: Identifier, rhs: Identifier) -> Bool {
//        return lhs.get() == rhs.get()
//    }
}
