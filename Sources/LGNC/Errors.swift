import Foundation

public protocol ClientError: Error {
    func getErrorTuple() -> (message: String, code: Int)
}

public extension Dictionary where Key == String, Value == [ClientError] {
    public func getExactlyOneErrorFor(field: String) -> ClientError? {
        guard let list = self[field], list.count == 1, let result = list.first else {
            return nil
        }
        return result
    }

    public func getGeneralError() -> ClientError? {
        return self.getExactlyOneErrorFor(field: "_")
    }

    public func getGeneralErrorCode() -> Int? {
        return self.getGeneralError()?.getErrorTuple().code
    }
}

public extension LGNC {
    public enum E: Error {
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

    public enum ContractError: ClientError {
        case URINotFound(String)
        case TransportNotAllowed(LGNC.Transport)
        case GeneralError(String, Int)
        case RemoteContractExecutionFailed
        case InternalError
        
        public func getErrorTuple() -> (message: String, code: Int) {
            switch self {
            case .URINotFound(let URI):
                return (message: "URI '\(URI)' not found", code: 404)
            case .TransportNotAllowed(let transport):
                return (message: "Transport '\(transport.rawValue)' not allowed", code: 405)
            case .InternalError, .RemoteContractExecutionFailed:
                return (message: "Internal server error", code: 500)
            case .GeneralError(let message, let code):
                return (message: message, code: code)
            }
        }
    }
}
