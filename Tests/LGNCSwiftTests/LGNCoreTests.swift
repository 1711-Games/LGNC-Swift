import XCTest
import NIO

@testable import LGNCore

final class LGNCoreTests: XCTestCase {
    func testByteTrickery_getBytes_cast() {
        struct Foo: Equatable {
            let bar: String
        }

        let testInstance1: String = "foo bar"
        let testInstance2 = Int(123)
        let testInstance3 = false
        let testInstance4 = Foo(bar: "baz")
        let testInstance1Bytes: Bytes = [102, 111, 111, 32, 98, 97, 114]
        let testInstance2Bytes: Bytes = [123, 0, 0, 0, 0, 0, 0, 0]
        let testInstance3Bytes: Bytes = [0]
        let testInstance4Bytes: Bytes = [98, 97, 122, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 227]

        XCTAssertEqual(LGNCore.getBytes(testInstance1), testInstance1Bytes)
        XCTAssertEqual(LGNCore.getBytes(testInstance2), testInstance2Bytes)
        XCTAssertEqual(LGNCore.getBytes(testInstance3), testInstance3Bytes)
        XCTAssertEqual(LGNCore.getBytes(testInstance4), testInstance4Bytes)

        try! XCTAssertEqual(testInstance1Bytes.cast(), testInstance1)
        try! XCTAssertEqual(testInstance2Bytes.cast(), testInstance2)
        try! XCTAssertEqual(testInstance3Bytes.cast(), testInstance3)
        try! XCTAssertEqual(testInstance4Bytes.cast(), testInstance4)

        try! XCTAssertEqual(ArraySlice(testInstance1Bytes).cast(), testInstance1)
        try! XCTAssertEqual(ArraySlice(testInstance2Bytes).cast(), testInstance2)
        try! XCTAssertEqual(ArraySlice(testInstance3Bytes).cast(), testInstance3)
        try! XCTAssertEqual(ArraySlice(testInstance4Bytes).cast(), testInstance4)

        XCTAssertThrowsError(try Bytes([0, 1, 2]).cast() as Foo)
        XCTAssertThrowsError(try ArraySlice<Byte>([0, 1, 2]).cast() as Foo)

        // ASCII unpacking shouldn't throw
        XCTAssertThrowsError(try Bytes(testInstance4Bytes).cast(encoding: .utf8) as String)
        XCTAssertThrowsError(try ArraySlice<Byte>(testInstance4Bytes).cast(encoding: .utf8) as String)
    }

    func testByteTrickery_append_prepend_addNul() {
        var array: Bytes = []

        XCTAssertEqual(array, [])

        array.append(Bytes([6, 7, 8, 9]))
        XCTAssertEqual(array, [6, 7, 8, 9])

        array.prepend(Bytes([1, 2, 3, 4, 5]))
        XCTAssertEqual(array, [1, 2, 3, 4, 5, 6, 7, 8, 9])

        array.addNul()
        XCTAssertEqual(array, [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
    }

    func testRounded() {
        XCTAssertEqual(Float(0.1 + 0.2).rounded(toPlaces: 4), 0.3000)
        XCTAssertEqual(Float(13.37).rounded(toPlaces: 0), 13)
        XCTAssertEqual(Float(13.37).rounded(toPlaces: 1), 13.4)
        XCTAssertEqual(Float(13.37).rounded(toPlaces: 2), 13.37)
        XCTAssertEqual(Float(13.37).rounded(toPlaces: 3), 13.370)
        XCTAssertEqual(Float(13.37).rounded(toPlaces: 4), 13.3700)
        XCTAssertEqual(Float(13.37).rounded(toPlaces: 5), 13.37000)
    }

    func testContext() {
        let eventLoop = EmbeddedEventLoop()
        let originalInstance = LGNCore.Context(
            remoteAddr: "192.168.13.37",
            clientAddr: "195.248.161.225",
            clientID: "id1",
            userAgent: "Safari",
            locale: .ukUA,
            requestID: LGNCore.RequestID(),
            isSecure: true,
            transport: .HTTP,
            meta: [:],
            eventLoop: eventLoop
        )

        let fullyClonedInstance = originalInstance.cloned()

        XCTAssertEqual(fullyClonedInstance.clientAddr, originalInstance.clientAddr)
        XCTAssertEqual(fullyClonedInstance.clientID, originalInstance.clientID)
        XCTAssertEqual(fullyClonedInstance.userAgent, originalInstance.userAgent)
        XCTAssertEqual(fullyClonedInstance.locale, originalInstance.locale)
        XCTAssertEqual(fullyClonedInstance.requestID, originalInstance.requestID)
        XCTAssertEqual(fullyClonedInstance.isSecure, originalInstance.isSecure)
        XCTAssertEqual(fullyClonedInstance.transport, originalInstance.transport)

        let clonedInstanceRemoteAddr: String = "1.2.3.4"
        let clonedInstanceClientAddr: String = "1.1.1.1"
        let clonedInstanceClientID: String = "id2"
        let clonedInstanceUserAgent: String = "Firefox"
        let clonedInstanceLocale: LGNCore.i18n.Locale = .ruRU
        let clonedInstanceRequestID = LGNCore.RequestID()
        let clonedInstanceIsSecure: Bool = false
        let clonedInstanceTransport: LGNCore.Transport = .LGNS

        let notFullyClonedInstance = originalInstance.cloned(
            remoteAddr: clonedInstanceRemoteAddr,
            clientAddr: clonedInstanceClientAddr,
            clientID: clonedInstanceClientID,
            userAgent: clonedInstanceUserAgent,
            locale: clonedInstanceLocale,
            requestID: clonedInstanceRequestID,
            isSecure: clonedInstanceIsSecure,
            transport: clonedInstanceTransport
        )

        XCTAssertEqual(notFullyClonedInstance.remoteAddr, clonedInstanceRemoteAddr)
        XCTAssertEqual(notFullyClonedInstance.clientAddr, clonedInstanceClientAddr)
        XCTAssertEqual(notFullyClonedInstance.clientID, clonedInstanceClientID)
        XCTAssertEqual(notFullyClonedInstance.userAgent, clonedInstanceUserAgent)
        XCTAssertEqual(notFullyClonedInstance.locale, clonedInstanceLocale)
        XCTAssertEqual(notFullyClonedInstance.requestID, clonedInstanceRequestID)
        XCTAssertEqual(notFullyClonedInstance.isSecure, clonedInstanceIsSecure)
        XCTAssertEqual(notFullyClonedInstance.transport, clonedInstanceTransport)

        XCTAssertNotEqual(notFullyClonedInstance.remoteAddr, originalInstance.remoteAddr)
        XCTAssertNotEqual(notFullyClonedInstance.clientAddr, originalInstance.clientAddr)
        XCTAssertNotEqual(notFullyClonedInstance.clientID, originalInstance.clientID)
        XCTAssertNotEqual(notFullyClonedInstance.userAgent, originalInstance.userAgent)
        XCTAssertNotEqual(notFullyClonedInstance.locale, originalInstance.locale)
        XCTAssertNotEqual(notFullyClonedInstance.requestID, originalInstance.requestID)
        XCTAssertNotEqual(notFullyClonedInstance.isSecure, originalInstance.isSecure)
        XCTAssertNotEqual(notFullyClonedInstance.transport, originalInstance.transport)
    }

    func testi18nDummyTranslator() {
        LGNCore.i18n.translator = LGNCore.i18n.DummyTranslator()

        XCTAssertEqual(LGNCore.i18n.tr("foo", .ruRU), "foo")
        XCTAssertEqual(LGNCore.i18n.tr("foo", .afZA), "foo")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ruRU), "foo {bar}")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ruRU, [:]), "foo {bar}")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ruRU, ["bar": "baz"]), "foo baz")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .afZA, ["bar": "baz"]), "foo baz")
    }

    func testi18nFactoryTranslator() {
        LGNCore.i18n.translator = LGNCore.i18n.FactoryTranslator(
            phrases: [
                .ukUA: [
                    "foo": "bar",
                    "baz {lul}": "zaz {lul}",
                    "foo {bar}": LGNCore.i18n.Phrase(
                        one: "foo {bar} one",
                        few: "foo {bar} few",
                        many: "foo {bar} many",
                        other: "foo {bar} other"
                    ),
                ],
            ],
            allowedLocales: [.ukUA, .enUS]
        )

        XCTAssertEqual(LGNCore.i18n.tr("foo", .ruRU), "foo")
        XCTAssertEqual(LGNCore.i18n.tr("foo", .ukUA), "bar")
        XCTAssertEqual(LGNCore.i18n.tr("baz {lul}", .afZA), "baz {lul}")
        XCTAssertEqual(LGNCore.i18n.tr("baz {lul}", .enUS), "baz {lul}")
        XCTAssertEqual(LGNCore.i18n.tr("baz {lul}", .ukUA), "zaz {lul}")
        XCTAssertEqual(LGNCore.i18n.tr("baz {lul}", .ukUA, ["lul": "kek"]), "zaz kek")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ruRU, ["bar": "baz"]), "foo baz")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ruRU, ["bar": 1]), "foo 1")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ruRU, ["bar": 5]), "foo 5")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ukUA, ["bar": "rar"]), "foo rar other")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ukUA, ["bar": 1]), "foo 1 one")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ukUA, ["bar": 2]), "foo 2 few")
        XCTAssertEqual(LGNCore.i18n.tr("foo {bar}", .ukUA, ["bar": 5]), "foo 5 many")
    }

    static var allTests = [
        ("testByteTrickery_getBytes_cast", testByteTrickery_getBytes_cast),
        ("testByteTrickery_append_prepend_addNul", testByteTrickery_append_prepend_addNul),
        ("testRounded", testRounded),
        ("testContext", testContext),
        ("testi18nDummyTranslator", testi18nDummyTranslator),
        ("testi18nFactoryTranslator", testi18nFactoryTranslator),
    ]
}
