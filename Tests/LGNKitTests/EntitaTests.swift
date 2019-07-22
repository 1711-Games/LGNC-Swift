import Foundation
import XCTest
@testable import Entita

final class EntitaTests: XCTestCase {
    struct Convertible: DictionaryConvertible, Equatable {
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
            self.init(foo: "zaz") // todo
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
        // extract(param name: String, from dictionary: Entita.Dict) -> (key: String, value: Any?) {
        // extract<T>(param name: String, from dictionary: Entita.Dict) throws -> T {
        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict,isOptional: Bool = false) throws -> T? {
        // extract<T>(param name: String, from dictionary: Entita.Dict,isOptional: Bool) throws -> T? {
        // extract<T: RawRepresentable>(param name: String, from dictionary: Entita.Dict) throws -> T {
        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> T {
        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> [T] {
        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> [String: T] {
        // extract<T: DictionaryDecodable>(param name: String, from dictionary: Entita.Dict) throws -> [String: [T]] {
        // extract(param name: String, from dictionary: Entita.Dict) throws -> Double {
        // extract(param name: String, from dictionary: Entita.Dict) throws -> Int {
        // extract(param name: String, from dictionary: Entita.Dict,isOptional: Bool = false) throws -> Int? {
        // extract(param name: String, from dictionary: Entita.Dict) throws -> [Int] {
        // extract(param name: String, from dictionary: Entita.Dict) throws -> [String: Int] {
        // extractID(from dictionary: Entita.Dict, as name: String = ENTITA_DEFAULT_ID_LABEL,subkey: String? = nil) throws -> Identifier {
    }

    static var allTests = [
        ("testFlattened", testFlattened),
    ]
}
