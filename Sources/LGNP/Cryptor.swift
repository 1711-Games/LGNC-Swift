import CryptoSwift
import Foundation
import Gzip
import LGNCore

public extension LGNP {
    public struct Cryptor {
        private static let MIN_SALT_SIZE = 6
        private static let MAX_SALT_SIZE = 12
        private static let IV_SIZE = AES.blockSize

        public let salt: String
        public let key: String

        public init(salt: String, key: String) throws {
            let saltBytes = salt.bytes.count
            guard saltBytes >= Cryptor.MIN_SALT_SIZE && saltBytes <= Cryptor.MAX_SALT_SIZE else {
                throw E.InvalidSalt("Salt must be between 6 and 12 bytes (currently \(saltBytes))")
            }
            let keyBytes = key.bytes.count
            guard keyBytes == 32 || keyBytes == 24 || keyBytes == 16 else {
                throw E.InvalidKey("Key must be 16, 24 or 32 bytes long (currently \(keyBytes))")
            }
            self.salt = salt
            self.key = key
        }

        private func getIV(from uuid: UUID) throws -> String {
            guard let iv = String(bytes: uuid.uuidString.bytes[0 ..< Cryptor.IV_SIZE - self.salt.bytes.count], encoding: .ascii) else {
                throw E.InvalidIV("Could not generate IV")
            }
            return "\(salt)\(iv)"
        }

        public func encrypt(input: Bytes, uuid: UUID) throws -> Bytes {
            return try AES(key: key, iv: try getIV(from: uuid)).encrypt(input)
        }

        public func decrypt(input: Bytes, uuid: UUID) throws -> Bytes {
            return try AES(key: key, iv: try getIV(from: uuid)).decrypt(input)
        }
    }
}
