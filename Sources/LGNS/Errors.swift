public extension LGNS {
    public enum E: Error {
        case RequiredBitmaskNotSatisfied
        case Timeout
        case ConnectionClosed
        case LGNPError(String)
        case UnknownError(String)
        
        public var description: String {
            switch self {
            case .RequiredBitmaskNotSatisfied:
                return "Required bitmask not satisfied"
            case .Timeout:
                return "Connection timeout"
            case .ConnectionClosed:
                return "Connection closed unexpectedly"
            case let .LGNPError(description):
                return "LGNP error: \(description)"
            case let .UnknownError(description):
                return "Unknown error: \(description)"
            }
        }
    }
}
