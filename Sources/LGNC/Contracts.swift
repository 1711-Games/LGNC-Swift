import Entita
import LGNCore
import LGNS
import NIO

public typealias Meta = LGNC.Entity.Meta
public typealias CanonicalContractResponse = (response: Entity, meta: Meta)

/// A type erased contract
public protocol AnyContract {
    /// Canonical form of contract body (guarantee) type
    typealias CanonicalGuaranteeBody = (Entity) async throws -> CanonicalContractResponse

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
    static var guaranteeBody: Optional<Self.CanonicalGuaranteeBody> { get set }

    /// A computed property returning `true` if contract is guaranteed
    static var isGuaranteed: Bool { get }

    /// An internal method for invoking contract with given raw dict (context is available via `LGNCore.Context.current`), not to be used directly
    static func invoke(with dict: Entita.Dict) async throws -> CanonicalContractResponse
}

public extension AnyContract {
    static var isWebSocketTransportAvailable: Bool {
        self.transports.contains(.WebSocket)
    }

    static var isWebSocketOnly: Bool {
        self.transports == [.WebSocket]
    }

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
        self.guaranteeBody != nil
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

    /// Contract body (guarantee) type in which contract returns a tuple of Response and meta
    typealias GuaranteeBodyWithMeta = (Request) async throws -> (response: Response, meta: Meta)

    /// Contract body (guarantee) type in which contract returns only Response
    typealias GuaranteeBody = (Request) async throws -> Response

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody)

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBodyWithMeta)

    /// Executes current contract on remote node at given address with given request
    static func executeReturningMeta(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context?
    ) async throws -> (response: Self.Response, meta: LGNC.Entity.Meta)

    /// Executes current contract on remote node at given address with given request
    static func execute(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context?
    ) async throws -> Self.Response

    /// Used for returning response with a list of HTTP headers
    static func withHeaders(
        response: Self.Response,
        meta: LGNC.Entity.Meta,
        headers: [(String, String)]
    ) -> (response: Self.Response, meta: LGNC.Entity.Meta)
}

public enum ContractVisibility {
    case Public, Private
}

public extension Contract {
    typealias InitValidationErrors = [String: [ValidatorError]]

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody) {
        self.guaranteeBody = { (request: Entity) async throws -> (response: Entity, meta: Meta) in
            (response: try await guaranteeBody(request as! Request) as Entity, meta: [:])
        }
    }

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBodyWithMeta) {
        self.guaranteeBody = { (request: Entity) async throws -> (response: Entity, meta: Meta) in
            let result = try await guaranteeBody(request as! Request)
            return (response: result.response as Entity, meta: result.meta)
        }
    }

    static func invoke(with dict: Entita.Dict) async throws -> CanonicalContractResponse {
        guard let guaranteeBody = self.guaranteeBody else {
            throw LGNC.E.ControllerError(
                "No guarantee closure for contract '\(self.URI)'"
            )
        }

        let (response, _meta) = try await guaranteeBody(try await Request.initWithValidation(from: dict) as Entity)
        var meta = _meta

        if LGNCore.Context.current.transport == .HTTP && Response.hasCookieFields {
            for (name, cookie) in Mirror(reflecting: response)
                .children
                .compactMap({ (mirror: Mirror.Child) -> (String, LGNC.Entity.Cookie)? in
                    guard let name = mirror.label, let value = mirror.value as? LGNC.Entity.Cookie else {
                        return nil
                    }
                    return (name, value)
                })
            {
                var _cookie: LGNC.Entity.Cookie = cookie
                if cookie.name.isEmpty {
                    _cookie.name = name
                }
                try meta.appending(cookie: _cookie)
            }
        }

        return (response: response, meta: meta)
    }

    static func executeReturningMeta(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context? = nil
    ) async throws -> (response: Self.Response, meta: LGNC.Entity.Meta) {
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

        func resultLog(_ maybeError: Error? = nil) {
            let resultString: String
            if let error = maybeError {
                resultString = "a failure (\(error))"
            } else {
                resultString = "successful"
            }
            context.logger.info(
                "Remote contract 'lgns://\(address)/\(URI)' execution was \(resultString) and took \(profiler.end().rounded(toPlaces: 4))s"
            )
        }

        let payload: Bytes
        do {
            payload = try request.getDictionary().pack(to: Self.preferredContentType)
        } catch {
            throw LGNC.Client.E.PackError("Could not pack request: \(error)")
        }

        do {
            let result = try await LGNC.Entity.Result.initFromResponse(
                from: try await client
                    .send(
                        contract: Self.self,
                        payload: payload,
                        at: address,
                        context: context)
                    .unpack(from: Self.preferredContentType),
                type: Self.Response.self
            )
            guard result.success == true else {
                throw LGNC.E.MultipleError(result.errors)
            }
            guard let resultEntity = result.result else {
                throw LGNC.E.UnpackError("Empty result")
            }
            resultLog()
            return (
                response: resultEntity as! Self.Response,
                meta: result.meta
            )
        } catch let error as NIOConnectionError {
            context.logger.error(
                """
                Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                @ \(address): \(error)
                """
            )
            resultLog(LGNC.ContractError.RemoteContractExecutionFailed)
            throw LGNC.ContractError.RemoteContractExecutionFailed
        } catch {
            resultLog(error)
            throw error
        }
    }

    static func execute(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context? = nil
    ) async throws -> Self.Response {
        let (response, _) = try await self.executeReturningMeta(
            at: address,
            with: request,
            using: client,
            context: maybeContext
        )
        return response
    }

    static func withHeaders(
        response: Self.Response,
        meta _meta: LGNC.Entity.Meta = [:],
        headers: [(String, String)]
    ) -> (response: Self.Response, meta: LGNC.Entity.Meta) {
        var meta = _meta

        headers.forEach { k, v in
            meta[LGNC.HTTP.HEADER_PREFIX + k] = v
        }

        return (response: response, meta: meta)
    }
}

public enum Contracts {}
