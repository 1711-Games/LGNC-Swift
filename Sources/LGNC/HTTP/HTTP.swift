import Foundation
import NIOHTTP1
import LGNCore

public enum HTTP {}

public extension LGNC {
    enum HTTP {
        public typealias ResolverResult = (body: Bytes, headers: [(name: String, value: String)])
        public typealias Resolver = (Request) async throws -> ResolverResult

        public static let HEADER_PREFIX = "HEADER__"
        public static let COOKIE_META_KEY_PREFIX = HEADER_PREFIX + "Set-Cookie: "
    }
}

public extension LGNC.HTTP {
    struct Request: Sendable {
        public let URI: String
        public let headers: HTTPHeaders
        public let remoteAddr: String
        public let body: Bytes
        public let uuid: UUID
        public let contentType: LGNCore.ContentType
        public let method: HTTPMethod
        public let meta: LGNC.Entity.Meta
        public let eventLoop: EventLoop
    }
}

public extension HTTP {
    enum ContentDisposition: String {
        case Inline = "inline"
        case Attachment = "attachment"

        func header(forFile file: File) -> (name: String, value: String) {
            (
                name: "Content-Disposition",
                value: "\(self)\(file.filename.map { "; filename=\"\($0)\"" } ?? "")"
            )
        }
    }
}
