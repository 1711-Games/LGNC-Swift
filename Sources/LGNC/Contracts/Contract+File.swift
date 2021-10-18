public struct FileContractResponse {
    public let file: LGNC.Entity.File
    public let disposition: HTTP.ContentDisposition?
    public let meta: Meta

    public init(file: LGNC.Entity.File, disposition: HTTP.ContentDisposition? = nil, meta: Meta = [:]) {
        self.file = file
        self.disposition = disposition
        self.meta = meta
    }
}

public protocol FileContract: Contract {
    typealias GuaranteeBodyCanonical = (Swift.Result<Request, Error>) async throws -> FileContractResponse

    typealias GuaranteeBody = (Swift.Result<Request, Error>) async throws -> LGNC.Entity.File

    static func guaranteeCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyCanonical)

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody)
}

public extension FileContract {
    static func guaranteeCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyCanonical) {
        self._guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            let response = try await guaranteeBody(request.map { $0 as! Request })
            return ContractExecutionResult(result: .Binary(response.file, response.disposition), meta: response.meta)
        }
    }

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody) {
        self.guaranteeCanonical { request in
            .init(
                file: try await guaranteeBody(request),
                disposition: .Attachment,
                meta: [:]
            )
        }
    }
}
