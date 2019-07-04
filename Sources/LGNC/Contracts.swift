import Entita
import LGNCore
import LGNS
import NIO

public typealias Meta = LGNC.Entity.Meta

public protocol SomeContract {
    typealias Closure = (Entity, LGNCore.RequestInfo) -> Future<(response: Entity, meta: Meta)>

    static var URI: String { get }
    static var transports: [LGNCore.Transport] { get }
    static var preferredTransport: LGNCore.Transport { get }
    static var contentTypes: [LGNCore.ContentType] { get }
    static var preferredContentType: LGNCore.ContentType { get }
    static var guaranteeClosure: Optional<Self.Closure> { get set }
    static var isGuaranteed: Bool { get }

    static func invoke(
        with dict: Entita.Dict,
        requestInfo: LGNCore.RequestInfo
    ) -> Future<(response: Entity, meta: Meta)>
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

    typealias FutureClosureWithMeta = (Request, LGNCore.RequestInfo) -> Future<(response: Response, meta: Meta)>
    typealias FutureClosure = (Request, LGNCore.RequestInfo) -> Future<Response>
    typealias NonFutureClosureWithMeta = (Request, LGNCore.RequestInfo) throws -> (response: Response, meta: Meta)
    typealias NonFutureClosure = (Request, LGNCore.RequestInfo) throws -> Response

    static func guarantee(_ guaranteeClosure: @escaping Self.FutureClosure)
    static func guarantee(_ guaranteeClosure: @escaping Self.FutureClosureWithMeta)
    static func guarantee(_ guaranteeClosure: @escaping Self.NonFutureClosure)
    static func guarantee(_ guaranteeClosure: @escaping Self.NonFutureClosureWithMeta)

}

public enum ContractVisibility {
    case Public, Private
}

public extension Contract {
    typealias InitValidationErrors = [String: [ValidatorError]]

    static func guarantee(_ guaranteeClosure: @escaping Self.FutureClosureWithMeta) {
        self.guaranteeClosure = self.normalize(guaranteeClosure: guaranteeClosure)
    }

    static func guarantee(_ guaranteeClosure: @escaping Self.FutureClosure) {
        self.guaranteeClosure = self.normalize(guaranteeClosure: guaranteeClosure)
    }

    static func guarantee(_ guaranteeClosure: @escaping Self.NonFutureClosure) {
        self.guaranteeClosure = self.normalize(guaranteeClosure: guaranteeClosure)
    }

    static func guarantee(_ guaranteeClosure: @escaping Self.NonFutureClosureWithMeta) {
        self.guaranteeClosure = self.normalize(guaranteeClosure: guaranteeClosure)
    }

    static func normalize(guaranteeClosure: @escaping Self.FutureClosureWithMeta) -> Self.Closure {
        return { normalizedRequest, requestInfo in
            return guaranteeClosure(normalizedRequest as! Request, requestInfo)
                .map { (response: $0.response as Entity, meta: $0.meta) }
        }
    }

    static func normalize(guaranteeClosure: @escaping Self.FutureClosure) -> Self.Closure {
        return { normalizedRequest, requestInfo in
            return guaranteeClosure(normalizedRequest as! Request, requestInfo)
                .map { (response: $0 as Entity, meta: [:]) }
        }
    }

    static func normalize(guaranteeClosure: @escaping Self.NonFutureClosureWithMeta) -> Self.Closure {
        return self.normalize(
            guaranteeClosure: { (request, requestInfo) -> Future<(response: Response, meta: Meta)> in
                let promise: Promise<(response: Response, meta: Meta)> = requestInfo.eventLoop.makePromise()

                do {
                    promise.succeed(try guaranteeClosure(request, requestInfo))
                }
                catch {
                    promise.fail(error)
                }

                return promise.futureResult
            }
        )
    }

    static func normalize(guaranteeClosure: @escaping Self.NonFutureClosure) -> Self.Closure {
        return self.normalize(guaranteeClosure: { (request, requestInfo) -> (response: Response, meta: Meta) in
            return try (response: guaranteeClosure(request, requestInfo), meta: [:])
        })
    }

    /// Not to be used directly
    static func invoke(
        with dict: Entita.Dict,
        requestInfo: LGNCore.RequestInfo
    ) -> Future<(response: Entity, meta: Meta)> {
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
            .map { (response: $0.response as Entity, meta: $0.meta) }
    }
}

public enum Contracts {}
