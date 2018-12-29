public protocol DictionaryEncodable {
    func getDictionary() throws -> Entita.Dict
}

public protocol DictionaryDecodable /*: class */ {
    init(from dictionary: Entita.Dict) throws
}

public protocol DictionaryExtractable {
    static var keyDictionary: [String: String] { get }
}

public let ENTITA_DEFAULT_ID_LABEL = "ID"

//
// public extension DictionaryDecodable {
//    public init(from dictionary: Entita.Dict) throws {
//        self = try DictionaryDecoder().decode(Self.self, dictionary)
//    }
// }

public typealias DictionaryConvertible = DictionaryEncodable & DictionaryDecodable & DictionaryExtractable
public typealias Entity = DictionaryConvertible
