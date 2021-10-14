import LGNCore
import NIO

public protocol HTMLResponse {
    var htmlResponse: HTMLContract.CanonicalResponse { get async throws }
}

public protocol HTMLContract: Contract {
    typealias CanonicalResponse = (html: String, headers: [String: String])
    typealias GuaranteeBody = (Swift.Result<Request, Error>) async throws -> HTMLResponse

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody)
}

public extension HTMLContract {
    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody) {
        self.guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            let html: String
            let headers: [String: String]

            do {
                let (_html, _headers) = try await guaranteeBody(request.map { $0 as! Request }).htmlResponse
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

    static func withHeaders(html: String, headers: [String: String]) -> HTMLResponse {
        HTMLWithHeaders(html: html, headers: headers)
    }
}

extension String: HTMLResponse {
    public var htmlResponse: HTMLContract.CanonicalResponse {
        (self, [:])
    }
}

extension ByteBuffer: HTMLResponse {
    public var htmlResponse: (html: String, headers: [String: String]) {
        (self.getString(at: 0, length: self.readableBytes) ?? "", [:])
    }
}

extension EventLoopFuture: HTMLResponse where Value == ByteBuffer {
    public var htmlResponse: (html: String, headers: [String: String]) {
        get async throws {
            try await self.value.htmlResponse
        }
    }
}

public struct HTMLWithHeaders: HTMLResponse {
    let html: String
    let headers: [String: String]

    public var htmlResponse: HTMLContract.CanonicalResponse {
        (self.html, self.headers)
    }

    public init(html: String, headers: [String: String]) {
        self.html = html
        self.headers = headers
    }
}
