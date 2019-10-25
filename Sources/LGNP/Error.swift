public extension LGNP {
    enum E: Error {
        case InvalidMessage(String)
        case InvalidMessageProtocol(String)
        case InvalidMessageLength(String)
        case InvalidSalt(String)
        case InvalidKey(String)
        case InvalidIV(String)
        case EncryptionFailed(String)
        case DecryptionFailed(String)
        case CompressionFailed(String)
        case DecompressionFailed(String)
        case ParsingFailed(String)
        case SignatureVerificationFailed(String)
        case URIParsingFailed(String)
        case EncodingFailed(String)
        case TooShortHeaderToParse(String)
        case MetaSectionNotFound
    }
}
