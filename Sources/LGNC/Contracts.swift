import Entita
import LGNCore
import LGNS
import NIO

public typealias Meta = LGNC.Entity.Meta

/// A type erased contract
public protocol AnyContract {
    /// Canonical form of contract body (guarantee) type
    typealias Closure = (Entity, LGNCore.Context) -> EventLoopFuture<(response: Entity, meta: Meta)>

    /// URI of contract, must be unique for service
    static var URI: String { get }

    /// Indicates whether contract can be invoked with HTTP GET method (and respective GET params)
    static var isGETSafe: Bool { get }

    /// Allowed transports for contract, must not be empty
    static var transports: [LGNCore.Transport] { get }

    /// Preferred transport to be used by client if no transport is provided, see default implementation
    static var preferredTransport: LGNCore.Transport { get }

    /// Allowed content types of request for contract, must not be empty
    static var contentTypes: [LGNCore.ContentType] { get }

    /// Preferred content type of request for contract, see default implementation
    static var preferredContentType: LGNCore.ContentType { get }

    /// Contract guarantee closure body
    static var guaranteeClosure: Optional<Self.Closure> { get set }

    /// A computed property returning `true` if contract is guaranteed
    static var isGuaranteed: Bool { get }

    /// An internal method for invoking contract with given raw dict and context, not to be used directly
    static func invoke(
        with dict: Entita.Dict,
        context: LGNCore.Context
    ) -> EventLoopFuture<(response: Entity, meta: Meta)>
}

public extension AnyContract {
    static var isGETSafe: Bool { false }

    static var preferredTransport: LGNCore.Transport {
        guard self.transports.count > 0 else {
            LGNC.logger.error("Empty transports in contract \(Self.self), returning .LGNS")
            return .LGNS
        }

        if self.transports.contains(.LGNS) {
            return .LGNS
        }

        return .HTTP
    }

    static var preferredContentType: LGNCore.ContentType {
        guard self.transports.count > 0 else {
            LGNC.logger.error("Empty content-types in contract \(Self.self), returning .JSON")
            return .JSON
        }

        if Self.preferredTransport == .LGNS && self.contentTypes.contains(.MsgPack) {
            return .MsgPack
        }

        return .JSON
    }

    static var isGuaranteed: Bool {
        self.guaranteeClosure != nil
    }
}

/// A type erased yet more concrete contract than `AnyContract`, as it defines `Request`, `Response` and other dynamic stuff
public protocol Contract: AnyContract {
    /// Request type of contract
    associatedtype Request: ContractEntity

    /// Response type of contract
    associatedtype Response: ContractEntity

    /// Service to which current contract belongs to
    associatedtype ParentService: Service

    /// Contract body (guarantee) type in which contract returns a future with a tuple of Response and meta
    typealias FutureClosureWithMeta =    (Request, LGNCore.Context) -> EventLoopFuture<(response: Response, meta: Meta)>

    /// Contract body (guarantee) type in which contract returns a future with only Response
    typealias FutureClosure =            (Request, LGNCore.Context) -> EventLoopFuture<           Response>

    /// Contract body (guarantee) type in which contract returns a tuple of Response and meta
    typealias NonFutureClosureWithMeta = (Request, LGNCore.Context) throws ->          (response: Response, meta: Meta)

    /// Contract body (guarantee) type in which contract returns only Response
    typealias NonFutureClosure =         (Request, LGNCore.Context) throws ->                     Response

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeClosure: @escaping Self.FutureClosure)

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeClosure: @escaping Self.FutureClosureWithMeta)

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeClosure: @escaping Self.NonFutureClosure)

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeClosure: @escaping Self.NonFutureClosureWithMeta)

    /// Executes current contract on remote node at given address with given request
    static func executeReturningMeta(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context?
    ) -> EventLoopFuture<(response: Self.Response, meta: LGNC.Entity.Meta)>

    /// Executes current contract on remote node at given address with given request
    static func execute(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context?
    ) -> EventLoopFuture<Self.Response>
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

    /// Normalizes given non-canonical contract body (guarantee) into canonical form
    static func normalize(guaranteeClosure: @escaping Self.FutureClosureWithMeta) -> Self.Closure {
        return { normalizedRequest, context in
            return guaranteeClosure(normalizedRequest as! Request, context)
                .map { (response: $0.response as Entity, meta: $0.meta) }
        }
    }

    /// Normalizes given non-canonical contract body (guarantee) into canonical form
    static func normalize(guaranteeClosure: @escaping Self.FutureClosure) -> Self.Closure {
        return { normalizedRequest, context in
            return guaranteeClosure(normalizedRequest as! Request, context)
                .map { (response: $0 as Entity, meta: [:]) }
        }
    }

    /// Normalizes given non-canonical contract body (guarantee) into canonical form
    static func normalize(guaranteeClosure: @escaping Self.NonFutureClosureWithMeta) -> Self.Closure {
        return self.normalize(
            guaranteeClosure: { (request, context) -> EventLoopFuture<(response: Response, meta: Meta)> in
                let promise: EventLoopPromise<(response: Response, meta: Meta)> = context.eventLoop.makePromise()

                do {
                    promise.succeed(try guaranteeClosure(request, context))
                }
                catch {
                    promise.fail(error)
                }

                return promise.futureResult
            }
        )
    }

    /// Normalizes given non-canonical contract body (guarantee) into canonical form
    static func normalize(guaranteeClosure: @escaping Self.NonFutureClosure) -> Self.Closure {
        return self.normalize { (request, context) -> (response: Response, meta: Meta) in
            return try (response: guaranteeClosure(request, context), meta: [:])
        }
    }

    static func invoke(
        with dict: Entita.Dict,
        context: LGNCore.Context
    ) -> EventLoopFuture<(response: Entity, meta: Meta)> {
        guard let guaranteeClosure = self.guaranteeClosure else {
            return context.eventLoop.makeFailedFuture(
                LGNC.E.ControllerError(
                    "No guarantee closure for contract '\(self.URI)'"
                )
            )
        }

        return Request
            .initWithValidation(from: dict, context: context)
            .flatMap { guaranteeClosure($0 as Entity, context) }
            .flatMapThrowing { response, meta in
                var meta = meta

                if context.transport == .HTTP && Response.hasCookieFields {
                    for cookie in Mirror(reflecting: response)
                        .children
                        .compactMap({ $0.value as? LGNC.Entity.Cookie })
                    {
                        try meta.appending(cookie: cookie)
                    }
                }

                return (response: response, meta: meta)
            }
    }

    static func executeReturningMeta(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context? = nil
    ) -> EventLoopFuture<(response: Self.Response, meta: LGNC.Entity.Meta)> {
        let profiler = LGNCore.Profiler.begin()
        let eventLoop = maybeContext?.eventLoop ?? client.eventLoopGroup.next()
        let transport = Self.preferredTransport

        let context = LGNC.Client.getRequestContext(
            from: maybeContext,
            transport: transport,
            eventLoop: eventLoop
        )

        context.logger.debug(
            "Executing remote contract \(transport.rawValue.lowercased())://\(address)/\(Self.URI)",
            metadata: [
                "requestID": "\(context.uuid.string)",
            ]
        )

        let payload: Bytes
        do {
            payload = try request.getDictionary().pack(to: Self.preferredContentType)
        } catch {
            return eventLoop.makeFailedFuture(LGNC.Client.E.PackError("Could not pack request: \(error)"))
        }

        let result: EventLoopFuture<(response: Self.Response, meta: LGNC.Entity.Meta)> = client
            .send(
                contract: Self.self,
                payload: payload,
                at: address,
                context: context
            )
            .flatMapThrowing { responseBytes, responseContext in
                (dict: try responseBytes.unpack(from: Self.preferredContentType), responseContext: responseContext)
            }
            .flatMap { (dict: Entita.Dict, responseContext: LGNCore.Context) -> EventLoopFuture<LGNC.Entity.Result> in
                LGNC.Entity.Result.initFromResponse(
                    from: dict,
                    context: responseContext,
                    type: Self.Response.self
                )
            }
            .flatMapThrowing { (result: LGNC.Entity.Result) in
                guard result.success == true else {
                    throw LGNC.E.MultipleError(result.errors)
                }
                guard let resultEntity = result.result else {
                    throw LGNC.E.UnpackError("Empty result")
                }
                return (
                    response: resultEntity as! Self.Response,
                    meta: result.meta
                )
            }
            .flatMapErrorThrowing {
                if let error = $0 as? NIOConnectionError {
                    context.logger.error("""
                        Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                        @ \(address): \(error)
                    """)
                    throw LGNC.ContractError.RemoteContractExecutionFailed
                }
                throw $0
            }

        result.whenComplete { result in
            let resultString: String
            switch result {
            case .success(_):
                resultString = "successful"
            case .failure(let error):
                resultString = "a failure (\(error))"
            }
            context.logger.info(
                "Remote contract 'lgns://\(address)/\(URI)' execution was \(resultString) and took \(profiler.end().rounded(toPlaces: 4))s"
            )
        }

        return result
    }

    static func execute(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context? = nil
    ) -> EventLoopFuture<Self.Response> {
        self
            .executeReturningMeta(at: address, with: request, using: client, context: maybeContext)
            .map { response, _ in response }
    }
}

public enum Contracts {}
