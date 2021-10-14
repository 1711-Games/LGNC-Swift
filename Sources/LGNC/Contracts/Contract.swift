import LGNCore
import Entita

/// A type erased yet more concrete contract than `AnyContract`, as it defines `Request`, `Response` and other dynamic stuff
public protocol Contract: AnyContract {
    /// Request type of contract
    associatedtype Request: ContractEntity

    /// Response type of contract
    associatedtype Response: ContractEntity

    /// Service to which current contract belongs to
    associatedtype ParentService: Service

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
    static func _invoke(with dict: Entita.Dict) async throws -> ContractExecutionResult {
        guard let guaranteeBody = self.guaranteeBody else {
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
}
