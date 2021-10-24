import LGNCore
import LGNLog
import Entita

public protocol StructuredContract: Contract {
    /// Contract body (guarantee) type in which contract returns a tuple of Response and meta
    typealias GuaranteeBodyCanonical = (Request) async throws -> (response: Response, meta: Meta)

    /// Contract body (guarantee) type in which contract returns only Response
    typealias GuaranteeBody = (Request) async throws -> Response

    /// Setter for contract body (guarantee)
    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody)

    /// Setter for contract body (guarantee)
    static func guaranteeCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyCanonical)

    /// Used for returning response with a list of HTTP headers
    static func withHeaders(
        response: Self.Response,
        meta: LGNC.Entity.Meta,
        headers: [(String, String)]
    ) -> (response: Self.Response, meta: LGNC.Entity.Meta)
}

public extension StructuredContract {
    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody) {
        self.guaranteeCanonical { (request: Request) async throws -> (response: Response, meta: Meta) in
            try await (response: guaranteeBody(request), meta: [:])
        }
    }

    static func guaranteeCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyCanonical) {
        self._guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            switch request {
            case .success(let rawRequest):
                let (response, meta) = try await guaranteeBody(rawRequest as! Request)
                return ContractExecutionResult(result: .Structured(response as Entity), meta: meta)
            case .failure(let error):
                Logger.current.critical(
                    "Contract \(Self.self) with structured response got request in error state (this must not happen)",
                    metadata: ["error": "\(error)"]
                )
                throw LGNC.ContractError.InternalError
            }
        }
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
