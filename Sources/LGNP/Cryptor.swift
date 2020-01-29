import CryptoSwift
import Foundation
import Gzip
import LGNCore

public extension LGNP {
    /// A helper structure for encrypting and decrypting messages using AES
    struct Cryptor {
        private static let MIN_SALT_SIZE = 6
        private static let MAX_SALT_SIZE = 12
        private static let IV_SIZE = AES.blockSize

        public let salt: Bytes
        public let key: Bytes

        /// Creates an instance of Cryptor with given `salt` and `key`.
        /// `salt` must be from 6 to 12 bytes long
        /// `key` must be 16, 24 or 32 bytes long
        public init(salt: Bytes, key: Bytes) throws {
            guard salt.count >= Cryptor.MIN_SALT_SIZE && salt.count <= Cryptor.MAX_SALT_SIZE else {
                throw E.InvalidSalt("Salt must be between 6 and 12 bytes (currently \(salt.count))")
            }

            guard key.count == 32 || key.count == 24 || key.count == 16 else {
                throw E.InvalidKey("Key must be 16, 24 or 32 bytes long (currently \(key.count))")
            }

            self.salt = salt
            self.key = key
        }

        public init(salt: String, key: String) throws {
            try self.init(
                salt: LGNCore.getBytes(salt),
                key: LGNCore.getBytes(key)
            )
        }

        /// Encrypts input bytes using given UUID as IV
        @inlinable
        public func encrypt(input: Bytes, uuid: UUID) throws -> Bytes {
            try self
                .getAES(uuid: uuid)
                .encrypt(input)
        }

        /// Decrypts input bytes using given UUID as IV
        @inlinable
        public func decrypt(input: Bytes, uuid: UUID) throws -> Bytes {
            try self
                .getAES(uuid: uuid)
                .decrypt(input)
        }

        /// Creates an instance of AES cryptor with given UUID as IV
        @usableFromInline
        internal func getAES(uuid: UUID) throws -> AES {
            try AES(
                key: self.key,
                blockMode: CBC(iv: self.getIV(from: uuid)),
                padding: .pkcs7
            )
        }

        /// Computes IV from given UUID
        @usableFromInline
        internal func getIV(from uuid: UUID) -> Bytes {
            self.salt + LGNCore.getBytes(uuid)[0 ..< Cryptor.IV_SIZE - self.salt.count]
        }
    }
}
