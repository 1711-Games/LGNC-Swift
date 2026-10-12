import XCTest
import NIO
import NIOEmbedded
import NIOHTTP1
import LGNCore

@testable import LGNP
@testable import LGNS
@testable import LGNC

/// Malformed input must never crash the process
final class HardeningTests: XCTestCase {
    let cryptor = try! LGNP.Cryptor(key: [1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8])

    // MARK: - LGNP

    func testShortHeadlessBody() {
        for length in 0 ..< 18 {
            XCTAssertThrowsError(
                try LGNP.decodeHeadless(body: Bytes(repeating: 97, count: length), length: 100, with: self.cryptor)
            )
        }
    }

    func testSignedMessageShorterThanSignature() {
        // MSID + bitmask with SHA512 signature, but a 3-byte payload
        let bitmask = LGNP.Message.ControlBitmask.signatureSHA512.rawValue
        let body = Bytes(repeating: 97, count: 16) + withUnsafeBytes(of: bitmask.littleEndian) { Bytes($0) } + [1, 2, 3]
        XCTAssertThrowsError(try LGNP.decodeHeadless(body: body, length: UInt32(body.count + 8), with: self.cryptor))
    }

    func testNonASCIIPayloadDescription() {
        let message = LGNP.Message(URI: "", payload: [0xFF, 0xFE, 0x00, 0xC3], controlBitmask: .containsError)
        XCTAssertFalse(message._payloadAsString.isEmpty)
        XCTAssertFalse(Bytes([0xFF, 0xC3])._string.isEmpty)
    }

    func testSignatureIsCheckedInConstantTime() {
        XCTAssertTrue(LGNP.constantTimeEquals([1, 2, 3], [1, 2, 3]))
        XCTAssertFalse(LGNP.constantTimeEquals([1, 2, 3], [1, 2, 4]))
        XCTAssertFalse(LGNP.constantTimeEquals([1, 2, 3], [1, 2]))
    }

    // MARK: - LGNS framing

    func makeDecoderChannel(maximumMessageLength: Int = 1024 * 1024) throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(
            ByteToMessageHandler(
                LGNS.LGNPDecoder(
                    cryptor: self.cryptor,
                    requiredBitmask: [],
                    validateRequiredBitmask: false,
                    maximumMessageLength: maximumMessageLength
                )
            )
        )
        return channel
    }

    func encoded(_ uri: String, _ payload: String) throws -> Bytes {
        try LGNP.encode(message: LGNP.Message(URI: uri, payload: Bytes(payload.utf8)), with: self.cryptor)
    }

    func testFragmentedMessage() throws {
        let channel = try self.makeDecoderChannel()
        let bytes = try self.encoded("test", "fragmented payload")
        for byte in bytes.dropLast() {
            try channel.writeInbound(ByteBuffer(bytes: [byte]))
            XCTAssertNil(try channel.readInbound(as: LGNP.Message.self))
        }
        try channel.writeInbound(ByteBuffer(bytes: [bytes.last!]))
        let message = try XCTUnwrap(try channel.readInbound(as: LGNP.Message.self))
        XCTAssertEqual(message.URI, "test")
        XCTAssertEqual(message.payload, Bytes("fragmented payload".utf8))
    }

    func testPipelinedMessages() throws {
        let channel = try self.makeDecoderChannel()
        try channel.writeInbound(ByteBuffer(bytes: try self.encoded("first", "1") + self.encoded("second", "2")))
        XCTAssertEqual(try channel.readInbound(as: LGNP.Message.self)?.URI, "first")
        XCTAssertEqual(try channel.readInbound(as: LGNP.Message.self)?.URI, "second")
    }

    func testTooLongMessageIsRejectedBeforeBuffering() throws {
        let channel = try self.makeDecoderChannel(maximumMessageLength: 64)
        // Only the header, claiming a 1 GB message
        let header = Bytes("LGNP".utf8) + withUnsafeBytes(of: UInt32(1 << 30).littleEndian) { Bytes($0) }
        XCTAssertThrowsError(try channel.writeInbound(ByteBuffer(bytes: header)))
    }

    func testGarbageIsRejected() throws {
        let channel = try self.makeDecoderChannel()
        XCTAssertThrowsError(try channel.writeInbound(ByteBuffer(bytes: Bytes("GET / HTTP/1.1\r\n\r\n".utf8))))
    }

    // MARK: - HTTP parsing

    func testContentTypes() {
        XCTAssertEqual(LGNCore.ContentType(rawValue: ";").type, "")
        XCTAssertEqual(LGNCore.ContentType(rawValue: "").type, "")
        let multipart = LGNCore.ContentType(rawValue: "multipart/form-data; boundary=a=b")
        XCTAssertEqual(multipart.type, "multipart/form-data")
        XCTAssertEqual(multipart.options["boundary"], "a=b")
    }

    func testQueryParams() {
        let params = HTTP.parseQueryParams("a=1&b=x%26c%3D2&flag=true&space=a+b&broken=%&empty=&noValue")
        XCTAssertEqual(params["a"] as? Int, 1)
        XCTAssertEqual(params["b"] as? String, "x&c=2")
        XCTAssertNil(params["c"])
        XCTAssertEqual(params["flag"] as? Bool, true)
        XCTAssertEqual(params["space"] as? String, "a b")
        XCTAssertNil(params["broken"])
        XCTAssertEqual(params["empty"] as? String, "")
        XCTAssertTrue(HTTP.parseQueryParams("").isEmpty)
        XCTAssertTrue(HTTP.parseQueryParams("?").isEmpty)
    }

    func testBrowserMultipart() {
        let body = Bytes(
            """
            --XyZ\r
            Content-Disposition: form-data; name="title"\r
            \r
            Привет\r
            --XyZ\r
            Content-Disposition: form-data; name="file"; filename="a.txt"\r
            Content-Type: text/plain\r
            \r
            file contents\r
            --XyZ--\r

            """.utf8
        )
        let result = HTTP.parseMultipartFormdata(boundary: "XyZ", input: body)
        XCTAssertEqual(result["title"] as? String, "Привет")
        let file = result["file"] as? LGNC.Entity.File
        XCTAssertEqual(file?.filename, "a.txt")
        XCTAssertEqual(file?.body, Bytes("file contents".utf8))
    }

    func testMalformedMultipart() {
        let cases: [Bytes] = [
            Bytes("--b--b--b".utf8),
            Bytes("--b--bXXXX".utf8),
            Bytes("--b\n--b".utf8),
            Bytes("--b".utf8),
            [],
            Bytes("--b\r\nContent-Disposition: form-data; name=\"x\"\r\n\r\n".utf8) + [0xFF, 0xFE] + Bytes("\r\n--b--".utf8),
            Bytes("--b\r\nno separator\r\n--b--".utf8),
        ]
        for input in cases {
            let result = HTTP.parseMultipartFormdata(boundary: "b", input: input)
            XCTAssertNil(result["x"])
        }
    }
}
