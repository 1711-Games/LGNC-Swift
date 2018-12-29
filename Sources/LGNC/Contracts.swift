import LGNCore
import LGNS
import Entita
import NIO

public protocol Contract {
    associatedtype Request: ContractEntity
    associatedtype Response: ContractEntity
    associatedtype ParentService: Service
    associatedtype Callback = (Request, RequestInfo) -> Future<Response>
    associatedtype NonFutureCallback = (Request, RequestInfo) throws -> Response
    associatedtype NormalizedCallback = (Request, RequestInfo) -> Future<Entity>

    static var URI: String { get }
}

public extension Contract {
    public typealias InitValidationErrors = [String: [ValidatorError]]

    public static func normalize(
        callback: @escaping (Request, RequestInfo) -> Future<Response>
    ) -> (Request, RequestInfo) -> Future<Entity> {
        return { callback($0, $1).map { $0 as Entity } }
    }

    public static func futurize(
        callback: @escaping (Request, RequestInfo) throws -> Response
    ) -> (Request, RequestInfo) -> Future<Response> {
        return { (request, requestInfo) -> Future<Response> in
            let promise: Promise<Response> = requestInfo.eventLoop.newPromise()
            do { promise.succeed(result: try callback(request, requestInfo)) }
            catch { promise.fail(error: error) }
            return promise.futureResult
        }
    }

    // Not to be used directly
    public static func _invoke(
        with callback: Optional<(Request, RequestInfo) -> Future<Entity>>,
        request: Entita.Dict,
        requestInfo: RequestInfo,
        name: String
    ) -> Future<Entity> {
        guard let callback = callback else {
            return requestInfo.eventLoop.newFailedFuture(error: LGNC.E.ControllerError("No callback for contract '\(name)'"))
        }
        return Request.initWithValidation(from: request, on: requestInfo.eventLoop)
            .then { callback($0, requestInfo) }
            .map { $0 as Entity }
    }
}

public struct Contracts {

}
