import LGNCore

public protocol HTMLContract: Contract {
    typealias GuaranteeBodyHTML = (Swift.Result<Request, Error>) async throws -> (response: String, headers: [String: String])

    static func guaranteeHTML(_ guaranteeBody: @escaping Self.GuaranteeBodyHTML)
}

public extension HTMLContract {
    static func guaranteeHTML(_ guaranteeBody: @escaping Self.GuaranteeBodyHTML) {
        self.guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            let html: String
            let headers: [String: String]

            do {
                let (_html, _headers) = try await guaranteeBody(request.map { $0 as! Request })
                html = _html
                headers = _headers
            } catch let error as Redirect {
                html = ""
                headers = ["Location": error.location]
            }

            var meta = Meta()
            headers.forEach { k, v in
                meta[LGNC.HTTP.HEADER_PREFIX + k] = v
            }

            return ContractExecutionResult(
                result: .Binary(LGNC.Entity.File(contentType: .textHTML, body: Bytes(html.utf8)), nil),
                meta: meta
            )
        }
    }
}
