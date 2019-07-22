import Foundation
import LGNCore

public struct LGNP {
    public static let UUID_SIZE = MemoryLayout<UUID>.size
    public static let PROTOCOL_HEADER = "LGNP"
    public static let ERROR_RESPONSE = LGNCore.getBytes("error")
    public static let MESSAGE_HEADER_LENGTH: UInt8 = 0
        + UInt8(LGNP.getProtocolLabelBytes().count) // LGNP
        + UInt8(MemoryLayout<LGNP.Message.LengthType>.size) // Message length length
    public static let MINIMUM_MESSAGE_LENGTH: UInt8 = 0
        + LGNP.MESSAGE_HEADER_LENGTH
        + 16 // UUID
        + 2 // control bitmask
        + 1 // minimum URI length
        + 1 // NUL byte after URI

    public static var MAXIMUM_MESSAGE_LENGTH: LGNP.Message.LengthType = LGNP.Message.LengthType.max
    public static var verbose = false

    private static let logger = Logger(label: "LGNP")

    private static func getProtocolLabelBytes() -> Bytes {
        return Bytes(LGNP.PROTOCOL_HEADER.utf8)
    }

    public static func validateMessageProtocolAndParseLength(
        from messageBytes: Bytes,
        checkMinimumMessageSize: Bool = true
    ) throws -> LGNP.Message.LengthType {
        let protocolHeaderBytes = getProtocolLabelBytes()
        guard checkMinimumMessageSize == false || messageBytes.count >= LGNP.MINIMUM_MESSAGE_LENGTH else {
            // this error is soft one because chunk might be too short to parse
            // all other errors are fatal though
            throw E.TooShortHeaderToParse(
                "Message must be at least \(LGNP.MINIMUM_MESSAGE_LENGTH) bytes long (given \(messageBytes.count) bytes)"
            )
        }
        guard messageBytes.starts(with: protocolHeaderBytes) else {
            throw E.InvalidMessageProtocol("Message must begin with 'LGNP' ASCII string")
        }
        let from = protocolHeaderBytes.count
        let to = protocolHeaderBytes.count + MemoryLayout<LGNP.Message.LengthType>.size
        let length: LGNP.Message.LengthType = try messageBytes[from ..< to].cast()
        guard length != 0 else {
            throw E.InvalidMessageLength("Message length cannot be zero")
        }
        let minimumHeaderlessMessageLength = LGNP.MINIMUM_MESSAGE_LENGTH - LGNP.MESSAGE_HEADER_LENGTH
        guard length >= minimumHeaderlessMessageLength else {
            throw E.InvalidMessageLength(
                "Message length cannot be less than \(minimumHeaderlessMessageLength) bytes (given \(length) bytes)"
            )
        }
        return length
    }

    private static func getBodyFor(_ message: Message, with cryptor: Cryptor? = nil) throws -> Bytes {
        var rawBody = Bytes()
        rawBody.append(contentsOf: Bytes(message.URI.utf8))
        rawBody.addNul()
        if message.controlBitmask.contains(.containsMeta) {
            guard let meta = message.meta else {
                throw E.MetaSectionNotFound
            }
            rawBody.append(LGNCore.getBytes(Message.LengthType(meta.count)))
            rawBody.append(meta)
        }
        rawBody.append(message.payload)
        if let signature = self.getSignature(body: rawBody, message: message) {
            if verbose {
                print("[\(message.uuid.uuidString)] Compiled message signature \(signature.toHexString())")
            }
            rawBody.insert(contentsOf: signature, at: 0)
        }
        if message.controlBitmask.contains(.encrypted) {
            if let cryptor = cryptor {
                do {
                    rawBody = try cryptor.encrypt(input: rawBody, uuid: message.uuid)
                    if verbose {
                        print("[\(message.uuid.uuidString)] Encrypted message with aes")
                    }
                } catch {
                    throw E.EncryptionFailed("Encryption failed: \(error)")
                }
            } else if verbose {
                print("[\(message.uuid.uuidString)] Encrypted bitmask provided, but no Cryptor")
            }
        }
        if message.controlBitmask.contains(.compressed) {
            throw E.CompressionFailed("Compression is temporarily unavailable (see README.md for details)")
//            do {
//                rawBody = try rawBody.gzipped(level: .bestCompression)
//                if self.verbose {
//                    print("[\(message.uuid.uuidString)] Compressed message with gzip")
//                }
//            } catch {
//                throw E.CompressionFailed("Compression failed: \(error)")
//            }
        }
        if rawBody.count > LGNP.MAXIMUM_MESSAGE_LENGTH {
            throw E.EncodingFailed(
                "Maximum message size of \(LGNP.MAXIMUM_MESSAGE_LENGTH) bytes exceeded (given \(rawBody.count) bytes)"
            )
        }
        return rawBody
    }

    private static func getSignature(
        body: Bytes,
        salt: Bytes,
        controlBitmask: Message.ControlBitmask,
        uuid: UUID
    ) -> Bytes? {
        var saltedBody = body
        // TODO: order and algorithm of diffusing salt and uuid into saltedBody might be regulated
        // by private params in cryptor or smth
        saltedBody.append(salt)
        saltedBody.append(LGNCore.getBytes(uuid))
        var result: Bytes?
        if controlBitmask.contains(.signatureRIPEMD320) {
            if verbose {
                print("RIPEMD320 not implemented yet")
            }
        }
        if controlBitmask.contains(.signatureRIPEMD160) {
            if verbose {
                print("RIPEMD160 not implemented yet")
            }
        }
        if controlBitmask.contains(.signatureSHA256) {
            result = saltedBody.sha256()
        }
        if controlBitmask.contains(.signatureSHA1) {
            result = saltedBody.sha1()
        }
        return result
    }

    private static func getSignature(body: Bytes, message: Message) -> Bytes? {
        return getSignature(
            body: body,
            salt: message.salt,
            controlBitmask: message.controlBitmask,
            uuid: message.uuid
        )
    }

    public static func encode(message: Message, with cryptor: Cryptor? = nil) throws -> Bytes {
        var result = Bytes()
        if verbose {
            print("[\(message.uuid.uuidString)] Began encoding message")
        }
        result.prepend(try getBodyFor(message, with: cryptor))
        result.prepend(LGNCore.getBytes(message.controlBitmask))
        if verbose {
            print("[\(message.uuid.uuidString)] Message control bitmask is \(message.controlBitmask.rawValue)")
        }
        result.prepend(LGNCore.getBytes(message.uuid))
        if verbose {
            print("[\(message.uuid.uuidString)] Message headless size is \(Message.LengthType(result.count)) bytes")
        }
        result.prepend(LGNCore.getBytes(Message.LengthType(result.count) + Message.LengthType(MESSAGE_HEADER_LENGTH)))
        result.prepend(getProtocolLabelBytes())
        return result
    }

    public static func decode(
        body: Bytes,
        with cryptor: Cryptor? = nil,
        salt: Bytes
    ) throws -> Message {
        /*
         For some reason subscripting without casting LGNP.MESSAGE_HEADER_LENGTH (which is UInt8) to signed Int
         fails with odd error message "Not enough bits to represent a signed value". Hopefully, it will at least be
         properly documented in future Swift versions (last tested on 4.1) or even fixed.
         */
        guard body != ERROR_RESPONSE else {
            throw E.InvalidMessage("Response message is error")
        }
        guard body.count >= Int(LGNP.MESSAGE_HEADER_LENGTH) else {
            throw E.InvalidMessageProtocol("Message is not long enough: \(String(bytes: body, encoding: .ascii) ?? "unparseable")")
        }
        return try decode(
            body: Bytes(body[Int(LGNP.MESSAGE_HEADER_LENGTH)...]),
            length: try validateMessageProtocolAndParseLength(from: body),
            with: cryptor,
            salt: salt
        )
    }

    public static func decode(
        body: Bytes,
        length: Message.LengthType,
        with cryptor: Cryptor? = nil,
        salt: Bytes
    ) throws -> Message {
        let realLength = length - Message.LengthType(MESSAGE_HEADER_LENGTH)
        guard body.count >= realLength else {
            throw E.ParsingFailed("Body length must be \(realLength) bytes or more (given \(body.count) bytes)")
        }
        let uuid = try UUID(bytes: Bytes(body[0 ..< LGNP.UUID_SIZE]))
        var pos = LGNP.UUID_SIZE
        let nextPos = pos + MemoryLayout<Message.ControlBitmask.BitmaskType>.size
        let controlBitmask: Message.ControlBitmask = try Message.ControlBitmask(
            rawValue: body[pos ..< nextPos].cast()
        )
        pos = nextPos
        var payload = Bytes(body[nextPos...])
        if controlBitmask.contains(.compressed) {
            throw E.DecompressionFailed("Decompression temporarily unavailable (see README.md)")
//            do {
//                payload = try payload.gunzipped()
//                if self.verbose {
//                    print("Decompressed")
//                }
//            } catch {
//                throw E.DecompressionFailed("Could not decompress payload: \(error)")
//            }
        }
        if controlBitmask.contains(.encrypted) {
            guard let cryptor = cryptor else {
                throw E.DeencryptionFailed("Cryptor not provided for deencryption")
            }
            do {
                payload = try cryptor.decrypt(input: payload, uuid: uuid)
                if verbose {
                    print("Deencrypted")
                }
            } catch {
                throw E.DeencryptionFailed("Could not deencrypt payload: \(error)")
            }
        }
        payload = try validateSignatureAndGetBody(
            from: payload,
            uuid: uuid,
            salt: salt,
            controlBitmask: controlBitmask
        )
        guard let URIEndPos = payload.firstIndex(of: 0) else {
            throw E.URIParsingFailed("Could not find NUL byte dividing URI and payload body")
        }
        let URIBytes = payload[0 ..< URIEndPos]
        guard let URI: String = String(bytes: URIBytes, encoding: .ascii) else {
            throw E.URIParsingFailed("Could not parse ASCII URI from bytes \(Bytes(URIBytes))")
        }
        if verbose {
            print("Parsed URI '\(URI)'")
        }
        payload = Bytes(payload[(URIEndPos + 1)...])
        let meta: Bytes? = controlBitmask.contains(.containsMeta)
            ? try extractMeta(from: &payload)
            : nil
        return Message(
            URI: URI,
            payload: payload,
            meta: meta,
            salt: salt,
            controlBitmask: controlBitmask,
            uuid: uuid
        )
    }

    private static func extractMeta(from payload: inout Bytes) throws -> Bytes {
        let sizeLength: Int = MemoryLayout<LGNP.Message.LengthType>.size
        let from = payload.startIndex
        let to = from + sizeLength
        guard payload.count > sizeLength else {
            throw E.MetaSectionNotFound
        }
        let size: Message.LengthType = try payload[from ..< to].cast()
        guard payload.count > size else {
            throw E.InvalidMessageLength("Meta section is not long enough (should be \(size), given \(payload.count)")
        }
        let _to = from + sizeLength + Int(size)
        let meta = Bytes(payload[from + sizeLength ..< _to])
        payload = Bytes(payload[_to...])
        return meta
    }

    private static func validateSignatureAndGetBody(
        from payload: Bytes,
        uuid: UUID,
        salt: Bytes,
        controlBitmask: Message.ControlBitmask
    ) throws -> Bytes {
        if !controlBitmask.hasSignature {
            return payload
        }
        var signatureLength: UInt!
        var signatureName: String = "unknownAlgo"
        if controlBitmask.contains(.signatureRIPEMD320) {
            signatureName = "RIPEMD320"
            throw E.SignatureVerificationFailed("RIPEMD320 not implemented yet")
        }
        if controlBitmask.contains(.signatureRIPEMD160) {
            signatureName = "RIPEMD160"
            throw E.SignatureVerificationFailed("RIPEMD160 not implemented yet")
        }
        if controlBitmask.contains(.signatureSHA256) {
            signatureName = "SHA256"
            signatureLength = 32
        }
        if controlBitmask.contains(.signatureSHA1) {
            signatureName = "SHA1"
            signatureLength = 20
        }
        let _length: Int = Int(signatureLength)
        let givenSignature = Bytes(payload[0 ..< _length])
        let result = Bytes(payload[_length...])
        guard let etalonSignature = self.getSignature(
            body: Bytes(payload[_length...]),
            salt: salt,
            controlBitmask: controlBitmask,
            uuid: uuid
        ) else {
            throw E.SignatureVerificationFailed("Could not generate etalon \(signatureName) signature")
        }
        guard givenSignature == etalonSignature else {
            self.logger.error("Given \(signatureName) signature (\(givenSignature.toHexString())) does not match with etalon (\(etalonSignature.toHexString()))")
            throw E.SignatureVerificationFailed("Signature mismatch")
        }
        if verbose {
            print("Validated \(signatureName) signature \(etalonSignature.toHexString())")
        }
        return result
    }
}
