import Foundation

public extension DictionaryExtractable {
    static var keyDictionary: [String: String] {
        return [:]
    }

    /// Formats a key name for error
    private static func formatFieldKey(_ longName: String, _ shortName: String) -> String {
        return "\(longName):\(shortName)"
    }

    /// Checks whether given key is present in dictionary
    fileprivate static func _has(_ name: String, in dictionary: Entita.Dict) -> Bool {
        let flattened = self.extract(param: name, from: dictionary).value.flattened
        return flattened != nil && !(flattened is NSNull)
    }

    /// Returns a key for given name
    func getDictionaryKey(_ name: String) -> String {
        return Self.getDictionaryKey(name)
    }

    /// Returns a key for given name
    static func getDictionaryKey(_ name: String) -> String {
        if Entita.KEY_DICTIONARIES_ENABLED == false {
            return name
        }
        return self.keyDictionary[name] ?? name
    }

    /// Extracts a type-erased value from dictionary
    static func extract(param name: String, from dictionary: Entita.Dict) -> (key: String, value: Any?) {
        let key = Self.getDictionaryKey(name)
        return (key: key, value: dictionary[key] ?? nil)
    }

    /// Returns entity self name
    static func getSelfName() -> String {
        return String(reflecting: self).components(separatedBy: ".")[1...].joined(separator: ".")
    }

    /// Extracts an arbitrary value from dictionary
    static func extract<T>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> T {
        let resultTuple: (key: String, value: Any?) = self.extract(
            param: name,
            from: dictionary
        )
        guard let result = resultTuple.value as? T else {
            throw Entita.E.ExtractError(formatFieldKey(name, resultTuple.key), resultTuple.value)
        }
        return result
    }

    static func extractArbitrary<T>(param name: String, from dictionary: Entita.Dict) throws -> T {
        try self.extract(param: name, from: dictionary)
    }

    /// Exracts a decodable value from dictionary
    static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> T {
        let key = self.getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: Any] else {
            // print("\(#line)")
            throw Entita.E.ExtractError(formatFieldKey(name, key), nil)
        }
        return try T(from: rawDict)
    }

    /// Exracts an optional decodable value from dictionary
    static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict,
        isOptional: Bool = false
    ) throws -> T? {
        let key = self.getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: Any] else {
            if isOptional {
                return nil
            }
            throw Entita.E.ExtractError(formatFieldKey(name, key), nil)
        }
        return try T(from: rawDict)
    }

    /// Exracts an optional value from dictionary
    static func extract<T>(
        param name: String,
        from dictionary: Entita.Dict,
        isOptional: Bool
    ) throws -> T? {
        if isOptional && !self._has(name, in: dictionary) {
            return nil
        }
        let resultTuple: (key: String, value: Any?) = self.extract(param: name, from: dictionary)
        guard let result = resultTuple.value as? T else {
            throw Entita.E.ExtractError(formatFieldKey(name, resultTuple.key), resultTuple.value)
        }
        return result
    }

    /// Exracts a raw representable value (enum) from dictionary
    static func extract<T: RawRepresentable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> T {
        let resultTuple: (key: String, value: Any?) = extract(param: name, from: dictionary)
        guard let resultValue = resultTuple.value as? T.RawValue else {
            // print("\(#line)")
            throw Entita.E.ExtractError(formatFieldKey(name, resultTuple.key), resultTuple.value)
        }
        guard let result = T(rawValue: resultValue) else {
            // print("\(#line)")
            throw Entita.E.ExtractError(formatFieldKey(name, resultTuple.key), resultValue)
        }
        return result
    }

    /// Exracts an array of decodable values from dictionary
    static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [T] {
        let key = getDictionaryKey(name)
        guard let rawList = dictionary[key] as? [Entita.Dict] else {
            throw Entita.E.ExtractError(formatFieldKey(name, key), nil)
        }
        return try rawList.map { try T(from: $0) }
    }

    /// Exracts a map of decodable values from dictionary
    static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [String: T] {
        let key = getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: Entita.Dict] else {
            throw Entita.E.ExtractError(formatFieldKey(name, key), nil)
        }
        return try Dictionary(uniqueKeysWithValues: rawDict.map { key, rawDict in try (key, T(from: rawDict)) })
    }

    /// Exracts a map of arrays of decodable values from dictionary
    static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [String: [T]] {
        let key = getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: [Entita.Dict]] else {
            throw Entita.E.ExtractError(formatFieldKey(name, key), nil)
        }
        return try Dictionary(uniqueKeysWithValues: rawDict.map { key, rawDict in try (key, rawDict.map { try T(from: $0) }) })
    }

    /// Exracts double float value from dictionary
    static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> Double {
        return (try self.extract(param: name, from: dictionary) as NSNumber).doubleValue
    }

    /// Exracts integer value from dictionary
    static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> Int {
        return (try self.extract(param: name, from: dictionary) as NSNumber).intValue
    }

    /// Exracts optional integer value from dictionary
    static func extract(
        param name: String,
        from dictionary: Entita.Dict,
        isOptional: Bool = false
    ) throws -> Int? {
        if isOptional && !self._has(name, in: dictionary) {
            return nil
        }
        return (try self.extract(param: name, from: dictionary)) as Int
    }

    /// Exracts an array of integer values from dictionary
    static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [Int] {
        return (try extract(param: name, from: dictionary) as [NSNumber]).map { $0.intValue }
    }

    /// Exracts a map of integer values from dictionary
    static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [String: Int] {
        return Dictionary(
            uniqueKeysWithValues:
            (try self.extract(param: name, from: dictionary) as [String: NSNumber])
                .map { key, value in (key, value.intValue) }
        )
    }

    /// Extracts an identifier from dictionary
    static func extractID(
        from dictionary: Entita.Dict,
        as name: String = Entita.DEFAULT_ID_LABEL,
        subkey: String? = nil
    ) throws -> Identifier {
        let dataset: Entita.Dict
        if let subkey = subkey {
            dataset = try self.extract(param: subkey, from: dictionary)
        } else {
            dataset = dictionary
        }
        return Identifier(try self.extract(param: name, from: dataset) as String)
    }

    /// Extract an arbitrary value from dictionary
    func extract<T>(param name: String, from dictionary: Entita.Dict) throws -> T {
        return try Self.extract(param: name, from: dictionary)
    }

    /// Extracts an identifier from dictionary
    func extractID(
        from dictionary: Entita.Dict,
        as _: String = Entita.DEFAULT_ID_LABEL,
        subkey: String? = nil
    ) throws -> Identifier {
        return try Self.extractID(from: dictionary, subkey: subkey)
    }
}
