import Foundation
import LGNCore
import LGNP
import LGNS
import Entita
import NIO

public protocol Service {
    typealias Executor = (RequestInfo, Entita.Dict) -> Future<Entity>

    static var keyDictionary: [String: Entita.Dict] { get }
    static var contractExecutorMap: [String: Executor] { get }
    static var port: Int { get }
    static var info: [String: String] { get }

    static func checkContractsCallbacks() -> Bool
    static func serveLGNS(
        at target: LGNS.Server.BindTo,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: MultiThreadedEventLoopGroup,
        requiredBitmask: LGNP.Message.ControlBitmask,
        readTimeout: TimeAmount,
        writeTimeout: TimeAmount,
        promise: PromiseVoid?
    ) throws
}

public enum ServiceVisibility {
    case Public, Private
}

public extension LGNC {
    public typealias ServicesRegistry = [String: (port: Int, contracts: [String: ServiceVisibility])]
}

public extension Service {
    public static func executeContract(
        URI: String,
        uuid: String,
        payload: Entita.Dict,
        requestInfo info: RequestInfo
    ) -> Future<Entity> {
        let result: Future<LGNC.Entity.Result>
        do {
            guard let contractExecutor = self.contractExecutorMap[URI] else {
                throw LGNC.ContractError.URINotFound(URI)
            }
            result = contractExecutor(info, payload)
                .map { LGNC.Entity.Result(from: $0) }
                .mapIfError { error in
                    do {
                        switch error {
                        case let LGNC.E.UnpackError(error):
                            LGNCore.log(error, prefix: info.uuid.string)
                            throw LGNC.E.clientError("Invalid request")
                        case let LGNC.E.MultipleError(errors):
                            throw LGNC.E.MultipleError(errors) // rethrow
                        case let LGNC.E.DecodeError(errors):
                            throw LGNC.E.MultipleError(errors)
                        case let error as ClientError:
                            throw LGNC.E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [error]])
                        default:
                            LGNCore.log("Uncaught error: \(error)", prefix: uuid)
                            throw LGNC.E.MultipleError([LGNC.GLOBAL_ERROR_KEY: [LGNC.ContractError.InternalError]])
                        }
                    } catch let LGNC.E.MultipleError(errors) {
                        return LGNC.Entity.Result(from: errors)
                    } catch {
                        LGNCore.log("Extremely unexpected error: \(error)", prefix: info.uuid.string)
                        return LGNC.Entity.Result.internalError
                    }
                }
        } catch let error as LGNC.ContractError {
            result = info.eventLoop.newSucceededFuture(
                result: info.isSecure
                    ? LGNC.Entity.Result(from: [LGNC.GLOBAL_ERROR_KEY: [error]])
                    : LGNC.Entity.Result.internalError
            )
            LGNCore.log("Contract error: \(error)")
        } catch let error {
            LGNCore.log("Quite uncaught error: \(error)", prefix: uuid)
            result = info.eventLoop.newSucceededFuture(result: LGNC.Entity.Result.internalError)
        }
        return result.map { $0 as Entity }
    }
}
