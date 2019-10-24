import Foundation
import LGNCore

public extension LGNP {
    struct Message {
        public typealias Length = UInt32

        internal static let LENGTH_SIZE = MemoryLayout<Self.Length>.size

        /// Represents a control bitmask containing boolean options of a parent `Message`
        public struct ControlBitmask: OptionSet {
            internal static let SIZE = UInt8(MemoryLayout<Self.BitmaskType>.size)

            public typealias BitmaskType = UInt16

            public let rawValue: BitmaskType

            /// Empty bitmask with all options in `false`
            public static let defaultValues        = ControlBitmask(rawValue: 0)

            /// Indicates that connection should not be closed as more messages are to come
            public static let keepAlive            = ControlBitmask(rawValue: 1 << 0)

            /// Indicates that message is encrypted with AES
            public static let encrypted            = ControlBitmask(rawValue: 1 << 1)

            /// Indicates that message is compressed with GZIP
            public static let compressed           = ControlBitmask(rawValue: 1 << 2)

            /// Indicates that message contains meta section
            public static let containsMeta         = ControlBitmask(rawValue: 1 << 3)

            /// Indicates that message contains (or is an) error
            public static let containsError        = ControlBitmask(rawValue: 1 << 4)

            /// Indicates that message is signed with SHA1
            public static let signatureSHA1        = ControlBitmask(rawValue: 1 << 5)

            /// Indicates that message is signed with SHA256
            public static let signatureSHA256      = ControlBitmask(rawValue: 1 << 6)

            /// Indicates that message is signed with RIPEMD160 (currently unavailable)
            public static let signatureRIPEMD160   = ControlBitmask(rawValue: 1 << 7)

            /// Indicates that message is signed with RIPEMD320 (currently unavailable)
            public static let signatureRIPEMD320   = ControlBitmask(rawValue: 1 << 8)

            // reserved                                                            9
            // reserved                                                            10

            /// Indicates that message payload is plain text
            public static let contentTypePlainText = ControlBitmask(rawValue: 1 << 11)

            /// Indicates that message payload is in MsgPack format
            public static let contentTypeMsgPack   = ControlBitmask(rawValue: 1 << 12)

            /// Indicates that message payload is in JSON format
            public static let contentTypeJSON      = ControlBitmask(rawValue: 1 << 13)

            /// Indicates that message payload is in XML format
            public static let contentTypeXML       = ControlBitmask(rawValue: 1 << 14)

            // reserved                                                            15
            // reserved                                                            16

            /// Returns `true` if message is signed
            public var hasSignature: Bool {
                return false
                    || self.contains(.signatureSHA1)
                    || self.contains(.signatureSHA256)
                    || self.contains(.signatureRIPEMD160)
                    || self.contains(.signatureRIPEMD320)
            }

            /// Returns message's content type
            public var contentType: LGNCore.ContentType {
                if self.contains(.contentTypeMsgPack) {
                    return .MsgPack
                } else if self.contains(.contentTypeJSON) {
                    return .JSON
                } else if self.contains(.contentTypeXML) {
                    return .XML
                } else if self.contains(.contentTypePlainText) {
                    return .PlainText
                }
                return .PlainText
            }

            @inlinable public init(rawValue: BitmaskType) {
                self.rawValue = rawValue
            }

            /// Returns bitmask bytes
            public var bytes: Bytes {
                return LGNCore.getBytes(rawValue)
            }
        }

        /// Message URI
        public let URI: String

        /// Message payload body
        public let payload: Bytes

        /// Message salt
        public let salt: Bytes

        /// Message UUID
        public var uuid: UUID

        /// Message control bitmask
        public var controlBitmask: ControlBitmask

        /// Message meta section
        public var meta: Bytes? {
            didSet {
                if meta != nil {
                    self.controlBitmask.insert(.containsMeta)
                } else {
                    self.controlBitmask.remove(.containsMeta)
                }
            }
        }

        /// Returns message's content type
        public var contentType: LGNCore.ContentType {
            return self.controlBitmask.contentType
        }

        /// Returns `true` if message contains (or is an) error
        public var containsError: Bool {
            return self.controlBitmask.contains(.containsError)
        }

        /// Returns message payload body as ASCII string.
        /// This operation is potentially unsafe and should be used only for debug purposes
        public var _payloadAsString: String {
            return String(bytes: payload, encoding: .ascii)!
        }

        public init(
            URI: String,
            payload: Bytes,
            meta: Bytes? = nil,
            salt: Bytes,
            controlBitmask: ControlBitmask = .defaultValues,
            uuid: UUID = UUID()
        ) {
            self.URI = URI
            self.payload = payload
            self.meta = meta
            self.salt = salt
            self.uuid = uuid

            var _controlBitmask = controlBitmask
            if let _ = self.meta {
                _controlBitmask.insert(.containsMeta)
            }

            self.controlBitmask = _controlBitmask
        }

        /// Returns a message with given error message in payload
        public static func error(message: String) -> Message {
            return self.init(URI: "", payload: message.bytes, salt: [])
        }

        /// Copies current message replacing payload, control bitmask (optional), URI (optional) and UUID (optional)
        public func copied(
            payload: Bytes,
            controlBitmask: Message.ControlBitmask? = nil,
            URI: String? = nil,
            uuid: UUID? = nil
        ) -> Message {
            Message(
                URI: URI == nil ? self.URI : "",
                payload: payload,
                salt: salt,
                controlBitmask: (controlBitmask ?? self.controlBitmask).subtracting(.containsMeta),
                uuid: uuid ?? self.uuid
            )
        }
    }
}

extension LGNP.Message: Equatable {
    public static func == (lhs: LGNP.Message, rhs: LGNP.Message) -> Bool {
        lhs.payload == rhs.payload && lhs.uuid == rhs.uuid
    }
}
