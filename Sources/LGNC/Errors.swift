import Foundation
import LGNCore

public protocol ClientError: Error {
    func getErrorTuple() -> (message: String, code: Int)
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
        case TransportNotAllowed(LGNCore.Transport)
        case GeneralError(String, Int)
        case RemoteContractExecutionFailed
        case InternalError

        public var isPublicError: Bool {
            let result: Bool

            switch self {
            case .URINotFound(_), .TransportNotAllowed(_), .InternalError: result = true
            default: result = false
            }

            return result
        }

        public func getErrorTuple() -> (message: String, code: Int) {
            switch self {
            case let .URINotFound(URI):
                return (message: "URI '\(URI)' not found", code: 404)
            case let .TransportNotAllowed(transport):
                return (message: "Transport '\(transport.rawValue)' not allowed", code: 405)
            case .InternalError, .RemoteContractExecutionFailed:
                return (message: "Internal server error", code: 500)
            case let .GeneralError(message, code):
                return (message: message, code: code)
            }
        }
    }
}
