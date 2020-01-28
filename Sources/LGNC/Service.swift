import Entita
import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

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

    /// A storage for getting contracts guarantee statuses
    static var guaranteeStatuses: [String: Bool] { get set }

    /// Checks contracts guarantee statuses and returns `false` if some contracts are not garanteed
    static func checkContractsCallbacks() -> Bool

    /// Executes a contract at given URI with given raw dictionary and context
    static func executeContract(
        URI: String,
        dict: Entita.Dict,
        context: LGNCore.Context
    ) -> Future<Entity>

    /// Starts a LGNS server at given target. Returns a future with a server, which must be waited for until claiming the server as operational.
    static func startServerLGNS(
        at target: LGNS.Server.BindTo?,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup,
        requiredBitmask: LGNP.Message.ControlBitmask,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount
    ) -> Future<AnyServer>

    /// Starts a HTTP server at given target. Returns a future with a server, which must be waited for until claiming the server as operational.
    static func startServerHTTP(
        at target: LGNS.Server.BindTo?,
        eventLoopGroup: EventLoopGroup,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount
    ) -> Future<AnyServer>
}

public extension LGNC {
    typealias ServicesRegistry = [
        String: (
            transports: [LGNCore.Transport: Int],
            contracts: [
                String: (visibility: ContractVisibility, transports: [LGNCore.Transport])
            ]
        )
    ]
}

public extension Service {
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

    static func executeContract(
        URI: String,
        dict: Entita.Dict,
        context: LGNCore.Context
    ) -> Future<Entity> {
        let result: Future<LGNC.Entity.Result>

        let profiler = LGNCore.Profiler.begin()

        do {
            guard let contractInfo = self.contractMap[URI] else {
                throw LGNC.ContractError.URINotFound(URI)
            }
            guard LGNC.ALLOW_ALL_TRANSPORTS == true || contractInfo.transports.contains(context.transport) else {
                throw LGNC.ContractError.TransportNotAllowed(context.transport)
            }
            result = contractInfo
                .invoke(with: dict, context: context)
                .map { response, meta in LGNC.Entity.Result(from: response, meta: meta) }
                .recover { error in
                    let _result: LGNC.Entity.Result

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
                        _result = LGNC.Entity.Result(from: errors)
                    } catch {
                        context.logger.critical("Extremely unexpected error: \(error)")
                        _result = LGNC.Entity.Result.internalError
                    }

                    return _result
                }
        } catch let error as LGNC.ContractError {
            result = context.eventLoop.makeSucceededFuture(
                context.isSecure
                    ? LGNC.Entity.Result(from: [LGNC.GLOBAL_ERROR_KEY: [error]])
                    : LGNC.Entity.Result.internalError
            )
            context.logger.error("Contract error: \(error)")
        } catch let error {
            context.logger.critical("Quite uncaught error: \(error)")
            result = context.eventLoop.makeSucceededFuture(LGNC.Entity.Result.internalError)
        }

        result.whenComplete { result in
            let clientAddr = context.clientAddr
            let transport = context.transport.rawValue
            let executionTime = profiler.end().rounded(toPlaces: 4)

            context.logger.info(
                "[\(clientAddr)] [\(transport)] [\(URI)] \(executionTime)s"
            )
        }

        return result.map { $0 as Entity }
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
