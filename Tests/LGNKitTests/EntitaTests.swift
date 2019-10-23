import Foundation
import XCTest
@testable import Entita

final class EntitaTests: XCTestCase {
    struct Convertible: Entity, Equatable {
        let foo: String
        let int: Int = 123
        let float: Float = 13.37
        let bool: Bool = true
        let list: [String] = ["one", "two", "three"]
        let map: [String: String] = ["one": "val"]

        init(foo: String) {
            self.foo = foo
        }

        init(from dictionary: Entita.Dict) throws {
            self.init(foo: "zaz")
        }

        func getDictionary() throws -> Entita.Dict {
            return ["foo": try self.encode(self.foo)]
        }
    }

    let instanceEncodable = Convertible(foo: "bar")
    lazy var encoded = try! self.instanceEncodable.encode(self.instanceEncodable)

    func testFlattened() {
        XCTAssertEqual((123 as Int?).flattened as? Int, Int?(123))
        XCTAssertEqual((123 as Int??????).flattened as? Int, Int?(123))
        XCTAssertEqual((nil as Int??????).flattened as? Int, nil)
    }

    func testDictionaryEncodable() {
        let _ = try! Convertible(from: [:])

        // encode<T: ScalarValue>(_ input: T) throws -> Any
        XCTAssertEqual(try! self.instanceEncodable.encode(Int(1)) as? Int, 1)

        // encode<T: ScalarValue>(_ input: T?) throws -> Any
        XCTAssertEqual(try! self.instanceEncodable.encode(Int?(1)) as? Int, 1)

        // encode<T: ScalarValue>(_ input: [T]) throws -> [Any]
        XCTAssertEqual(try! self.instanceEncodable.encode([1, 2, 3]) as? [Int], [1, 2, 3])

        // encode<T: ScalarValue>(_ input: [String: T]) throws -> Entita.Dict
        let input: Entita.Dict = try! self.instanceEncodable.encode(["foo": "bar", "baz": "zaz"])
        let output: Entita.Dict = ["foo": "bar", "baz": "zaz"] as Entita.Dict
        XCTAssertEqual(input["foo"] as! String, output["foo"] as! String)
        XCTAssertEqual(input["baz"] as! String, output["baz"] as! String)

        // encode(_ input: DictionaryEncodable) throws -> Entita.Dict
        XCTAssertEqual(self.encoded["foo"] as! String, "bar")

        // encode(_ input: DictionaryEncodable?) throws -> Any
        XCTAssertEqual(self.encoded["foo"] as? String?, "bar")

        // encode(_ input: Entita.Dict?) throws -> Any
        XCTAssertNoThrow(try self.instanceEncodable.encode(self.encoded as Entita.Dict?))

        // encode<T: DictionaryEncodable>(_ input: [T]) throws -> [Entita.Dict]
        let input2: [Convertible] = [self.instanceEncodable, self.instanceEncodable, self.instanceEncodable]
        let output2: [Entita.Dict] = try! self.instanceEncodable.encode(input2)
        XCTAssert(output2.count == 3)
        XCTAssert(output2[0]["foo"] as! String == "bar")
        XCTAssert(output2[1]["foo"] as! String == "bar")
        XCTAssert(output2[2]["foo"] as! String == "bar")

        // encode<T: DictionaryEncodable>(_ input: [String: T]) throws -> Entita.Dict
        let input3: [String: Convertible] = [
            "one": self.instanceEncodable,
            "two": self.instanceEncodable,
            "three": self.instanceEncodable
        ]
        let output3: Entita.Dict = try! self.instanceEncodable.encode(input3)
        XCTAssert(output3.count == 3)
        XCTAssert((output3["one"] as! Entita.Dict)["foo"] as! String == "bar")
        XCTAssert((output3["two"] as! Entita.Dict)["foo"] as! String == "bar")
        XCTAssert((output3["three"] as! Entita.Dict)["foo"] as! String == "bar")

        // encode<T: DictionaryEncodable>(_ input: [String: [T]]) throws -> Entita.Dict
        let input4: [String: [Convertible]] = [
            "one": [self.instanceEncodable, self.instanceEncodable, self.instanceEncodable]
        ]
        let output4: Entita.Dict = try! self.instanceEncodable.encode(input4)
        XCTAssert(output4.count == 1)
        XCTAssert((output4["one"] as! [Entita.Dict]).count == 3)
        XCTAssert((output4["one"] as! [Entita.Dict])[0]["foo"] as! String == "bar")
        XCTAssert((output4["one"] as! [Entita.Dict])[1]["foo"] as! String == "bar")
        XCTAssert((output4["one"] as! [Entita.Dict])[2]["foo"] as! String == "bar")

        // encode<T: RawRepresentable>(_ input: T) throws -> T.RawValue
        enum Foo: String {
            case bar
        }
        XCTAssertEqual(try self.instanceEncodable.encode(Foo.bar), Foo.bar.rawValue)
    }

    func testDictionaryExtractable() {
        XCTAssertEqual(try Convertible(foo: "bar").extract(param: "foo", from: ["foo": "bar"]), "bar")
        
        // extract(param name: String, from dictionary: Entita.Dict) -> (key: String, value: Any?) {
        let output1: (key: String, value: Any?) = Convertible.extract(param: "foo", from: ["foo": "bar"])
        XCTAssertEqual(output1.key, "foo")
        XCTAssertEqual(output1.value as? String, "bar")
        XCTAssertEqual(output1.value as? Int, nil)
        let output2: (key: String, value: Any?) = Convertible.extract(param: "foo", from: [:])
        XCTAssertEqual(output2.key, "foo")
        XCTAssertEqual(output2.value as? String, nil)

        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict, isOptional: Bool = false) throws -> T?
        let output3: Entita.Dict? = try! Convertible.extract(
            param: "foo",
            from: ["foo": ["bar": "baz"]],
            isOptional: false
        )
        XCTAssertNotNil(output3)
        XCTAssertEqual(output3?["bar"] as? String, "baz")
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:], isOptional: false))
        XCTAssertNoThrow    (try Convertible.extract(param: "foo", from: [:], isOptional: true))

        // extract<T>(param name: String, from dictionary: Entita.Dict, isOptional: Bool) throws -> T?
        let output4: String? = try! Convertible.extract(param: "foo", from: ["foo": "bar"], isOptional: true)
        XCTAssertEqual(output4, "bar")
        XCTAssertEqual(try Convertible.extract(param: "foo", from: [:], isOptional: true) as String?, nil)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["baz": "bar"], isOptional: false) as String?)

        // extract<T: RawRepresentable>(param name: String, from dictionary: Entita.Dict) throws -> T
        enum Foo: String {
            case bar
        }
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": Foo.bar.rawValue]), Foo.bar)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as Foo)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"]) as Foo)

        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> T
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": true]) as Bool, true)
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": "bar"]) as String, "bar")
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"]) as Bool)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as Bool)

        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> [T]
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": ["bar", "baz"]]) as [String], ["bar", "baz"])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"]) as [String])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as [String])
        
        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> [String: T]
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": ["bar": true, "baz": false]]) as [String: Bool], ["bar": true, "baz": false])
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": ["bar": "lul", "baz": "kek"]]) as [String: String], ["bar": "lul", "baz": "kek"])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": ["bar": 1, "baz": "sas"]]) as [String: Bool])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as [String: Bool])

        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> [String: [T]]
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": ["bar": [1], "baz": [2]]]) as [String: [Int]], ["bar": [1], "baz": [2]])
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": ["bar": ["lul"], "baz": ["kek", "omegalul"]]]) as [String: [String]], ["bar": ["lul"], "baz": ["kek", "omegalul"]])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": ["bar": [1], "baz": ["sas"]]]) as [String: [Int]])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as [String: [Int]])

        // extract(param name: String, from dictionary: Entita.Dict) throws -> Double
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": 322.1337]) as Double, Double(322.1337))
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": 322]) as Double, Double(322))
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"]) as Double)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as Double)

        // extract(param name: String, from dictionary: Entita.Dict) throws -> Int
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": 322.1337]) as Int, Int(322))
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": 322]) as Int, Int(322))
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"]) as Int)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as Int)

        // extract(param name: String, from dictionary: Entita.Dict, isOptional: Bool = false) throws -> Int?
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": 322.1337]) as Int?, Int(322))
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": 322]) as Int?, Int(322))
        XCTAssertEqual(try Convertible.extract(param: "foo", from: [:], isOptional: true) as Int?, nil)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"], isOptional: true) as Int?)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"], isOptional: false) as Int?)
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:], isOptional: false) as Int?)

        // extract(param name: String, from dictionary: Entita.Dict) throws -> [Int]
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": [322.1337]]) as [Int], [Int(322)])
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": [322]]) as [Int], [Int(322)])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": "baz"]) as [Int])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": 123]) as [Int])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": ["baz"]]) as [Int])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as [Int])

        // extract(param name: String, from dictionary: Entita.Dict) throws -> [String: Int]
        XCTAssertEqual(try Convertible.extract(param: "foo", from: ["foo": ["bar": 1, "baz": 2]]) as [String: Int], ["bar": 1, "baz": 2])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: ["foo": ["bar": 1, "baz": "sas"]]) as [String: Int])
        XCTAssertThrowsError(try Convertible.extract(param: "foo", from: [:]) as [String: Int])
    }

    func testExtractID() throws {
        let uuid = UUID().uuidString
        XCTAssertEqual(try Convertible.extractID(from: [Entita.DEFAULT_ID_LABEL: uuid]), Identifier(uuid))
        XCTAssertEqual(try Convertible.extractID(from: ["foo": uuid], as: "foo"), Identifier(uuid))
        XCTAssertEqual(try Convertible.extractID(from: ["foo": [Entita.DEFAULT_ID_LABEL: uuid]], subkey: "foo"), Identifier(uuid))
        XCTAssertEqual(try Convertible.extractID(from: ["bar": ["foo": uuid]], as: "foo", subkey: "bar"), Identifier(uuid))
        XCTAssertThrowsError(try Convertible.extractID(from: [:]))
        XCTAssertThrowsError(try Convertible.extractID(from: ["foo": uuid]))
        XCTAssertThrowsError(try Convertible.extractID(from: ["bar": uuid], as: "foo"))
        XCTAssertThrowsError(try Convertible.extractID(from: ["lul": [Entita.DEFAULT_ID_LABEL: uuid]], subkey: "foo"))
        XCTAssertThrowsError(try Convertible.extractID(from: ["bar": ["baz": uuid]], as: "foo", subkey: "bar"))
        XCTAssertThrowsError(try Convertible.extractID(from: ["bar": NSNull()], as: "foo", subkey: "bar"))
        XCTAssertThrowsError(try Convertible.extractID(from: ["bar": [:]], as: "foo", subkey: "bar"))

        XCTAssertEqual(try Convertible(foo: "bar").extractID(from: [Entita.DEFAULT_ID_LABEL: uuid]), Identifier(uuid))
    }
    
    func testDictionaryExtractable_DictionaryExtractable() throws {
        struct DDecodable: DictionaryDecodable, DictionaryExtractable, Equatable {
            static let keyDictionary: [String: String] = [
                "foo": "f",
                "bar": "b",
            ]

            let foo: String
            let bar: Bool

            init(foo: String, bar: Bool) {
                self.foo = foo
                self.bar = bar
            }

            init(from dictionary: Entita.Dict) throws {
                self = DDecodable(
                    foo: try Self.extract(param: "foo", from: dictionary),
                    bar: try Self.extract(param: "bar", from: dictionary)
                )
            }
        }
        Entita.KEY_DICTIONARIES_ENABLED = false
        XCTAssertEqual(
            try DDecodable.extract(param: "baz", from: ["baz": ["foo": "lul", "bar": true]]),
            DDecodable(foo: "lul", bar: true)
        )
        XCTAssertEqual(
            try DDecodable.extract(
                param: "baz",
                from: ["baz": ["foo": "lul", "bar": true]],
                isOptional: false
            ) as DDecodable?,
            DDecodable(foo: "lul", bar: true)
        )
        Entita.KEY_DICTIONARIES_ENABLED = true
        XCTAssertEqual(
            try DDecodable.extract(
                param: "baz",
                from: ["baz": ["f": "lul", "b": true]],
                isOptional: false
            ) as DDecodable?,
            DDecodable(foo: "lul", bar: true)
        )
        XCTAssertEqual(
            try DDecodable.extract(
                param: "baz",
                from: [:],
                isOptional: true
            ) as DDecodable?,
            nil
        )
        XCTAssertThrowsError(
            try DDecodable.extract(
                param: "baz",
                from: ["baz": ["foo": "lul", "bar": true]],
                isOptional: false
            ) as DDecodable?
        )
        XCTAssertThrowsError(
            try DDecodable.extract(
                param: "baz",
                from: [:],
                isOptional: false
            ) as DDecodable?
        )
        XCTAssertThrowsError(
            try DDecodable.extract(
                param: "baz",
                from: [:]
            ) as DDecodable
        )
        Entita.KEY_DICTIONARIES_ENABLED = false

        XCTAssertEqual(
            try DDecodable.extract(
                param: "list",
                from: [
                    "list": [
                        ["foo": "one", "bar": true],
                        ["foo": "two", "bar": false]
                    ],
                ]
            ),
            [
                DDecodable(foo: "one", bar: true),
                DDecodable(foo: "two", bar: false),
            ]
        )
        XCTAssertThrowsError(
            try DDecodable.extract(
                param: "list",
                from: [:]
            ) as [DDecodable]
        )

        XCTAssertEqual(
            try DDecodable.extract(
                param: "map",
                from: [
                    "map": [
                        "one": ["foo": "one", "bar": true],
                        "two": ["foo": "two", "bar": false],
                    ],
                ]
            ),
            [
                "one": DDecodable(foo: "one", bar: true),
                "two": DDecodable(foo: "two", bar: false),
            ]
        )
        XCTAssertThrowsError(
            try DDecodable.extract(
                param: "list",
                from: [:]
            ) as [String: DDecodable]
        )
        
        XCTAssertEqual(
            try DDecodable.extract(
                param: "map",
                from: [
                    "map": [
                        "one": [["foo": "one", "bar": true]],
                        "two": [["foo": "two", "bar": false]],
                    ],
                ]
            ),
            [
                "one": [DDecodable(foo: "one", bar: true)],
                "two": [DDecodable(foo: "two", bar: false)],
            ]
        )
        XCTAssertThrowsError(
            try DDecodable.extract(
                param: "list",
                from: [:]
            ) as [String: [DDecodable]]
        )
    }
    
    func testDictionaryKey() {
        XCTAssertEqual(Convertible.getDictionaryKey("foo"), "foo")
        XCTAssertEqual(Convertible(foo: "bar").getDictionaryKey("foo"), "foo")
        XCTAssertEqual(Convertible.keyDictionary["foo"], nil)
    }
    
    func testGetSelfName() {
        XCTAssertEqual(
            Convertible.getSelfName(),
            "EntitaTests.Convertible"
        )
    }
    
    func testIdentifier() {
        let uuid = UUID().uuidString

        let instance1 = Identifier(uuid)
        XCTAssertEqual(instance1.string, uuid)
        XCTAssertEqual(instance1.get(), uuid)
        XCTAssertEqual(instance1.description, uuid)
        
        let instance2 = Identifier(instance1)
        XCTAssertEqual(instance1, instance2)
    }

    static var allTests = [
        ("testFlattened", testFlattened),
        ("testDictionaryEncodable", testDictionaryEncodable),
        ("testDictionaryExtractable", testDictionaryExtractable),
        ("testExtractID", testExtractID),
        ("testDictionaryExtractable_DictionaryExtractable", testDictionaryExtractable_DictionaryExtractable),
        ("testDictionaryKey", testDictionaryKey),
        ("testGetSelfName", testGetSelfName),
        ("testIdentifier", testIdentifier),
    ]
}
