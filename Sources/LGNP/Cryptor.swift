import Crypto
import Foundation
import LGNCore

public extension LGNP {
    /// Encryption and signing of LGNP messages.
    ///
    /// Two independent keys are derived from the given key with HKDF-SHA256: one for AES-GCM encryption and one for
    /// HMAC signatures, so the same key material is never used by both primitives.
    struct Cryptor: Sendable {
        static let NONCE_SIZE: Int = 12
        static let TAG_SIZE: Int = 16

        /// The given (master) key
        public let key: Bytes
        internal let encryptionKey: SymmetricKey
        internal let signatureKey: SymmetricKey

        /// Creates an instance of Cryptor with given `key`, which must be 16, 24 or 32 bytes long
        public init(key: Bytes) throws {
            guard key.count == 32 || key.count == 24 || key.count == 16 else {
                throw E.InvalidKey("Key must be 16, 24 or 32 bytes long (currently \(key.count))")
            }

            self.key = key
            let master = SymmetricKey(data: key)
            self.encryptionKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: master,
                info: Data("LGNP v2 encryption".utf8),
                outputByteCount: 32
            )
            self.signatureKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: master,
                info: Data("LGNP v2 signature".utf8),
                outputByteCount: 32
            )
        }

        public init(key: String) throws {
            try self.init(key: LGNCore.getBytes(key))
        }

        /// Encrypts given bytes with a fresh random nonce, authenticating `header` too.
        ///
        /// Returns `nonce (12 bytes) + ciphertext + tag (16 bytes)`.
        public func encrypt(_ input: Bytes, authenticating header: Bytes) throws -> Bytes {
            let box = try AES.GCM.seal(input, using: self.encryptionKey, nonce: AES.GCM.Nonce(), authenticating: header)
            return Bytes(box.nonce) + Bytes(box.ciphertext) + Bytes(box.tag)
        }

        /// Decrypts bytes produced by ``encrypt(_:authenticating:)`` with the same `header`
        public func decrypt(_ input: Bytes, authenticating header: Bytes) throws -> Bytes {
            guard input.count >= Self.NONCE_SIZE + Self.TAG_SIZE else {
                throw E.DecryptionFailed("Encrypted payload must be at least \(Self.NONCE_SIZE + Self.TAG_SIZE) bytes long")
            }
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: input[0 ..< Self.NONCE_SIZE]),
                ciphertext: input[Self.NONCE_SIZE ..< input.count - Self.TAG_SIZE],
                tag: input[(input.count - Self.TAG_SIZE)...]
            )
            return Bytes(try AES.GCM.open(box, using: self.encryptionKey, authenticating: header))
        }
    }
}
