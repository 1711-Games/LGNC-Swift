import Foundation
import LGNCore
import Crypto
import LGNLog

/// LGNP stands for LGN Protocol and is used for sending data over network in a strict, compact and secure way.
/// Atomic unit of data in LGNP is called a message.
///
/// LGNP Message consists of following blocks:
/// - `HEAD` 4 bytes of ASCII `LGNP`
/// - `SIZE` 4 bytes of message size in LE `UInt32` (this size includes sizes of `HEAD` and `SIZE` blocks)
/// - `MSID` 16 bytes of RequestID
/// - `BMSK` 2 bytes of control bitmask in LE `UInt16`
/// - `SIGN` (optional, if stated in `BMSK`) Some number of bytes of HMAC-signature (depends of algo), computed as
///   `HMAC(MSID + BMSK + URI + NUL + MSZE + META + BODY)` with the signature key (see `LGNP.Cryptor`)
/// - `URI` Some number of bytes of URI and a terminating `NUL` byte
/// - `MSZE` (optional, if stated in `BMSK`) 4 bytes of meta section size in LE `UInt32`
/// - `META` (optional, if stated in `BMSK`) Some number of bytes of meta section (size is specified in `MSZE`)
/// - `BODY` Some number of payload bytes (size is `SIZE` minus size of every preceeding block, e.g. `BODY` is the rest of message trimming after `SIZE`)
///
/// # Notes
///
/// - Sections starting from `SIGN` (including one) may be encrypted with AES-GCM with the encryption key (see
///   `LGNP.Cryptor`) and a random nonce: the encrypted section is `NONCE (12 bytes) + ciphertext + TAG (16 bytes)`,
///   and `MSID + BMSK` are authenticated as additional data
/// - `MSID` and `BMSK` are covered by both the signature and the encryption tag, so they can't be altered
/// - It's recommended to fail parsing if there is more data than stated in `SIZE` block
public enum LGNP {
    public static let ERROR_RESPONSE = LGNCore.getBytes("error")
    public static let MESSAGE_HEADER_LENGTH = Message.Block.HEAD.size + Message.Block.SIZE.size
    public static let MINIMUM_MESSAGE_LENGTH = 0
        + MESSAGE_HEADER_LENGTH
        + Message.Block.MSID.size
        + Message.Block.BMSK.size
        + 1 // minimum URI length
        + 1 // NUL byte after URI

    /// Maximum length of a message (16 MiB by default). Longer messages are rejected on decoding as soon as their
    /// header is read, and are not encoded.
    nonisolated(unsafe) public static var MAXIMUM_MESSAGE_LENGTH: Message.Block.SIZE.TYPE = 16 * 1024 * 1024

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
        let logger = Logger.current

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
            logger.trace(
                "[\(message.msid.string)] Compiled message signature \(signature.hexString) (from body \(rawBody))"
            )
            rawBody.insert(contentsOf: Message.Block.SIGN(signature).bytes, at: 0)
        }

        if message.controlBitmask.contains(.encrypted) {
            do {
                rawBody = try cryptor.encrypt(rawBody, authenticating: Self.header(of: message))
                logger.trace("[\(message.msid.string)] Encrypted message")
            } catch {
                throw E.EncryptionFailed("Encryption failed: \(error)")
            }
        }

        if message.controlBitmask.contains(.compressed) {
            throw E.CompressionFailed("Compression is temporarily unavailable (see README.md for details)")
//            do {
//                rawBody = try rawBody.gzipped(level: .bestCompression)
//                self.logger.debug("[\(message.msid.string)] Compressed message with gzip")
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

    /// Returns computed signature for given body bytes, control bitmask and MSID
    private static func getSignature(
        bodySoFar: Bytes,
        cryptor: Cryptor,
        controlBitmask: Message.ControlBitmask,
        msid: Message.MSID
    ) -> Bytes {
        var result = Bytes()

        guard controlBitmask.hasSignature else {
            return result
        }

        let signed = Self.header(msid: msid, controlBitmask: controlBitmask) + bodySoFar

        if controlBitmask.contains(.signatureSHA256) {
            result = Bytes(HMAC<SHA256>.authenticationCode(for: signed, using: cryptor.signatureKey))
        }

        if controlBitmask.contains(.signatureSHA384) {
            result = Bytes(HMAC<SHA384>.authenticationCode(for: signed, using: cryptor.signatureKey))
        }

        if controlBitmask.contains(.signatureSHA512) {
            result = Bytes(HMAC<SHA512>.authenticationCode(for: signed, using: cryptor.signatureKey))
        }

        return result
    }

    /// `MSID + BMSK`: the part of a message authenticated by the signature and the encryption tag
    static func header(msid: Message.MSID, controlBitmask: Message.ControlBitmask) -> Bytes {
        LGNCore.getBytes(msid) + LGNCore.getBytes(controlBitmask)
    }

    static func header(of message: Message) -> Bytes {
        Self.header(msid: message.msid, controlBitmask: message.controlBitmask)
    }

    /// Returns computed signature for given body bytes and message
    private static func getSignature(bodySoFar: Bytes, cryptor: Cryptor, message: Message) -> Bytes {
        self.getSignature(
            bodySoFar: bodySoFar,
            cryptor: cryptor,
            controlBitmask: message.controlBitmask,
            msid: message.msid
        )
    }

    /// Returns complete message bytes for given message and cryptor
    public static func encode(message: Message, with cryptor: Cryptor) throws -> Bytes {
        let logger = Logger.current

        var result = Bytes()

        logger.trace("[\(message.msid.string)] Began encoding message")

        result.prepend(try self.getCompiledBodyFor(message, with: cryptor))
        result.prepend(LGNCore.getBytes(message.controlBitmask))

        logger.trace("[\(message.msid.string)] Message control bitmask is \(message.controlBitmask.rawValue)")

        result.prepend(LGNCore.getBytes(message.msid))

        logger.trace("[\(message.msid.string)] Message headless size is \(result.count) bytes")

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
        let logger = Logger.current

        let realLength = length - Message.Block.SIZE.TYPE(MESSAGE_HEADER_LENGTH)
        guard body.count >= realLength else {
            throw E.ParsingFailed("Body length must be \(realLength) bytes or more (given \(body.count) bytes)")
        }

        guard body.count >= Message.Block.MSID.size + Message.Block.BMSK.size else {
            throw E.ParsingFailed("Message body is too short (\(body.count) bytes)")
        }

        let msid = try LGNP.Message.MSID(bytes: Bytes(body[0 ..< Message.Block.MSID.size]))
        var pos = Message.Block.MSID.size
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
                payload = try cryptor.decrypt(payload, authenticating: Self.header(msid: msid, controlBitmask: controlBitmask))
                logger.trace("Decrypted")
            } catch {
                throw E.DecryptionFailed("Could not decrypt payload: \(error)")
            }
        }

        payload = try validateSignatureAndGetBody(
            from: payload,
            msid: msid,
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

        logger.trace("Parsed URI '\(URI)'")

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
            msid: msid
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
        Logger.current.trace("Meta section size is \(size) bytes")
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
        msid: Message.MSID,
        cryptor: Cryptor,
        controlBitmask: Message.ControlBitmask
    ) throws -> Bytes {
        let logger = Logger.current

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

        guard payload.count >= signatureLength else {
            throw E.SignatureVerificationFailed("Payload is shorter than \(signatureName) signature")
        }

        let givenSignature = Bytes(payload[0 ..< signatureLength])
        let result = Bytes(payload[signatureLength...])

        logger.trace(
            """
            Sample signature source \(Bytes(payload[signatureLength...])), \
            msid: \(msid), bitmask \(controlBitmask)
            """
        )
        let sampleSignature = self.getSignature(
            bodySoFar: Bytes(payload[signatureLength...]),
            cryptor: cryptor,
            controlBitmask: controlBitmask,
            msid: msid
        )
        guard Self.constantTimeEquals(givenSignature, sampleSignature) else {
            // Never log the expected signature: it would make the logs a signing oracle
            logger.error("Given \(signatureName) signature does not match")
            throw E.SignatureVerificationFailed("Signature mismatch")
        }

        logger.trace("Validated \(signatureName) signature")

        return result
    }

    /// Compares two byte arrays in time which depends only on their lengths
    static func constantTimeEquals(_ lhs: Bytes, _ rhs: Bytes) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }
}
