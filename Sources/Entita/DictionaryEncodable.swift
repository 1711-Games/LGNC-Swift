public extension DictionaryEncodable {
    /// Encodes any input scalar value as `Any`
    func encode<T: ScalarValue>(_ input: T) throws -> Any {
        return input
    }

    /// Encodes any optional input scalar value as `Any`
    func encode<T: ScalarValue>(_ input: T?) throws -> Any {
        return input as Any
    }

    /// Encodes any input array of scalar values as array of `Any`
    func encode<T: ScalarValue>(_ input: [T]) throws -> [Any] {
        return input
    }

    /// Encodes any input map of scalar values as map of `Any`
    func encode<T: ScalarValue>(_ input: [String: T]) throws -> Entita.Dict {
        return input
    }

    /// Encodes input encodable entity as dictionary
    func encode(_ input: DictionaryEncodable) throws -> Entita.Dict {
        return try input.getDictionary()
    }

    /// Encodes input optional encodable entity as `Any`
    ///
    /// This method is kinda hacky, and should be revised in future (TODO)
    func encode(_ input: DictionaryEncodable?) throws -> Any {
        return try input?.getDictionary() as Any
    }

    /// Encodes input optional dictionary as `Any`
    func encode(_ input: Entita.Dict?) throws -> Any {
        return input as Any
    }

    /// Encodes input array of encodables as an array of dictionaries
    func encode<T: DictionaryEncodable>(_ input: [T]) throws -> [Entita.Dict] {
        return try input.map(self.encode)
    }

    /// Encodes input map of encodables as dictionary
    func encode<T: DictionaryEncodable>(_ input: [String: T]) throws -> Entita.Dict {
        return try Dictionary(uniqueKeysWithValues: input.map { try ($0, self.encode($1)) })
    }

    /// Encodes input map of arrays of encodables as dictionary
    func encode<T: DictionaryEncodable>(_ input: [String: [T]]) throws -> Entita.Dict {
        return try Dictionary(uniqueKeysWithValues: input.map { try ($0, self.encode($1)) })
    }

    /// Encodes input rawrepresentable as its raw value
    func encode<T: RawRepresentable>(_ input: T) throws -> T.RawValue {
        return input.rawValue
    }
}
