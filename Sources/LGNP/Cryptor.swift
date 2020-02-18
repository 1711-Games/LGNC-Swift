import Crypto
import Foundation
import Gzip
import LGNCore

public extension LGNP {
    /// A helper structure for encrypting and decrypting messages using AES
    struct Cryptor {
        private static let NONCE_SIZE: Int = 12
        private static let TAG_SIZE: Int = 16

        public let key: Bytes
        internal let symmetricKey: SymmetricKey

        /// Creates an instance of Cryptor with given `key`.
        /// `key` must be 16, 24 or 32 bytes long
        public init(key: Bytes) throws {
            guard key.count == 32 || key.count == 24 || key.count == 16 else {
                throw E.InvalidKey("Key must be 16, 24 or 32 bytes long (currently \(key.count))")
            }

            self.key = key
            self.symmetricKey = SymmetricKey(data: key)
        }

        public init(key: String) throws {
            try self.init(key: LGNCore.getBytes(key))
        }

        /// Encrypts input bytes using given UUID as nonce
        @inlinable
        public func encrypt(input: Bytes, uuid: UUID) throws -> Bytes {
            try self.encrypt(input, nonce: self.getNonce(from: uuid))
        }

        /// Decrypts input bytes using given UUID as nonce
        @inlinable
        public func decrypt(input: Bytes, uuid: UUID) throws -> Bytes {
            try self.decrypt(input, nonce: self.getNonce(from: uuid))
        }

        /// Computes nonce from given UUID
        @usableFromInline
        internal func getNonce(from uuid: UUID) -> Bytes {
            Bytes(LGNCore.getBytes(uuid)[0 ..< Self.NONCE_SIZE])
        }

        @usableFromInline
        internal func encrypt(_ input: Bytes, nonce: Bytes) throws -> Bytes {
            let box = try AES.GCM.seal(
                input,
                using: self.symmetricKey,
                nonce: AES.GCM.Nonce(data: nonce)
            )
            return Bytes(box.ciphertext + box.tag)
        }

        @usableFromInline
        internal func decrypt(_ input: Bytes, nonce: Bytes) throws -> Bytes {
            guard input.count >= Self.TAG_SIZE else {
                throw E.DecryptionFailed("Encrypted payload must be 16+ bytes long (ending with a tag)")
            }

            return Bytes(
                try AES.GCM.open(
                    AES.GCM.SealedBox(
                        nonce: AES.GCM.Nonce(data: nonce),
                        ciphertext: input[0 ..< input.count - Self.TAG_SIZE],
                        tag: input[(input.count - Self.TAG_SIZE)...]
                    ),
                    using: self.symmetricKey
                )
            )
        }
    }
}
