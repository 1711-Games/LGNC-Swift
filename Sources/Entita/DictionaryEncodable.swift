public extension DictionaryEncodable {
    public func encode<T: ScalarValue>(_ input: T) throws -> Any {
        return input
    }

    public func encode<T: ScalarValue>(_ input: T?) throws -> Any {
        return input as Any
    }

    public func encode<T: ScalarValue>(_ input: [T]) throws -> [Any] {
        return input
    }

    public func encode<T: ScalarValue>(_ input: [String: T]) throws -> Entita.Dict {
        return input
    }

    public func encode(_ input: DictionaryEncodable) throws -> Entita.Dict {
        return try input.getDictionary()
    }

    // hacky
    public func encode(_ input: DictionaryEncodable?) throws -> Any {
        return try input?.getDictionary() as Any
    }

    public func encode(_ input: Entita.Dict?) throws -> Any {
        return input as Any
    }

    public func encode<T: DictionaryEncodable>(_ input: [T]) throws -> [Entita.Dict] {
        return try input.map(self.encode)
    }

    public func encode<T: DictionaryEncodable>(_ input: [String: T]) throws -> Entita.Dict {
        return try Dictionary(uniqueKeysWithValues: input.map { try ($0, self.encode($1)) })
    }

    public func encode<T: DictionaryEncodable>(_ input: [String: [T]]) throws -> Entita.Dict {
        return try Dictionary(uniqueKeysWithValues: input.map { try ($0, self.encode($1)) })
    }

    public func encode<T: RawRepresentable>(_ input: T) throws -> T.RawValue {
        return input.rawValue
    }
}
