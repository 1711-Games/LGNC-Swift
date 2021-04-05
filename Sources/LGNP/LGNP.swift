import Foundation
import LGNCore
import Crypto

/// LGNP stands for LGN Protocol and is used for sending data over network in a strict, compact and secure way.
/// Atomic unit of data in LGNP is called a message.
///
/// LGNP Message consists of following blocks:
/// - `HEAD` 4 bytes of ASCII `LGNP`
/// - `SIZE` 4 bytes of message size in LE `UInt32` (this size includes sizes of `HEAD` and `SIZE` blocks)
/// - `UUID` 16 bytes of UUID
/// - `BMSK` 2 bytes of control bitmask in LE `UInt16`
/// - `SIGN` (optional, if stated in `BMSK`) Some number of bytes of HMAC-signature (depends of algo), computed as `HMAC(URI + MSZE + META + BODY + UUID, KEY)`
/// - `URI` Some number of bytes of URI and a terminating `NUL` byte
/// - `MSZE` (optional, if stated in `BMSK`) 4 bytes of meta section size in LE `UInt32`
/// - `META` (optional, if stated in `BMSK`) Some number of bytes of meta section (size is specified in `MSZE`)
/// - `BODY` Some number of payload bytes (size is `SIZE` minus size of every preceeding block, e.g. `BODY` is the rest of message trimming after `SIZE`)
///
/// # Notes
///
/// - Sections starting from `SIGN` (uncluding one) may be encrypted with AES.GCM (using external secret key and first 12 bytes of `UUID` as nonce)
/// - Sections starting from `URI` (including one) are hashed into `SIGN` (before encryption)
/// - It's recommended to fail parsing if there is more data than stated in `SIZE` block
public enum LGNP {
    public static let ERROR_RESPONSE = LGNCore.getBytes("error")
    public static let MESSAGE_HEADER_LENGTH = Message.Block.HEAD.size + Message.Block.SIZE.size
    public static let MINIMUM_MESSAGE_LENGTH = 0
        + MESSAGE_HEADER_LENGTH
        + Message.Block.UUID.size
        + Message.Block.BMSK.size
        + 1 // minimum URI length
        + 1 // NUL byte after URI

    public static var MAXIMUM_MESSAGE_LENGTH: Message.Block.SIZE.TYPE = .max

    public static var logger = Logger(label: "LGNP")

    /// Validates and parses message header if enough bytes is provided, otherwise `LGNP.E.TooShortHeaderToParse` error is thrown which
    /// should be treated as `waiting for more bytes`. Returns expected message length.
    public static func validateMessageProtocolAndParseLength(
        from messageBytes: Bytes,
        checkMinimumMessageSize: Bool = true
    ) throws -> Message.Block.SIZE.TYPE {
        let protocolHeaderBytes = Message.Block.HEAD.bytes

        guard checkMinimumMessageSize == false || messageBytes.count >= Self.MINIMUM_MESSAGE_LENGTH else {
            // this error is soft one because chunk might be too short to parse
            // all other errors are fatal though
            throw E.TooShortHeaderToParse(
                "Message must be at least \(Self.MINIMUM_MESSAGE_LENGTH) bytes long (given \(messageBytes.count) bytes)"
            )
        }

        guard messageBytes.starts(with: protocolHeaderBytes) else {
            throw E.InvalidMessageProtocol("Message must begin with 'LGNP' ASCII string")
        }

        let from = protocolHeaderBytes.count
        let to = protocolHeaderBytes.count + Message.Block.SIZE.size
        let length: Message.Block.SIZE.TYPE = try messageBytes[from ..< to].cast()
        guard length != 0 else {
            throw E.InvalidMessageLength("Message length cannot be zero")
        }

        let minimumHeaderlessMessageLength = Self.MINIMUM_MESSAGE_LENGTH - Self.MESSAGE_HEADER_LENGTH
        guard length >= minimumHeaderlessMessageLength else {
            throw E.InvalidMessageLength(
                "Message length cannot be less than \(minimumHeaderlessMessageLength) bytes (given \(length) bytes)"
            )
        }

        return length
    }

    /// Returns compiled body bytes for given `Message` and `Cryptor`
    internal static func getCompiledBodyFor(_ message: Message, with cryptor: Cryptor) throws -> Bytes {
        var messageBlocks: [LGNPMessageBlock] = []

        messageBlocks.append(Message.Block.URI(message.URI))
        messageBlocks.append(Message.Block.NUL())

        if message.controlBitmask.contains(.containsMeta) {
            guard let meta = message.meta else {
                throw E.MetaSectionNotFound
            }

            messageBlocks.append(Message.Block.MSZE(sizeOfMeta: meta.count))
            messageBlocks.append(Message.Block.META(metaSection: meta))
        }

        messageBlocks.append(Message.Block.BODY(message.payload))

        var rawBody: Bytes = messageBlocks
            .map { $0.bytes }
            .flatMap { $0 }

        let signature = self.getSignature(bodySoFar: rawBody, cryptor: cryptor, message: message)
        if signature.count > 0 {
            self.logger.trace(
                "[\(message.uuid.uuidString)] Compiled message signature \(signature.hexString) (from body \(rawBody))"
            )
            rawBody.insert(contentsOf: Message.Block.SIGN(signature).bytes, at: 0)
        }

        if message.controlBitmask.contains(.encrypted) {
            do {
                rawBody = try cryptor.encrypt(input: rawBody, uuid: message.uuid)
                self.logger.trace("[\(message.uuid.uuidString)] Encrypted message with")
            } catch {
                throw E.EncryptionFailed("Encryption failed: \(error)")
            }
        }

        if message.controlBitmask.contains(.compressed) {
            throw E.CompressionFailed("Compression is temporarily unavailable (see README.md for details)")
//            do {
//                rawBody = try rawBody.gzipped(level: .bestCompression)
//                self.logger.debug("[\(message.uuid.uuidString)] Compressed message with gzip")
//            } catch {
//                throw E.CompressionFailed("Compression failed: \(error)")
//            }
        }

        if rawBody.count > Self.MAXIMUM_MESSAGE_LENGTH {
            throw E.EncodingFailed(
                "Maximum message size of \(Self.MAXIMUM_MESSAGE_LENGTH) bytes exceeded (given \(rawBody.count) bytes)"
            )
        }

        return rawBody
    }

    /// Returns computed signature for given body bytes, control bitmask and UUID
    private static func getSignature(
        bodySoFar: Bytes,
        cryptor: Cryptor,
        controlBitmask: Message.ControlBitmask,
        uuid: UUID
    ) -> Bytes {
        var result = Bytes()

        guard controlBitmask.hasSignature else {
            return result
        }

        let saltedBody = bodySoFar + LGNCore.getBytes(uuid)

        self.logger.trace("Salted prefix: \(saltedBody)")

        if controlBitmask.contains(.signatureSHA256) {
            result = Bytes(HMAC<SHA256>.authenticationCode(for: saltedBody, using: cryptor.symmetricKey))
        }

        if controlBitmask.contains(.signatureSHA384) {
            result = Bytes(HMAC<SHA384>.authenticationCode(for: saltedBody, using: cryptor.symmetricKey))
        }

        if controlBitmask.contains(.signatureSHA512) {
            result = Bytes(HMAC<SHA512>.authenticationCode(for: saltedBody, using: cryptor.symmetricKey))
        }

        return result
    }

    /// Returns computed signature for given body bytes and message
    private static func getSignature(bodySoFar: Bytes, cryptor: Cryptor, message: Message) -> Bytes {
        self.getSignature(
            bodySoFar: bodySoFar,
            cryptor: cryptor,
            controlBitmask: message.controlBitmask,
            uuid: message.uuid
        )
    }

    /// Returns complete message bytes for given message and cryptor
    public static func encode(message: Message, with cryptor: Cryptor) throws -> Bytes {
        var result = Bytes()

        self.logger.trace("[\(message.uuid.uuidString)] Began encoding message")

        result.prepend(try self.getCompiledBodyFor(message, with: cryptor))
        result.prepend(LGNCore.getBytes(message.controlBitmask))

        self.logger.trace("[\(message.uuid.uuidString)] Message control bitmask is \(message.controlBitmask.rawValue)")

        result.prepend(LGNCore.getBytes(message.uuid))

        self.logger.trace("[\(message.uuid.uuidString)] Message headless size is \(result.count) bytes")

        result.prepend(Message.Block.SIZE(headlessSize: result.count).bytes)
        result.prepend(Message.Block.HEAD.bytes)

        return result
    }

    /// Returns decoded message from given body and cryptor
    public static func decode(
        body: Bytes,
        with cryptor: Cryptor
    ) throws -> Message {
        /**
         For some reason subscripting without casting `Self.MESSAGE_HEADER_LENGTH` (which is `UInt8`) to signed Int
         fails with odd error message `Not enough bits to represent a signed value`. Hopefully, it will at least be
         properly documented in future Swift versions (last tested on 4.1) or even fixed.
         */
        guard body != ERROR_RESPONSE else {
            throw E.InvalidMessage("Response message is error")
        }

        guard body.count >= Self.MESSAGE_HEADER_LENGTH else {
            throw E.InvalidMessageProtocol(
                "Message is not long enough: \(String(bytes: body, encoding: .ascii) ?? "unparseable")"
            )
        }

        return try self.decodeHeadless(
            body: Bytes(body[Self.MESSAGE_HEADER_LENGTH...]),
            length: try self.validateMessageProtocolAndParseLength(from: body),
            with: cryptor
        )
    }

    /// Returns decoded message from given body, message length and cryptor
    public static func decodeHeadless(
        body: Bytes,
        length: Message.Block.SIZE.TYPE,
        with cryptor: Cryptor
    ) throws -> Message {
        let realLength = length - Message.Block.SIZE.TYPE(MESSAGE_HEADER_LENGTH)
        guard body.count >= realLength else {
            throw E.ParsingFailed("Body length must be \(realLength) bytes or more (given \(body.count) bytes)")
        }

        let uuid = try UUID(bytes: Bytes(body[0 ..< Message.Block.UUID.size]))
        var pos = Message.Block.UUID.size
        let nextPos = pos + Message.Block.BMSK.size

        let controlBitmask: Message.ControlBitmask = try Message.ControlBitmask(
            rawValue: body[pos ..< nextPos].cast()
        )

        pos = nextPos

        var payload = Bytes(body[nextPos...])

        if controlBitmask.contains(.compressed) {
            throw E.DecompressionFailed("Decompression temporarily unavailable (see README.md)")
//            do {
//                payload = try payload.gunzipped()
//                self.logger.debug("Decompressed")
//            } catch {
//                throw E.DecompressionFailed("Could not decompress payload: \(error)")
//            }
        }

        if controlBitmask.contains(.encrypted) {
            do {
                payload = try cryptor.decrypt(input: payload, uuid: uuid)
                self.logger.trace("Decrypted")
            } catch {
                throw E.DecryptionFailed("Could not decrypt payload: \(error)")
            }
        }

        payload = try validateSignatureAndGetBody(
            from: payload,
            uuid: uuid,
            cryptor: cryptor,
            controlBitmask: controlBitmask
        )

        guard let URIEndPos = payload.firstIndex(of: 0) else {
            throw E.URIParsingFailed("Could not find NUL byte dividing URI and payload body")
        }

        let URIBytes = payload[0 ..< URIEndPos]
        guard let URI: String = String(bytes: URIBytes, encoding: .ascii) else {
            throw E.URIParsingFailed("Could not parse ASCII URI from bytes \(Bytes(URIBytes))")
        }

        self.logger.trace("Parsed URI '\(URI)'")

        /// Please do not try to optimise this part: `self.extractMeta` may mutate `payload`
        payload = Bytes(payload[(URIEndPos + 1)...])
        let meta: Bytes? = controlBitmask.contains(.containsMeta)
            ? try self.extractMeta(from: &payload)
            : nil

        return Message(
            URI: URI,
            payload: payload,
            meta: meta,
            controlBitmask: controlBitmask,
            uuid: uuid
        )
    }

    /// Returns meta section bytes from given payload
    internal static func extractMeta(from payload: inout Bytes) throws -> Bytes {
        let sizeLength: Int = Message.Block.SIZE.size
        let from = payload.startIndex

        guard payload.count > sizeLength else {
            throw E.MetaSectionNotFound
        }

        let size: Message.Block.SIZE.TYPE = try payload[from ..< from + sizeLength].cast()
        self.logger.trace("Meta section size is \(size) bytes")
        guard payload.count - sizeLength > size else {
            throw E.InvalidMessageLength(
                "Meta section is not long enough (should be \(size), given \(payload.count - sizeLength))"
            )
        }

        let to = from + sizeLength + Int(size)
        let meta = Bytes(payload[from + sizeLength ..< to])

        payload = Bytes(payload[to...])

        return meta
    }

    /// Validates given signature and returns body from given payload and control bitmask
    internal static func validateSignatureAndGetBody(
        from payload: Bytes,
        uuid: UUID,
        cryptor: Cryptor,
        controlBitmask: Message.ControlBitmask
    ) throws -> Bytes {
        if !controlBitmask.hasSignature {
            return payload
        }

        var signatureLength: Int!
        var signatureName: String = "unknownAlgo"

        if controlBitmask.contains(.signatureSHA256) {
            signatureName = "SHA256"
            signatureLength = SHA256.byteCount
        }

        if controlBitmask.contains(.signatureSHA384) {
            signatureName = "SHA384"
            signatureLength = SHA384.byteCount
        }

        if controlBitmask.contains(.signatureSHA512) {
            signatureName = "SHA512"
            signatureLength = SHA512.byteCount
        }

        let givenSignature = Bytes(payload[0 ..< signatureLength])
        let result = Bytes(payload[signatureLength...])

        self.logger.trace(
            """
            Sample signature source \(Bytes(payload[signatureLength...])), \
            uuid: \(uuid), bitmask \(controlBitmask)
            """
        )
        let sampleSignature = self.getSignature(
            bodySoFar: Bytes(payload[signatureLength...]),
            cryptor: cryptor,
            controlBitmask: controlBitmask,
            uuid: uuid
        )
        let sampleSignatureHexString = sampleSignature.count > 0 ? sampleSignature.hexString : "NULL"

        guard givenSignature == sampleSignature else {
            self.logger.error(
                """
                Given \(signatureName) signature (\(givenSignature.hexString)) does not match \
                with sample (\(sampleSignatureHexString))
                """
            )
            throw E.SignatureVerificationFailed("Signature mismatch")
        }

        self.logger.trace("Validated \(signatureName) signature \(sampleSignatureHexString)")

        return result
    }
}
