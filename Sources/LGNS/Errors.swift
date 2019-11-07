internal protocol ErrorTupleConvertible: Error {
    var tuple: (code: Int, message: String) { get }
}

public extension LGNS {
    enum E: Error {
        case RequiredBitmaskNotSatisfied
        case Timeout
        case ConnectionClosed
        case LGNPError(String)
        case UnknownError(String)
    }

}

extension LGNS.E: ErrorTupleConvertible {
    var tuple: (code: Int, message: String) {
        let result: (code: Int, message: String)

        switch self {
        case .RequiredBitmaskNotSatisfied:
            result = (201, "Required bitmask not satisfied")
        case .Timeout:
            result = (202, "Connection timeout")
        case .ConnectionClosed:
            result = (203, "Connection closed unexpectedly")
        case let .LGNPError(description):
            result = (204, "LGNP error: \(description)")
        case let .UnknownError(description):
            result = (205, "Unknown error: \(description)")
        }

        return result
    }
}

extension LGNP.E: ErrorTupleConvertible {
    public var tuple: (code: Int, message: String) {
        let result: (code: Int, message: String)

        switch self {
        case let .InvalidMessage(message):
            result = (101, message)
        case let .InvalidMessageProtocol(message):
            result = (102, message)
        case let .InvalidMessageLength(message):
            result = (103, message)
        case let .InvalidSalt(message):
            result = (104, message)
        case let .InvalidKey(message):
            result = (105, message)
        case let .InvalidIV(message):
            result = (106, message)
        case let .EncryptionFailed(message):
            result = (107, message)
        case let .DecryptionFailed(message):
            result = (108, message)
        case let .CompressionFailed(message):
            result = (109, message)
        case let .DecompressionFailed(message):
            result = (110, message)
        case let .ParsingFailed(message):
            result = (111, message)
        case let .SignatureVerificationFailed(message):
            result = (112, message)
        case let .URIParsingFailed(message):
            result = (113, message)
        case let .EncodingFailed(message):
            result = (114, message)
        case let .TooShortHeaderToParse(message):
            result = (115, message)
        case .MetaSectionNotFound:
            result = (116, "Meta section not found")
        }

        return result
    }
}
