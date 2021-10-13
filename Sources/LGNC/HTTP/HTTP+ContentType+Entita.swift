import Entita

extension HTTP.ContentType: DictionaryConvertible {
    public init(from dictionary: Entita.Dict) throws {
        try self.init(
            type: Self.extract(param: "type", from: dictionary),
            options: Self.extract(param: "options", from: dictionary) ?? [:]
        )
    }

    public func getDictionary() throws -> Entita.Dict {
        try [
            "type": self.encode(self.type),
            "options": self.encode(self.options),
        ]
    }
}
