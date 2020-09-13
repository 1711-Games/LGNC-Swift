import Foundation
import LGNCore
import Entita

extension Data {
    public var string: String {
        String(data: self, encoding: .utf8)!
    }
}

extension Services.Shared.Baz: CustomStringConvertible {
    public var description: String {
        "[Gerreg:\(self.Gerreg),Tlaalt:\(self.Tlaalt)]"
    }
}

extension Array {
    public var descr: String {
        "[\(self.map { "\($0)" }.joined(separator: ","))]"
    }
}

extension Dictionary {
    public var descr: String {
        "[\(self.map { "\($0):\($1)" }.joined(separator: ","))]"
    }
}
