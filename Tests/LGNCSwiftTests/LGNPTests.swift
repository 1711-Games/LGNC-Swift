import Foundation
import XCTest
import LGNCore
import LGNLog
@testable import LGNP
import Crypto

internal extension String {
    var bytes: Bytes {
        LGNCore.getBytes(self)
    }
}

final class LGNPTests: XCTestCase {
    override class func setUp() {
        LGNLogger.logLevel = .trace
    }

    func testCryptor() throws {
        LGNLogger.logLevel = .trace
        XCTAssertThrowsError(try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8]))
        XCTAssertThrowsError(try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7]))
        XCTAssertNoThrow(try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8]))
        XCTAssertNoThrow(
            try LGNP.Cryptor(
                key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8,]
            )
        )

        let cryptor = try LGNP.Cryptor(key: "1234567812345678")

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
            controlBitmask: .defaultValues,
            uuid: uuid
        )

        message.meta = nil

        XCTAssertEqual(message.contentType, .TextPlain)
        XCTAssertEqual(message.containsError, false)

        message.controlBitmask.insert(.contentTypeJSON)

        XCTAssertEqual(message.contentType, .JSON)
        XCTAssertEqual(message.controlBitmask.contentType, .JSON)
        XCTAssertEqual(message.controlBitmask.hasSignature, false)
        XCTAssertTrue(message.controlBitmask.contains(.contentTypeJSON))

        message.controlBitmask = .signatureSHA256
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .signatureSHA384
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .signatureSHA512
        XCTAssertEqual(message.controlBitmask.hasSignature, true)
        message.controlBitmask = .defaultValues
        XCTAssertEqual(message.controlBitmask.hasSignature, false)
        XCTAssertEqual(message.contentType, .TextPlain)
        XCTAssertEqual(message.controlBitmask.bytes, [0, 0])

        message.controlBitmask = .contentTypeJSON
        XCTAssertEqual(message.contentType, .JSON)
        message.controlBitmask = .contentTypeMsgPack
        XCTAssertEqual(message.contentType, .MsgPack)
        message.controlBitmask = .contentTypeXML
        XCTAssertEqual(message.contentType, .XML)
        message.controlBitmask = .contentTypePlainText
        XCTAssertEqual(message.contentType, .TextPlain)

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
                controlBitmask: message.controlBitmask,
                uuid: uuid
            )
        )
    }

    func testLGNP() throws {
        let uuid = UUID()
        let cryptor = try LGNP.Cryptor(key: "1234567812345678")
        var message = LGNP.Message(
            URI: "foo",
            payload: [1,2,3],
            meta: [4,5,6],
            controlBitmask: [.contentTypePlainText, .signatureSHA512],
            uuid: uuid
        )

        XCTAssertEqual(
            try LGNP.decode(
                body: LGNP.encode(message: message, with: cryptor),
                with: cryptor
            ),
            message
        )

        XCTAssertEqual(
            try LGNP.decode(
                body: LGNP.encode(
                    message: LGNP.Message(
                        URI: "foo",
                        payload: [1,2,3],
                        meta: [4,5,6],
                        controlBitmask: [.contentTypePlainText, .signatureSHA256],
                        uuid: uuid
                    ),
                    with: cryptor
                ),
                with: cryptor
            ),
            message
        )

        message.controlBitmask.insert(.encrypted)
        message.meta = nil

        XCTAssertEqual(
            try LGNP.decode(
                body: LGNP.encode(message: message, with: cryptor),
                with: cryptor
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
                XCTFail("Unexpected error message '\(message)'")
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
                XCTFail("Unexpected error message '\(message)'")
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
        let cryptor = try! LGNP.Cryptor(key: "1234567812345678")

        XCTAssertThrowsError(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, controlBitmask: .containsMeta),
                with: cryptor
            )
        ) { error in
            guard case LGNP.E.MetaSectionNotFound = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
        }

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, controlBitmask: .encrypted),
                with: cryptor
            )
        )

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, controlBitmask: .signatureSHA256),
                with: cryptor
            )
        )

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(
                    URI: "",
                    payload: [1,2,3],
                    meta: [1,2,3],
                    controlBitmask: [.containsMeta, .signatureSHA256]
                ),
                with: cryptor
            )
        )

        XCTAssertNoThrow(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, controlBitmask: .encrypted),
                with: cryptor
            )
        )

        XCTAssertThrowsError(
            try LGNP.getCompiledBodyFor(
                LGNP.Message(URI: "", payload: [1,2,3], meta: nil, controlBitmask: .compressed),
                with: cryptor
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

    func testDecode() {
        let cryptor = try! LGNP.Cryptor(key: "1234567812345678")

        XCTAssertThrowsError(
            try LGNP.decode(body: "error".bytes, with: cryptor)
        ) { error in
            guard case LGNP.E.InvalidMessage(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Response message is error" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }

        XCTAssertThrowsError(
            try LGNP.decode(body: [], with: cryptor)
        ) { error in
            guard case LGNP.E.InvalidMessageProtocol(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Message is not long enough: " else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }

        XCTAssertThrowsError(
            try LGNP.decodeHeadless(body: [], length: 48, with: cryptor)
        ) { error in
            guard case LGNP.E.ParsingFailed(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message == "Body length must be 40 bytes or more (given 0 bytes)" else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }


        // .compressed
        XCTAssertThrowsError(
            try LGNP.decode(
                body: [
                    76, 71, 78, 80, 30, 0, 0, 0, 184, 148, 23, 34, 12, 79, 74,
                    224, 149, 247, 118, 235, 247, 85, 37, 162, 4, 0, 0, 1, 2, 3,
                ],
                with: cryptor
            )
        ) { error in
            guard case LGNP.E.DecompressionFailed(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message.starts(with: "Decompression temporarily unavailable") else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }

        let uuid = UUID()
        let message = LGNP.Message(
            URI: "foo",
            payload: [1,2,3],
            meta: [4,5,6],
            controlBitmask: [.contentTypePlainText, .signatureSHA512, .encrypted],
            uuid: uuid
        )
        let encoded = try! LGNP.encode(message: message, with: cryptor)
        let headlessBody = Bytes(encoded[Int(LGNP.MESSAGE_HEADER_LENGTH)...])

        var corruptedHeadlessBody: Bytes = headlessBody
        corruptedHeadlessBody.replaceSubrange(
            30...,
            with: [
                1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5,1,2,3,4,5,6,7,
                6,7,8,9,6,7,8,9,0,1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9,0,0,1,2,3,4,5,1,2,1,2,3,4,5,6,7,
            ]
        )
        XCTAssertThrowsError(
            try LGNP.decodeHeadless(
                body: corruptedHeadlessBody,
                length: UInt32(encoded.count),
                with: cryptor
            )
        ) { error in
            guard case LGNP.E.DecryptionFailed(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }

            guard message.starts(with: "Could not decrypt payload: ") else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }

        let message2 = LGNP.Message(
            URI: "AAAAAAAAAAAAA",
            payload: [1,2,3],
            controlBitmask: .defaultValues,
            uuid: uuid
        )
        var encoded2 = try! LGNP.encode(message: message2, with: cryptor)
        encoded2[encoded2.count - 4] = 100
        XCTAssertThrowsError(
            try LGNP.decode(body: encoded2, with: cryptor)
        ) { error in
            guard case LGNP.E.URIParsingFailed(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message.starts(with: "Could not find NUL byte dividing URI and payload body") else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
    }

    func testExtractMeta() {
        var payload: Bytes = [3, 0, 0, 0, 100, 100]

        XCTAssertThrowsError(
            try LGNP.extractMeta(from: &payload)
        ) { error in
            guard case LGNP.E.InvalidMessageLength(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message.starts(with: "Meta section is not long enough (should be 3, given 2)") else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }

        payload = [0,0]

        XCTAssertThrowsError(
            try LGNP.extractMeta(from: &payload)
        ) { error in
            guard case LGNP.E.MetaSectionNotFound = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
        }
    }

    func testValidateSignatureAndGetBody() {
        let uuid = UUID()

        let cryptor = try! LGNP.Cryptor(key: "1234567812345678")
        let message = LGNP.Message(
            URI: "FFFF",
            payload: [1,2,3],
            meta: [4,5,6],
            controlBitmask: .signatureSHA384,
            uuid: uuid
        )

        XCTAssertThrowsError(
            try LGNP.validateSignatureAndGetBody(
                from: try LGNP.encode(message: message, with: cryptor),
                uuid: uuid,
                cryptor: cryptor,
                controlBitmask: message.controlBitmask
            )
        ) { error in
            guard case LGNP.E.SignatureVerificationFailed(let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            guard message.starts(with: "Signature mismatch") else {
                XCTFail("Unexpected message \(message)")
                return
            }
        }
    }

    static var allTests = [
        ("testCryptor", testCryptor),
        ("testMessage", testMessage),
        ("testLGNP", testLGNP),
        ("testValidateMessageProtocolAndParseLength", testValidateMessageProtocolAndParseLength),
        ("testGetCompiledBodyFor", testGetCompiledBodyFor),
        ("testDecode", testDecode),
        ("testExtractMeta", testExtractMeta),
        ("testValidateSignatureAndGetBody", testValidateSignatureAndGetBody),
    ]
}
