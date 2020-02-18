import LGNCore

public extension LGNP.Message {
    /// Represents a control bitmask containing boolean options of a parent `Message`
    struct ControlBitmask: OptionSet {
        public typealias TYPE = UInt16

        public let rawValue: TYPE

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

        /// Indicates that message is signed with SHA256
        public static let signatureSHA256      = ControlBitmask(rawValue: 1 << 5)

        /// Indicates that message is signed with SHA384
        public static let signatureSHA384      = ControlBitmask(rawValue: 1 << 6)

        /// Indicates that message is signed with SHA512
        public static let signatureSHA512      = ControlBitmask(rawValue: 1 << 7)

        // reserved                                                            8
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
        @inlinable public var hasSignature: Bool {
            return false
                || self.contains(.signatureSHA256)
                || self.contains(.signatureSHA384)
                || self.contains(.signatureSHA512)
        }

        /// Returns `false` if message doesn't have a content type set (or if plain text is set)
        public var hasContentType: Bool {
            return false
                || self.contains(.contentTypeXML)
                || self.contains(.contentTypeJSON)
                || self.contains(.contentTypeMsgPack)
        }

        /// Returns message's content type
        @inlinable public var contentType: LGNCore.ContentType {
            let result: LGNCore.ContentType

            if self.contains(.contentTypeMsgPack) {
                result = .MsgPack
            } else if self.contains(.contentTypeJSON) {
                result = .JSON
            } else if self.contains(.contentTypeXML) {
                result = .XML
            } else if self.contains(.contentTypePlainText) {
                result = .PlainText
            } else {
                result = .PlainText
            }

            return result
        }

        @inlinable public init(rawValue: TYPE) {
            self.rawValue = rawValue
        }

        /// Returns bitmask bytes
        public var bytes: Bytes {
            return LGNCore.getBytes(rawValue)
        }
    }
}
