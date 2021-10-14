import LGNCore

public extension LGNC.Entity {
    struct File {
        public let filename: String?
        public let contentType: HTTP.ContentType
        public let body: Bytes

        public init(filename: String? = nil, contentType: HTTP.ContentType, body: Bytes) {
            self.filename = filename
            self.contentType = contentType
            self.body = body
        }
    }
}
