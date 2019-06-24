import Entita
import LGNCore
import LGNS
import NIO

public protocol SomeContract {
    static var URI: String { get }
    static var transports: [LGNCore.Transport] { get }
    static var preferredTransport: LGNCore.Transport { get }
    static var contentTypes: [LGNCore.ContentType] { get }
    static var preferredContentType: LGNCore.ContentType { get }
    static var guaranteeClosure: Optional<(Entity, LGNCore.RequestInfo) -> Future<Entity>> { get set }
    static var isGuaranteed: Bool { get }

    static func invoke(with dict: Entita.Dict, requestInfo: LGNCore.RequestInfo) -> Future<Entity>
}

public extension SomeContract {
    static var preferredTransport: LGNCore.Transport {
        guard self.transports.count > 0 else {
            Logger(label: "LGNC.SomeContract").error("Empty transports in contract \(Self.self), returning .LGNS")
            return .LGNS
        }

        if self.transports.contains(.LGNS) {
            return .LGNS
        }

        return .HTTP
    }

    static var preferredContentType: LGNCore.ContentType {
        guard self.transports.count > 0 else {
            Logger(label: "LGNC.SomeContract").error("Empty content-types in contract \(Self.self), returning .JSON")
            return .JSON
        }

        if Self.preferredTransport == .LGNS && self.contentTypes.contains(.MsgPack) {
            return .MsgPack
        }

        return .JSON
    }

    static var isGuaranteed: Bool {
        return self.guaranteeClosure != nil
    }
}

public protocol Contract: SomeContract {
    associatedtype Request: ContractEntity
    associatedtype Response: ContractEntity
    associatedtype ParentService: Service
    associatedtype Closure = (Request, LGNCore.RequestInfo) -> Future<Response>
    associatedtype NonFutureClosure = (Request, LGNCore.RequestInfo) throws -> Response

    static func guarantee(_ guaranteeClosure: @escaping (Request, LGNCore.RequestInfo) -> Future<Response>)
    static func guarantee(_ guaranteeClosure: @escaping (Request, LGNCore.RequestInfo) throws -> Response)
}

public enum ContractVisibility {
    case Public, Private
}

public extension Contract {
    typealias InitValidationErrors = [String: [ValidatorError]]

    static func guarantee(_ guaranteeClosure: @escaping (Request, LGNCore.RequestInfo) -> Future<Response>) {
        self.guaranteeClosure = self.normalize(guaranteeClosure: guaranteeClosure)
    }

    static func guarantee(_ guaranteeClosure: @escaping (Request, LGNCore.RequestInfo) throws -> Response) {
        self.guaranteeClosure = self.normalize(guaranteeClosure: guaranteeClosure)
    }

    static func normalize(
        guaranteeClosure: @escaping (Request, LGNCore.RequestInfo) -> Future<Response>
    ) -> (Entity, LGNCore.RequestInfo) -> Future<Entity> {
        return { normalizedRequest, requestInfo in
            return guaranteeClosure(normalizedRequest as! Request, requestInfo).map { $0 as Entity }
        }
    }

    static func normalize(
        guaranteeClosure: @escaping (Request, LGNCore.RequestInfo) throws -> Response
    ) -> (Entity, LGNCore.RequestInfo) -> Future<Entity> {
        return self.normalize(guaranteeClosure: { (request, requestInfo) -> Future<Response> in
            let promise: Promise<Response> = requestInfo.eventLoop.makePromise()

            do {
                promise.succeed(try guaranteeClosure(request, requestInfo))
            }
            catch {
                promise.fail(error)
            }

            return promise.futureResult
        })
    }

    /// Not to be used directly
    static func invoke(
        with dict: Entita.Dict,
        requestInfo: LGNCore.RequestInfo
    ) -> Future<Entity> {
        guard let guaranteeClosure = self.guaranteeClosure else {
            return requestInfo.eventLoop.makeFailedFuture(
                LGNC.E.ControllerError(
                    "No guarantee closure for contract '\(self.URI)'"
                )
            )
        }
        return Request
            .initWithValidation(from: dict, requestInfo: requestInfo)
            .flatMap { guaranteeClosure($0 as Entity, requestInfo) }
            .map { $0 as Entity }
    }
}

public struct Contracts {}
