import Entita

extension LGNC.Entity.File: DictionaryConvertible {
    public init(from dictionary: Entita.Dict) throws {
        try self.init(
            filename: Self.extract(param: "filename", from: dictionary),
            contentType: Self.extract(param: "contentType", from: dictionary),
            body: Self.extract(param: "body", from: dictionary)
        )
    }

    public func getDictionary() throws -> Entita.Dict {
        try [
            "filename": self.encode(self.filename),
            "contentType": self.encode(self.contentType),
            "body": self.encode(self.body),
        ]
    }
}

extension LGNC.Entity.File: ContractEntity {
    public static func initWithValidation(from dictionary: Entita.Dict) async throws -> LGNC.Entity.File {
        try self.init(from: dictionary)
    }
}

public extension DictionaryEncodable {
    /// Encodes input `File`
    func encode(_ input: LGNC.Entity.File) throws -> Any {
        input as Any
    }
}

public extension DictionaryExtractable {
    /// Exracts `File` value from dictionary
//    static func extract(param name: String, from dictionary: Entita.Dict) throws -> File {
//        // fast path
//        if let file: File = try self.extract(param: name, from: dictionary) {
//            return file
//        }
//    }
}
