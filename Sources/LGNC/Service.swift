import Entita
import Foundation
import LGNCore
import LGNLog
import LGNP
import LGNS

public protocol Service {
    /// A storage for all keydictionaries of requests and responses of all contracts
    static var keyDictionary: [String: Entita.Dict] { get }

    /// A storage for storing `URI -> Contract` connection, used for routing
    static var contractMap: [String: any Contract.Type] { get }

    /// Contains allowed service transports and respective ports
    static var transports: [LGNCore.Transport: Int] { get }

    /// Indicates whether LGNC should do case-sensitive request routing
    static var caseSensitiveURIs: Bool { get }

    /// A storage for custom KV info defined in LGNC schema
    static var info: [String: String] { get }

    static var webSocketURI: String? { get }

    /// A storage for getting contracts guarantee statuses
    static var guaranteeStatuses: [String: Bool] { get set }

    /// Checks contracts guarantee statuses and returns `false` if some contracts are not garanteed
    static func checkContractsCallbacks() -> Bool

    /// Executes a contract at given URI with given raw dictionary and context
    static func executeContract(
        URI: String,
        dict: Entita.Dict
    ) async throws -> ContractExecutionResult
}

public extension Service {
    static var caseSensitiveURIs: Bool { false }

    static var info: [String: String] { [:] }

    static var webSocketURI: String? { nil }

    static var webSocketContracts: [any Contract.Type] {
        self.contractMap
            .map { $0.value }
            .filter { $0.isWebSocketTransportAvailable }
    }

    static var webSocketOnlyContracts: [any Contract.Type] {
        self.contractMap
            .map { $0.value }
            .filter { $0.transports == [.WebSocket] }
    }

    static func checkContractsCallbacks() -> Bool {
        self.guaranteeStatuses
            .filter { URI, status in
                if status == true {
                    return false
                }
                Logger.current.error("Contract '\(URI)' is not guaranteed")
                return true
            }
            .count == 0
    }

    static func executeContract(
        URI: String,
        dict: Entita.Dict
    ) async throws -> ContractExecutionResult {
        let context = LGNCore.Context.current
        let result: ContractExecutionResult

        do {
            guard let contractInfo = self.contractMap[Self.caseSensitiveURIs ? URI : URI.lowercased()] else {
                throw LGNC.ContractError.URINotFound(URI) // todo customizable 404 errors
            }
            guard LGNC.ALLOW_ALL_TRANSPORTS == true || contractInfo.transports.contains(context.transport) else {
                throw LGNC.ContractError.TransportNotAllowed(context.transport)
            }

            do {
                let rawResponse = try await contractInfo._invoke(with: dict)
                switch rawResponse.result {
                case let .Structured(entity):
                    result = .init(result: .Structured(LGNC.Entity.Result(from: entity)), meta: rawResponse.meta)
                case let .Binary(entity, _):
                    // for LGNS result must always be structured (todo: make binary result actually binary maybe?)
                    if context.transport == .LGNS {
                        result = .init(result: .Structured(LGNC.Entity.Result(from: entity)), meta: rawResponse.meta)
                    } else {
                        result = rawResponse
                    }
                }
            } catch {
                do {
                    switch error {
                    case let LGNC.E.UnpackError(error):
                        context.logger.error("\(error)")
                        throw LGNC.E.clientError("Invalid request")
                    case let LGNC.E.MultipleError(errors):
                        throw LGNC.E.MultipleError(errors) // rethrow
                    case let LGNC.E.DecodeError(errors):
                        throw LGNC.E.MultipleError(errors)
                    case let error as ClientError:
                        throw LGNC.E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [error]])
                    default:
                        context.logger.error("Uncaught error: \(error)")
                        throw LGNC.E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [LGNC.ContractError.InternalError]])
                    }
                } catch let LGNC.E.MultipleError(errors) {
                    result = .init(result: LGNC.Entity.Result(from: errors))
                } catch {
                    context.logger.critical("Extremely unexpected error: \(error)")
                    result = .init(result: LGNC.Entity.Result.internalError)
                }
            }
        } catch let error as LGNC.ContractError {
            result = .init(
                result: context.isSecure || error.isPublicError
                    ? LGNC.Entity.Result(from: [LGNC.GLOBAL_ERROR_KEY: [error]])
                    : LGNC.Entity.Result.internalError
            )
            context.logger.error("Contract error: \(error)")
        } catch {
            context.logger.critical("Quite uncaught error: \(error)")
            result = .init(result: LGNC.Entity.Result.internalError)
        }

        context.logger.info(
            "[\(context.clientAddr)] [\(context.transport.rawValue)] [\(URI)] \(context.profiler.mark("contract executed").elapsed.rounded(toPlaces: 4))s"
        )

        return result
    }

    internal static func checkGuarantees() throws {
        if LGNC.ALLOW_INCOMPLETE_GUARANTEE == false && Self.checkContractsCallbacks() == false {
            throw LGNC.E.serverError(
                "Not all contracts are guaranteed (to disable set LGNC.ALLOW_INCOMPLETE_GUARANTEE to true)"
            )
        }
    }

    internal static func validate(transport: LGNCore.Transport) throws {
        guard let _ = self.transports[transport] else {
            throw LGNC.E.ServiceError("Transport \(transport) not supported for service")
        }
    }

    internal static func validate(controlBitmask: LGNP.Message.ControlBitmask) throws {
        guard controlBitmask.hasContentType else {
            throw LGNC.E.ServiceError("No content type set in control bitmask (or plain text set)")
        }
    }

    internal static func unwrapAddressGeneric(
        from target: LGNCore.Address?,
        transport: LGNCore.Transport
    ) throws -> LGNCore.Address {
        let address: LGNCore.Address

        if let target = target {
            address = target
        } else {
            guard let port = Self.transports[transport] else {
                throw LGNC.E.serverError("\(transport) transport is not available in service '\(self)'")
            }
            address = .port(port)
        }

        return address
    }
}
