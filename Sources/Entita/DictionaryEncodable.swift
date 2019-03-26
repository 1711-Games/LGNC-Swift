public extension DictionaryEncodable {
    func encode<T: ScalarValue>(_ input: T) throws -> Any {
        return input
    }

    func encode<T: ScalarValue>(_ input: T?) throws -> Any {
        return input as Any
    }

    func encode<T: ScalarValue>(_ input: [T]) throws -> [Any] {
        return input
    }

    func encode<T: ScalarValue>(_ input: [String: T]) throws -> Entita.Dict {
        return input
    }

    func encode(_ input: DictionaryEncodable) throws -> Entita.Dict {
        return try input.getDictionary()
    }

    // hacky
    func encode(_ input: DictionaryEncodable?) throws -> Any {
        return try input?.getDictionary() as Any
    }

    func encode(_ input: Entita.Dict?) throws -> Any {
        return input as Any
    }

    func encode<T: DictionaryEncodable>(_ input: [T]) throws -> [Entita.Dict] {
        return try input.map(self.encode)
    }

    func encode<T: DictionaryEncodable>(_ input: [String: T]) throws -> Entita.Dict {
        return try Dictionary(uniqueKeysWithValues: input.map { try ($0, self.encode($1)) })
    }

    func encode<T: DictionaryEncodable>(_ input: [String: [T]]) throws -> Entita.Dict {
        return try Dictionary(uniqueKeysWithValues: input.map { try ($0, self.encode($1)) })
    }

    func encode<T: RawRepresentable>(_ input: T) throws -> T.RawValue {
        return input.rawValue
    }
}
