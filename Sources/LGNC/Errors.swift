import Foundation
import LGNCore

public protocol ClientError: Error {
    func getErrorTuple() -> ErrorTuple
}

public extension Dictionary where Key == String, Value == [ClientError] {
    func getExactlyOneErrorFor(field: String) -> ClientError? {
        guard let list = self[field], list.count == 1, let result = list.first else {
            return nil
        }
        return result
    }

    func getGeneralError() -> ClientError? {
        return getExactlyOneErrorFor(field: "_")
    }

    func getGeneralErrorCode() -> Int? {
        return getGeneralError()?.getErrorTuple().code
    }
}

public extension LGNC {
    enum E: Error {
        case DecodeError([String: [ValidatorError]])
        case MultipleFieldDecodeError([ValidatorError])
        case UnpackError(String)
        case ControllerError(String)
        case ServiceError(String)
        case MultipleError([String: [ClientError]])

        public static func singleError(field: String, message: String, code: Int) -> E {
            return E.MultipleError([field: [ContractError.GeneralError(message, code)]])
        }

        public static func clientError(_ message: String, _ code: Int = 400) -> E {
            return E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [ContractError.GeneralError(message, code)]])
        }

        public static func serverError(_ message: String, _ code: Int = 500) -> E {
            return E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [ContractError.GeneralError(message, code)]])
        }
    }

    enum ContractError: ClientError {
        case URINotFound(String)
        case ExtraFieldsInRequest([String])
        case AmbiguousInput(String)
        case TransportNotAllowed(LGNCore.Transport)
        case GeneralError(String, Int)
        case RemoteContractExecutionFailed
        case InternalError

        public var isPublicError: Bool {
            let result: Bool

            switch self {
            case .URINotFound(_), .TransportNotAllowed(_), .InternalError, .ExtraFieldsInRequest(_): result = true
            default: result = false
            }

            return result
        }

        public func getErrorTuple() -> ErrorTuple {
            let result: ErrorTuple

            switch self {
            case let .URINotFound(URI):
                result = (code: 404, message: "URI '\(URI)' not found")
            case let .ExtraFieldsInRequest(fields):
                result = (
                    code: 422,
                    message: "Input contains unexpected items: \(fields.map { "'\($0)'" }.joined(separator: ", "))"
                )
            case let .AmbiguousInput(string):
                result = (code: 300, message: string)
            case let .TransportNotAllowed(transport):
                result = (code: 405, message: "Transport '\(transport.rawValue)' not allowed")
            case .InternalError, .RemoteContractExecutionFailed:
                result = (code: 500, message: "Internal server error")
            case let .GeneralError(message, code):
                result = (code: code, message: message)
            }

            return result
        }
    }
}
