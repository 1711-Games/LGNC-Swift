import LGNCore

public extension Identifiable {
    var _bytes: Bytes {
        LGNCore.getBytes(self)
    }
}

extension Int: Identifiable {}
extension String: Identifiable {}
