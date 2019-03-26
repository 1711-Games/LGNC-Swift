public extension Entita {
    enum E: Error {
        case ExtractError(String, Any?)
        case EncodeError(String)
        case DecodeError(String)
    }
}
