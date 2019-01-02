import Foundation

public extension DictionaryExtractable {
    public static var keyDictionary: [String: String] {
        return [:]
    }

    private static func formatFieldKey(_ longName: String, _ shortName: String) -> String {
        return "\(longName):\(shortName)"
    }

    public func getDictionaryKey(_ name: String) -> String {
        return Swift.type(of: self).getDictionaryKey(name)
    }

    public static func getDictionaryKey(_ name: String) -> String {
        if Entita.KEY_DICTIONARIES_ENABLED == false {
            return name
        }
        return self.keyDictionary[name] ?? name
    }

    public static func extract(param name: String, from dictionary: Entita.Dict) -> (key: String, value: Any?) {
        let key = self.getDictionaryKey(name)
        return (key: key, value: dictionary[key])
    }

    public static func getSelfName() -> String {
        return String(reflecting: self).components(separatedBy: ".")[1...].joined(separator: ".")
    }

    public static func extract<T>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> T {
        let resultTuple: (key: String, value: Any?) = self.extract(param: name, from: dictionary)
        guard let result = resultTuple.value as? T else {
            throw Entita.E.ExtractError(self.formatFieldKey(name, resultTuple.key), resultTuple.value)
        }
        return result
    }

    public static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict,
        isOptional: Bool = false
    ) throws -> T? {
        let key = self.getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: Any] else {
            if isOptional {
                return nil
            }
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, key), nil)
        }
        return try T(from: rawDict)
    }

    public static func extract<T>(
        param name: String,
        from dictionary: Entita.Dict,
        isOptional: Bool = false
    ) throws -> T? {
        let resultTuple: (key: String, value: Any?) = self.extract(param: name, from: dictionary)
        guard let result = resultTuple.value as? T else {
            // print(T.self)
            // print("\(#line)")
            if isOptional {
                return nil
            }
            throw Entita.E.ExtractError(self.formatFieldKey(name, resultTuple.key), resultTuple.value)
        }
        return result
    }

    public static func extract<T: RawRepresentable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> T {
        let resultTuple: (key: String, value: Any?) = self.extract(param: name, from: dictionary)
        guard let resultValue = resultTuple.value as? T.RawValue else {
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, resultTuple.key), resultTuple.value)
        }
        guard let result = T(rawValue: resultValue) else {
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, resultTuple.key), resultValue)
        }
        return result
    }

    public static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> T {
        let key = self.getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: Any] else {
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, key), nil)
        }
        return try T(from: rawDict)
    }

    public static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [T] {
        let key = self.getDictionaryKey(name)
        guard let rawList = dictionary[key] as? [Entita.Dict] else {
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, key), nil)
        }
        return try rawList.map { try T(from: $0) }
    }

    public static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [String: T] {
        let key = self.getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: Entita.Dict] else {
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, key), nil)
        }
        return try Dictionary(uniqueKeysWithValues: rawDict.map { key, rawDict in try (key, T(from: rawDict)) })
    }

    public static func extract<T: DictionaryDecodable>(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [String: [T]] {
        let key = self.getDictionaryKey(name)
        guard let rawDict = dictionary[key] as? [String: [Entita.Dict]] else {
            // print("\(#line)")
            throw Entita.E.ExtractError(self.formatFieldKey(name, key), nil)
        }
        return try Dictionary(uniqueKeysWithValues: rawDict.map { key, rawDict in try (key, rawDict.map { try T(from: $0) }) })
    }

    public static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> Double {
        return (try self.extract(param: name, from: dictionary) as NSNumber).doubleValue
    }

    public static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> Int {
        return (try self.extract(param: name, from: dictionary) as NSNumber).intValue
    }

    public static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [Int] {
        return (try self.extract(param: name, from: dictionary) as [NSNumber]).map { $0.intValue }
    }

    public static func extract(
        param name: String,
        from dictionary: Entita.Dict
    ) throws -> [String: Int] {
        return Dictionary(
            uniqueKeysWithValues:
            (try self.extract(param: name, from: dictionary) as [String: NSNumber])
                .map { key, value in (key, value.intValue) }
        )
    }

    public static func extractID(
        from dictionary: Entita.Dict,
        as name: String = ENTITA_DEFAULT_ID_LABEL,
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

    public func extract<T>(param name: String, from dictionary: Entita.Dict) throws -> T {
        return try Swift.type(of: self).extract(param: name, from: dictionary)
    }

    public func extractID(
        from dictionary: Entita.Dict,
        as _: String = ENTITA_DEFAULT_ID_LABEL,
        subkey: String? = nil
    ) throws -> Identifier {
        return try Swift.type(of: self).extractID(from: dictionary, subkey: subkey)
    }
}
