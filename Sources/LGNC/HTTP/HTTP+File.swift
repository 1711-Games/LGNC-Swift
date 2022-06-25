import LGNCore

public extension LGNC.Entity {
    struct File {
        public let filename: String?
        public let contentType: LGNCore.ContentType
        public let body: Bytes

        public init(filename: String? = nil, contentType: LGNCore.ContentType, body: Bytes) {
            self.filename = filename
            self.contentType = contentType
            self.body = body
        }
    }
}
