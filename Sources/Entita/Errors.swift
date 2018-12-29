public extension Entita {
    public enum E: Error {
        case ExtractError(String, Any?)
        case EncodeError(String)
        case DecodeError(String)
    }
}
