import LGNCore
import LGNLog
import Entita
import NIO

public typealias Meta = LGNC.Entity.Meta
public typealias CanonicalCompositeRequest = Swift.Result<Entity, Error>
public typealias CanonicalStructuredContractResponse = (response: Entity, meta: Meta)

public protocol Contract {
    /// Request type of contract
    associatedtype Request: ContractEntity

    /// Response type of contract
    associatedtype Response: ContractEntity

    /// Service to which current contract belongs to
    associatedtype ParentService: Service

    /// Canonical form of contract body (guarantee) type
    typealias CanonicalGuaranteeBody = (CanonicalCompositeRequest) async throws -> ContractExecutionResult

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

    /// Indicates whether this contract returns response in structured form (i.e. an API contract in JSON/MsgPack format)
    static var isResponseStructured: Bool { get }

    /// A computed property returning `true` if contract is guaranteed
    static var isGuaranteed: Bool { get }

    /// Contract guarantee closure body (must not be set directly)
    static var _guaranteeBody: Optional<Self.CanonicalGuaranteeBody> { get set }

    /// An internal method for invoking contract with given raw dict (context is available via `LGNCore.Context.current`), not to be used directly
    static func _invoke(with dict: Entita.Dict) async throws -> ContractExecutionResult

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
}

public extension Contract {
    static var isResponseStructured: Bool {
        true
    }

    static var isWebSocketTransportAvailable: Bool {
        self.transports.contains(.WebSocket)
    }

    static var isWebSocketOnly: Bool {
        self.transports == [.WebSocket]
    }

    static var isGETSafe: Bool { false }

    static var preferredTransport: LGNCore.Transport {
        guard self.transports.count > 0 else {
            Logger.current.error("Empty transports in contract \(Self.self), returning .LGNS")
            return .LGNS
        }

        if self.transports.contains(.LGNS) {
            return .LGNS
        }

        return .HTTP
    }

    static var preferredContentType: LGNCore.ContentType {
        guard self.transports.count > 0 else {
            Logger.current.error("Empty content-types in contract \(Self.self), returning .JSON")
            return .JSON
        }

        if Self.preferredTransport == .LGNS && self.contentTypes.contains(.MsgPack) {
            return .MsgPack
        }

        return .JSON
    }

    static var isGuaranteed: Bool {
        self._guaranteeBody != nil
    }

    static func _invoke(with dict: Entita.Dict) async throws -> ContractExecutionResult {
        guard let guaranteeBody = self._guaranteeBody else {
            throw LGNC.E.ControllerError("No guarantee closure for contract '\(self.URI)'")
        }

        let request: CanonicalCompositeRequest
        do {
            request = try await .success(Request.initWithValidation(from: dict) as Entity)
        } catch {
            if self.isResponseStructured {
                throw error
            }
            request = .failure(error)
        }

        var response = try await guaranteeBody(request)

        if LGNCore.Context.current.transport == .HTTP && Response.hasCookieFields,
           case .Structured(let responseEntity) = response.result
        {
            for (name, cookie) in Mirror(reflecting: responseEntity)
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
                try response.meta.appending(cookie: _cookie)
            }
        }

        return response
    }

    static func executeReturningMeta(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        context maybeContext: LGNCore.Context? = nil
    ) async throws -> (response: Self.Response, meta: LGNC.Entity.Meta) {
        let eventLoop = maybeContext?.eventLoop ?? client.eventLoopGroup.next()
        let transport = Self.preferredTransport

        let context = LGNC.Client.getRequestContext(
            from: maybeContext,
            transport: transport,
            eventLoop: eventLoop
        )

        context.profiler.mark("from channel to execution")

        func resultLog(_ maybeError: Error? = nil) {
            let resultString: String
            if let error = maybeError {
                resultString = "a failure (\(error))"
            } else {
                resultString = "successful"
            }
            let milestone = context.profiler.mark("remote contract executed")
            Logger.current.info(
                "Remote contract '\(address)/\(URI)' execution was \(resultString) and took \(milestone.elapsed.rounded(toPlaces: 4))s"
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
                        context: context
                    )
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
            Logger.current.error(
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
}
