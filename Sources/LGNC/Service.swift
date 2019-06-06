import Entita
import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

public protocol Service {
    typealias Executor = (LGNCore.RequestInfo, Entita.Dict) -> Future<Entity>

    static var keyDictionary: [String: Entita.Dict] { get }
    static var contractMap: Contract.Map { get }
    static var transports: [LGNCore.Transport: Int] { get }
    static var info: [String: String] { get }

    static func checkContractsCallbacks() -> Bool
    static func executeContract(
        URI: String,
        uuid: UUID,
        payload: Entita.Dict,
        requestInfo: LGNCore.RequestInfo
    ) -> Future<Entity>
    static func serveLGNS(
        at target: LGNS.Server.BindTo?,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup,
        requiredBitmask: LGNP.Message.ControlBitmask,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount,
        promise: PromiseVoid?
    ) throws
    static func serveHTTP(
        at target: LGNS.Server.BindTo?,
        eventLoopGroup: EventLoopGroup,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount,
        promise: PromiseVoid?
    ) throws
}

public extension LGNC {
    typealias ServicesRegistry = [
        String: (
            transports: [LGNCore.Transport: Int],
            contracts: [
                String: (
                    visibility: ContractVisibility,
                    transports: [LGNCore.Transport]
                )
            ]
        )
    ]
}

public extension Service {
    static func executeContract(
        URI: String,
        uuid: UUID,
        payload: Entita.Dict,
        requestInfo: LGNCore.RequestInfo
    ) -> Future<Entity> {
        let result: Future<LGNC.Entity.Result>

        let profiler = LGNCore.Profiler.begin()

        do {
            guard let contractInfo = self.contractMap[URI] else {
                throw LGNC.ContractError.URINotFound(URI)
            }
            guard LGNC.ALLOW_ALL_TRANSPORTS == true || contractInfo.transports.contains(requestInfo.transport) else {
                throw LGNC.ContractError.TransportNotAllowed(requestInfo.transport)
            }
            result = contractInfo
                .executor(requestInfo, payload)
                .map { LGNC.Entity.Result(from: $0) }
                .recover { error in
                    do {
                        switch error {
                        case let LGNC.E.UnpackError(error):
                            requestInfo.logger.error("\(error)")
                            throw LGNC.E.clientError("Invalid request")
                        case let LGNC.E.MultipleError(errors):
                            throw LGNC.E.MultipleError(errors) // rethrow
                        case let LGNC.E.DecodeError(errors):
                            throw LGNC.E.MultipleError(errors)
                        case let error as ClientError:
                            throw LGNC.E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [error]])
                        default:
                            requestInfo.logger.error("Uncaught error: \(error)")
                            throw LGNC.E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [LGNC.ContractError.InternalError]])
                        }
                    } catch let LGNC.E.MultipleError(errors) {
                        return LGNC.Entity.Result(from: errors)
                    } catch {
                        requestInfo.logger.critical("Extremely unexpected error: \(error)")
                        return LGNC.Entity.Result.internalError
                    }
                }
        } catch let error as LGNC.ContractError {
            result = requestInfo.eventLoop.makeSucceededFuture(
                requestInfo.isSecure
                    ? LGNC.Entity.Result(from: [LGNC.GLOBAL_ERROR_KEY: [error]])
                    : LGNC.Entity.Result.internalError
            )
            requestInfo.logger.error("Contract error: \(error)")
        } catch let error {
            requestInfo.logger.critical("Quite uncaught error: \(error)")
            result = requestInfo.eventLoop.makeSucceededFuture(LGNC.Entity.Result.internalError)
        }

        result.whenComplete { result in
            let clientAddr = requestInfo.clientAddr
            let transport = requestInfo.transport.rawValue
            let executionTime = profiler.end().rounded(toPlaces: 4)

            requestInfo.logger.info(
                "[\(clientAddr)] [\(transport)] [\(URI)] \(executionTime)s"
            )
        }

        return result.map { $0 as Entity }
    }

    internal static func checkGuarantees() throws {
        if LGNC.ALLOW_INCOMPLETE_GUARANTEE == false && Self.checkContractsCallbacks() == false {
            throw LGNC.E.serverError("Not all contracts are guaranteed (to disable set LGNC.ALLOW_PART_GUARANTEE to true)")
        }
    }

    internal static func unwrapAddress(from target: LGNS.Address?) throws -> LGNS.Address {
        let address: Address
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
}
