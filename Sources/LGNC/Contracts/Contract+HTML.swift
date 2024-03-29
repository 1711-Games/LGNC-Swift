import LGNCore
import NIO
import NIOHTTP1

public protocol HTMLResponse {
    var htmlResponse: HTMLContract.CanonicalResponse { get async throws }
}

public protocol HTMLContract: Contract {
    typealias CanonicalResponse = (html: String, headers: [String: String], status: HTTPResponseStatus, meta: Meta)
    typealias GuaranteeBody = (Swift.Result<Request, Error>) async throws -> HTMLResponse

    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody)
}

public extension HTMLContract {
    static func guarantee(_ guaranteeBody: @escaping Self.GuaranteeBody) {
        self._guaranteeBody = { (request: CanonicalCompositeRequest) async throws -> ContractExecutionResult in
            let html: String
            var headers: [String: String]
            let status: HTTPResponseStatus
            let meta: Meta

            do {
                let (_html, _headers, _status, _meta) = try await guaranteeBody(request.map { $0 as! Request })
                    .htmlResponse
                html = _html
                headers = _headers
                status = _status
                meta = _meta
            } catch let error as Redirect {
                html = ""
                headers = ["Location": error.location]
                status = error.status
                meta = Meta()
            }

            if headers["Content-Type"] == nil {
                headers["Content-Type"] = LGNCore.ContentType(type: "text/html", options: ["charset": "UTF-8"]).header
            }

            return ContractExecutionResult(
                result: .Binary(LGNC.Entity.File(contentType: .TextHTML, body: Bytes(html.utf8)), nil),
                meta: HTTP.metaWithHeaders(headers: headers, status: status, meta: meta)
            )
        }
    }

    static func withHeaders(
        html: String,
        headers: [String: String],
        status: HTTPResponseStatus = .ok,
        meta: Meta = Meta()
    ) -> HTMLResponse {
        HTMLWithHeaders(html: html, headers: headers, status: status, meta: meta)
    }
}

extension String: HTMLResponse {
    public var htmlResponse: HTMLContract.CanonicalResponse {
        (self, [:], .ok, [:])
    }
}

extension ByteBuffer: HTMLResponse {
    public var htmlResponse: HTMLContract.CanonicalResponse {
        (self.getString(at: 0, length: self.readableBytes) ?? "", [:], .ok, [:])
    }
}

extension EventLoopFuture: HTMLResponse where Value == ByteBuffer {
    public var htmlResponse: HTMLContract.CanonicalResponse {
        get async throws {
            try await self.get().htmlResponse
        }
    }
}

public struct HTMLWithHeaders: HTMLResponse {
    let html: String
    let headers: [String: String]
    let status: HTTPResponseStatus
    let meta: Meta

    public var htmlResponse: HTMLContract.CanonicalResponse {
        (self.html, self.headers, .ok, self.meta)
    }

    public init(html: String, headers: [String: String], status: HTTPResponseStatus = .ok, meta: Meta = Meta()) {
        self.html = html
        self.headers = headers
        self.status = status
        self.meta = meta
    }
}
