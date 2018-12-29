import LGNCore

public extension Identifiable {
    public var _bytes: Bytes {
        return LGNCore.getBytes(self)
    }
}

extension Int: Identifiable {}
