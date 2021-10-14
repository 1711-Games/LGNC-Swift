public protocol FileContract: Contract {
    typealias GuaranteeBodyCanonical = (Swift.Result<Request, Error>) async throws -> (response: LGNC.Entity.File, disposition: HTTP.ContentDisposition?, meta: Meta)

    typealias GuaranteeBody = (Swift.Result<Request, Error>) async throws -> LGNC.Entity.File

    static func guaranteeCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyCanonical)

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody)
}

public extension FileContract {
    static func guaranteeCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyCanonical) {
        self.guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            let (file, disposition, meta) = try await guaranteeBody(request.map { $0 as! Request })
            return ContractExecutionResult(result: .Binary(file, disposition), meta: meta)
        }
    }

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody) {
        self.guaranteeCanonical { request in
            (
                response: try await guaranteeBody(request),
                disposition: .Attachment,
                meta: [:]
            )
        }
    }
}
