import Foundation
import LGNCore

public protocol LGNPMessageBlock {
    var size: Int { get }
    var bytes: Bytes { get }
}

public protocol LGNPMessageStaticBlock: LGNPMessageBlock {
    associatedtype TYPE

    static var size: Int { get }
}

extension LGNPMessageStaticBlock {
    public static var size: Int {
        MemoryLayout<TYPE>.size
    }

    public var size: Int {
        Self.size
    }
}

public extension LGNP.Message {
    enum Block {}
}

public extension LGNP.Message.Block {
    struct HEAD: LGNPMessageStaticBlock {
        public typealias TYPE = String // 4

        public static let bytes = "LGNP".bytes
        public static let size = Self.bytes.count

        public let bytes: Bytes = Self.bytes
    }

    struct SIZE: LGNPMessageStaticBlock {
        public typealias TYPE = UInt32 // 4

        public let bytes: Bytes
        public var size: Int = Self.size

        init(headlessSize: Int) {
            self.bytes = LGNCore.getBytes(TYPE(HEAD.size + headlessSize))
        }
    }

    struct UUID: LGNPMessageStaticBlock {
        public typealias TYPE = Foundation.UUID // 16

        public let bytes: Bytes
    }

    struct BMSK: LGNPMessageStaticBlock {
        public typealias TYPE = LGNP.Message.ControlBitmask.TYPE // 2

        public let bytes: Bytes
    }

    struct SIGN: LGNPMessageBlock {
        public let bytes: Bytes
        public let size: Int

        init(_ signature: Bytes) {
            self.bytes = signature
            self.size = 0
        }
    }

    struct URI: LGNPMessageBlock {
        public let bytes: Bytes
        public let size: Int

        init(_ URI: String) {
            self.bytes = LGNCore.getBytes(URI)
            self.size = 0
        }
    }

    struct MSZE: LGNPMessageStaticBlock {
        public typealias TYPE = UInt32 // 4

        public let bytes: Bytes
        public var size: Int = Self.size

        init(sizeOfMeta: Int) {
            self.bytes = LGNCore.getBytes(TYPE(sizeOfMeta))
        }
    }

    struct META: LGNPMessageBlock {
        public let bytes: Bytes
        public let size: Int

        init(metaSection: Bytes) {
            self.bytes = metaSection
            self.size = 0
        }
    }

    struct BODY: LGNPMessageBlock {
        public let bytes: Bytes
        public let size: Int

        init(_ body: Bytes) {
            self.bytes = body
            self.size = 0
        }
    }

    struct NUL: LGNPMessageBlock {
        public let bytes: Bytes = [0]
        public let size: Int = 0
    }
}
