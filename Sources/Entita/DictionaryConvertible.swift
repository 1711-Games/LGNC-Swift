/// A helper protocol containing all methods for extracting values from input dictionary
public protocol DictionaryExtractable {
    /// A dictionary holding names for keys of entity
    static var keyDictionary: [String: String] { get }
}

/// An encodable entity
public protocol DictionaryEncodable: DictionaryExtractable {
    /// Returns current entity as dictionary
    func getDictionary() throws -> Entita.Dict
}

/// An decodable entity
public protocol DictionaryDecodable: DictionaryExtractable /*: class */ {
    /// Initiates an entity from a dictionary
    init(from dictionary: Entita.Dict) throws
}

/// An entity that can be encoded and decoded
public typealias DictionaryConvertible = DictionaryEncodable & DictionaryDecodable & DictionaryExtractable

/// An entity that can be encoded and decoded
public typealias Entity = DictionaryConvertible
