import Foundation
import NIOHTTP1
import LGNCore
import NIO

public enum HTTP {}

public extension HTTP {
    static func metaWithHeaders(headers: [String: String], status: HTTPResponseStatus, meta: Meta = [:]) -> Meta {
        var result = meta

        headers.forEach { k, v in
            result[LGNC.HTTP.HEADER_PREFIX + k] = v
        }
        result[LGNC.HTTP.STATUS_PREFIX] = "\(status.code)"

        return result
    }
}

public extension LGNC {
    enum HTTP {
        public typealias ResolverResult = (
            body: Bytes,
            status: HTTPResponseStatus,
            headers: [(name: String, value: String)]
        )
        public typealias Resolver = (Request) async throws -> ResolverResult

        public static let HEADER_PREFIX = "HEADER__"
        public static let STATUS_PREFIX = "STATUS__"
        public static let COOKIE_META_KEY_PREFIX = HEADER_PREFIX + "Set-Cookie: "
    }
}

public extension LGNC.HTTP {
    struct Request: @unchecked Sendable {
        public let URI: String
        public let headers: HTTPHeaders
        public let remoteAddr: String
        public let body: Bytes
        public let requestID: LGNCore.RequestID
        public let contentType: LGNCore.ContentType
        public let method: HTTPMethod
        public let meta: LGNC.Entity.Meta
        public let eventLoop: EventLoop
        public let profiler: LGNCore.Profiler
    }
}

extension LGNC.HTTP.Request {
    var isURLEncoded: Bool {
        self.method == .POST
            && self.headers.first(name: "Content-Type")?.starts(with: "application/x-www-form-urlencoded") == true
    }
}

public extension LGNCore.ContentType {
    static var allowedHTTPTypes: [Self] = [
        .MsgPack,
        .JSON,
    ]
}

public extension HTTP {
    enum ContentDisposition: String {
        case Inline = "inline"
        case Attachment = "attachment"

        func header(forFile file: LGNC.Entity.File) -> (name: String, value: String) {
            (
                name: "Content-Disposition",
                value: "\(self)\(file.filename.map { "; filename=\"\($0)\"" } ?? "")"
            )
        }
    }
}
