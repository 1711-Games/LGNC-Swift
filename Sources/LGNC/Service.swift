import Entita
import Foundation
import LGNCore
import LGNP
import LGNS

/// A type-erased service
public protocol Service {
    /// A storage for all keydictionaries of requests and responses of all contracts
    static var keyDictionary: [String: Entita.Dict] { get }

    /// A storage for storing `URI -> Contract` connection, used for routing
    static var contractMap: [String: AnyContract.Type] { get }

    /// Contains allowed service transports and respective ports
    static var transports: [LGNCore.Transport: Int] { get }

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
    ) async throws -> LGNC.Entity.Result

    /// Starts a LGNS server at given target. Returns a future with a server, which must be waited for until claiming the server as operational.
    static func startServerLGNS(
        at target: LGNS.Server.BindTo?,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup,
        requiredBitmask: LGNP.Message.ControlBitmask,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount
    ) async throws -> AnyServer

    /// Starts a HTTP server at given target. Returns a future with a server, which must be waited for until claiming the server as operational.
    static func startServerHTTP(
        at target: LGNS.Server.BindTo?,
        eventLoopGroup: EventLoopGroup,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount
    ) async throws -> AnyServer
}

public extension Service {
    static var info: [String: String] { [:] }

    static var webSocketURI: String? { nil }

    static var webSocketContracts: [AnyContract.Type] {
        self.contractMap
            .map { $0.value }
            .filter { $0.isWebSocketTransportAvailable }
    }

    static var webSocketOnlyContracts: [AnyContract.Type] {
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
                Logger(label: "LGNC.Contracts.Checkin").error("Contract '\(URI)' is not guaranteed")
                return true
            }
            .count == 0
    }

    static func executeContract(URI: String, dict: Entita.Dict) async throws -> LGNC.Entity.Result {
        let context = Task.local(\.context)
        let profiler = LGNCore.Profiler.begin()
        let result: LGNC.Entity.Result

        do {
            guard let contractInfo = self.contractMap[URI] else {
                throw LGNC.ContractError.URINotFound(URI)
            }
            guard LGNC.ALLOW_ALL_TRANSPORTS == true || contractInfo.transports.contains(context.transport) else {
                throw LGNC.ContractError.TransportNotAllowed(context.transport)
            }

            do {
                result = LGNC.Entity.Result(from: try await contractInfo.invoke(with: dict))
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
                    result = .init(from: errors)
                } catch {
                    context.logger.critical("Extremely unexpected error: \(error)")
                    result = .internalError
                }
            }
        } catch let error as LGNC.ContractError {
            result = context.isSecure || error.isPublicError
                ? .init(from: [LGNC.GLOBAL_ERROR_KEY: [error]])
                : .internalError
            context.logger.error("Contract error: \(error)")
        } catch {
            context.logger.critical("Quite uncaught error: \(error)")
            result = .internalError
        }

        context.logger.info(
            "[\(context.clientAddr)] [\(context.transport.rawValue)] [\(URI)] \(profiler.end().rounded(toPlaces: 4))s"
        )

        return result
    }

    internal static func checkGuarantees() throws {
        if LGNC.ALLOW_INCOMPLETE_GUARANTEE == false && Self.checkContractsCallbacks() == false {
            throw LGNC.E.serverError(
                "Not all contracts are guaranteed (to disable set LGNC.ALLOW_PART_GUARANTEE to true)"
            )
        }
    }

    internal static func unwrapAddress(from target: LGNCore.Address?) throws -> LGNCore.Address {
        let address: LGNCore.Address

        if let target = target {
            address = target
        } else {
            guard let port = Self.transports[.LGNS] else {
                throw LGNC.E.serverError("LGNS transport is not available in service")
            }
            address = .port(port)
        }

        return address
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
}
