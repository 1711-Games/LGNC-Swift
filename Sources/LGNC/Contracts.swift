import Entita
import LGNCore
import LGNS
import NIO

public protocol Contract {
    associatedtype Request: ContractEntity
    associatedtype Response: ContractEntity
    associatedtype ParentService: Service
    associatedtype Callback = (Request, LGNC.RequestInfo) -> Future<Response>
    associatedtype NonFutureCallback = (Request, LGNC.RequestInfo) throws -> Response
    associatedtype NormalizedCallback = (Request, LGNC.RequestInfo) -> Future<Entity>

    typealias Map = [String: (transports: [LGNC.Transport], executor: Service.Executor)]

    static var URI: String { get }
}

public enum ContractVisibility {
    case Public, Private
}

public extension Contract {
    typealias InitValidationErrors = [String: [ValidatorError]]

    static func normalize(
        callback: @escaping (Request, LGNC.RequestInfo) -> Future<Response>
    ) -> (Request, LGNC.RequestInfo) -> Future<Entity> {
        return { callback($0, $1).map { $0 as Entity } }
    }

    static func futurize(
        callback: @escaping (Request, LGNC.RequestInfo) throws -> Response
    ) -> (Request, LGNC.RequestInfo) -> Future<Response> {
        return { (request, requestInfo) -> Future<Response> in
            let promise: Promise<Response> = requestInfo.eventLoop.makePromise()
            do { promise.succeed(try callback(request, requestInfo)) }
            catch { promise.fail(error) }
            return promise.futureResult
        }
    }

    // Not to be used directly
    static func _invoke(
        with callback: Optional < (Request, LGNC.RequestInfo) -> Future < Entity>>,
        request: Entita.Dict,
        requestInfo: LGNC.RequestInfo,
        name: String
    ) -> Future<Entity> {
        guard let callback = callback else {
            return requestInfo.eventLoop.makeFailedFuture(LGNC.E.ControllerError("No callback for contract '\(name)'"))
        }
        return Request.initWithValidation(from: request, on: requestInfo.eventLoop)
            .flatMap { callback($0, requestInfo) }
            .map { $0 as Entity }
    }
}

public struct Contracts {}
