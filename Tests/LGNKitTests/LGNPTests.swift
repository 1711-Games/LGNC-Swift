import Foundation
import XCTest
import LGNCore
@testable import LGNP

final class LGNPTests: XCTestCase {
    override class func setUp() {
        LGNP.logger.logLevel = .trace
    }

    func testCryptor() throws {
        LGNP.logger.logLevel = .trace
        XCTAssertThrowsError(try LGNP.Cryptor(salt: [1,2,3,4,5], key: [1,2,3,4,5,6,7,8]))
        XCTAssertThrowsError(try LGNP.Cryptor(salt: [1,2,3,4,5,6], key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7]))
        XCTAssertNoThrow(try LGNP.Cryptor(salt: [1,2,3,4,5, 6], key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8]))
        XCTAssertNoThrow(
            try LGNP.Cryptor(
                salt: [1,2,3,4,5,6],
                key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8,]
            )
        )

        let cryptor = try LGNP.Cryptor(salt: "foobar", key: "1234567812345678")

        let sampleData: Bytes = (0...16).map { _ in Byte.random(in: (Byte.min...Byte.max)) }
        let uuid = UUID()

        XCTAssertEqual(
            try cryptor.decrypt(
                input: try cryptor.encrypt(
                    input: sampleData,
                    uuid: uuid
                ),
                uuid: uuid
            ),
            sampleData
        )
    }

    func testMessage() {
        let uuid = UUID()

        var message = LGNP.Message(
            URI: "foo",
            payload: [1,2,3],
            meta: [0,0,0],
            salt: [4,5,6],
            controlBitmask: .defaultValues,
            uuid: uuid
        )

        message.meta = nil

        XCTAssertEqual(message.contentType, .PlainText)
        XCTAssertEqual(message.containsError, false)

        message.controlBitmask.insert(.contentTypeJSON)

        XCTAssertEqual(message.contentType, .JSON)
        XCTAssertEqual(message.controlBitmask.contentType, .JSON)
        XCTAssertEqual(message.controlBitmask.hasSignature, false)
        XCTAssertTrue(message.controlBitmask.contains(.contentTypeJSON))

        message.controlBitmask = .signatureSHA1
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .signatureSHA256
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .signatureRIPEMD160
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .signatureRIPEMD320
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .defaultValues
        XCTAssertEqual(message.controlBitmask.hasSignature, false)
        XCTAssertEqual(message.contentType, .PlainText)
        XCTAssertEqual(message.controlBitmask.bytes, [0, 0])

        message.controlBitmask = .contentTypeJSON
        XCTAssertEqual(message.contentType, .JSON)
        message.controlBitmask = .contentTypeMsgPack
        XCTAssertEqual(message.contentType, .MsgPack)
        message.controlBitmask = .contentTypeXML
        XCTAssertEqual(message.contentType, .XML)
        message.controlBitmask = .contentTypePlainText
        XCTAssertEqual(message.contentType, .PlainText)

        XCTAssertEqual(message.controlBitmask.contains(.containsMeta), false)
        message.meta = [7,8,9]
        XCTAssertEqual(message.controlBitmask.contains(.containsMeta), true)
        message.meta = nil
        XCTAssertEqual(message.controlBitmask.contains(.containsMeta), false)

        XCTAssertEqual(LGNP.Message.error(message: "abc").payload, [97, 98, 99])
        XCTAssertEqual(LGNP.Message.error(message: "abc")._payloadAsString, "abc")

        let uuid2 = UUID()
        XCTAssertEqual(
            message.copied(payload: [3,2,2], controlBitmask: .compressed, URI: "bar", uuid: uuid2),
            LGNP.Message(
                URI: "bar",
                payload: [3,2,2],
                meta: nil,
                salt: message.salt,
                controlBitmask: .compressed,
                uuid: uuid2
            )
        )
        XCTAssertEqual(
            message.copied(payload: [3,2,2]),
            LGNP.Message(
                URI: "foo",
                payload: [3,2,2],
                meta: nil,
                salt: message.salt,
                controlBitmask: message.controlBitmask,
                uuid: uuid
            )
        )
    }

    func testLGNP() throws {
        let uuid = UUID()
        let cryptor = try LGNP.Cryptor(salt: "foobar", key: "1234567812345678")
        var message = LGNP.Message(
            URI: "foo",
            payload: [1,2,3],
            meta: [4,5,6],
            salt: cryptor.salt,
            controlBitmask: [.contentTypePlainText, .signatureSHA1],
            uuid: uuid
        )

        XCTAssertEqual(
            try LGNP.decode(
                body: LGNP.encode(message: message, with: cryptor),
                salt: cryptor.salt
            ),
            message
        )

        message.controlBitmask.insert(.encrypted)
        message.meta = nil

        XCTAssertEqual(
            try LGNP.decode(
                body: LGNP.encode(message: message, with: cryptor),
                with: cryptor,
                salt: cryptor.salt
            ),
            message
        )
    }

    func testValidateMessageProtocolAndParseLength() {
        XCTAssertThrowsError(
            try LGNP.validateMessageProtocolAndParseLength(from: [], checkMinimumMessageSize: true)
        ) { error in
            guard case LGNP.E.TooShortHeaderToParse(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Message must be at least 28 bytes long (given 0 bytes)" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
        XCTAssertThrowsError(
            try LGNP.validateMessageProtocolAndParseLength(from: [1,2,3,4], checkMinimumMessageSize: true)
        ) { error in
            guard case LGNP.E.TooShortHeaderToParse(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Message must be at least 28 bytes long (given 4 bytes)" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
        XCTAssertThrowsError(
            try LGNP.validateMessageProtocolAndParseLength(
                from: [1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9,0],
                checkMinimumMessageSize: true
            )
        ) { error in
            guard case LGNP.E.InvalidMessageProtocol(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Message must begin with 'LGNP' ASCII string" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
        XCTAssertThrowsError(
            try LGNP.validateMessageProtocolAndParseLength(
                from: "LGNP".bytes + [0,0,0,0] + [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                checkMinimumMessageSize: true
            )
        ) { error in
            guard case LGNP.E.InvalidMessageLength(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Message length cannot be zero" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
        XCTAssertThrowsError(
            try LGNP.validateMessageProtocolAndParseLength(
                from: "LGNP".bytes + [1,0,0,0] + [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                checkMinimumMessageSize: true
            )
        ) { error in
            guard case LGNP.E.InvalidMessageLength(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Message length cannot be less than 20 bytes (given 1 bytes)" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
    }

    func testGetCompiledBodyFor() {
        XCTAssertThrowsError(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, salt: [], controlBitmask: .containsMeta)
            )
        ) { error in
            guard case LGNP.E.MetaSectionNotFound = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
        }

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, salt: [], controlBitmask: .encrypted)
            )
        )

        let cryptor = try! LGNP.Cryptor(salt: "foobar", key: "1234567812345678")

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, salt: [], controlBitmask: .signatureSHA1)
            )
        )

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(
                    URI: "",
                    payload: [1,2,3],
                    meta: nil,
                    salt: [],
                    controlBitmask: [.signatureRIPEMD320, .signatureRIPEMD160]
                )
            )
        )

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(
                    URI: "",
                    payload: [1,2,3],
                    meta: [1,2,3],
                    salt: [],
                    controlBitmask: [.containsMeta, .signatureSHA256]
                )
            )
        )

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, salt: [], controlBitmask: .encrypted),
                with: cryptor
            )
        )

        XCTAssertThrowsError(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, salt: [], controlBitmask: .compressed)
            )
        ) { error in
            guard case LGNP.E.CompressionFailed(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Compression is temporarily unavailable (see README.md for details)" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
    }

    static var allTests = [
        ("testCryptor", testCryptor),
    ]
}
