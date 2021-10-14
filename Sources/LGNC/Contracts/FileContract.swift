public protocol FileContract: Contract {
    typealias GuaranteeBodyFileCanonical = (Swift.Result<Request, Error>) async throws -> (response: LGNC.Entity.File, disposition: HTTP.ContentDisposition?, meta: Meta)

    typealias GuaranteeBodyFile = (Swift.Result<Request, Error>) async throws -> LGNC.Entity.File

    static func guaranteeFileCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyFileCanonical)

    static func guaranteeFile(_ guaranteeBody: @escaping Self.GuaranteeBodyFile)
}

public extension FileContract {
    static func guaranteeFileCanonical(_ guaranteeBody: @escaping Self.GuaranteeBodyFileCanonical) {
        self.guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            let (file, disposition, meta) = try await guaranteeBody(request.map { $0 as! Request })
            return ContractExecutionResult(result: .Binary(file, disposition), meta: meta)
        }
    }

    static func guaranteeFile(_ guaranteeBody: @escaping Self.GuaranteeBodyFile) {
        self.guaranteeFileCanonical { request in
            (
                response: try await guaranteeBody(request),
                disposition: .Attachment,
                meta: [:]
            )
        }
    }
}
