import Foundation
import LGNCore

public extension LGNP {
    public struct Message {
        public enum ContentType: String {
            case MsgPack, JSON, XML, PlainText

            public static var all: [ContentType] {
                return [.MsgPack, .JSON, .XML, .PlainText]
            }
        }

        public typealias LengthType = UInt32

        public struct ControlBitmask: OptionSet {
            public typealias BitmaskType = UInt16

            public let rawValue: BitmaskType

            public static let defaultValues = ControlBitmask(rawValue: 0)
            public static let keepAlive = ControlBitmask(rawValue: 1 << 0)
            public static let encrypted = ControlBitmask(rawValue: 1 << 1)
            public static let compressed = ControlBitmask(rawValue: 1 << 2)
            public static let containsMeta = ControlBitmask(rawValue: 1 << 3)
            public static let containsError = ControlBitmask(rawValue: 1 << 4)
            public static let signatureSHA1 = ControlBitmask(rawValue: 1 << 5)
            public static let signatureSHA256 = ControlBitmask(rawValue: 1 << 6)
            public static let signatureRIPEMD160 = ControlBitmask(rawValue: 1 << 7) // temporary unavailable
            public static let signatureRIPEMD320 = ControlBitmask(rawValue: 1 << 8) // temporary unavailable
            // 9 reserved
            // 10 reserved
            public static let contentTypePlainText = ControlBitmask(rawValue: 1 << 11)
            public static let contentTypeMsgPack = ControlBitmask(rawValue: 1 << 12)
            public static let contentTypeJSON = ControlBitmask(rawValue: 1 << 13)
            public static let contentTypeXML = ControlBitmask(rawValue: 1 << 14)
            // 15 reserved
            // 16 reserved

            public var hasSignature: Bool {
                return false
                    || contains(.signatureSHA1)
                    || contains(.signatureSHA256)
                    || contains(.signatureRIPEMD160)
                    || contains(.signatureRIPEMD320)
            }

            public var contentType: ContentType {
                if contains(.contentTypeMsgPack) {
                    return .MsgPack
                } else if contains(.contentTypeJSON) {
                    return .JSON
                } else if contains(.contentTypeXML) {
                    return .XML
                } else if contains(.contentTypePlainText) {
                    return .PlainText
                }
                return .PlainText
            }

            public init(rawValue: BitmaskType) {
                self.rawValue = rawValue
            }

            public var bytes: Bytes {
                return LGNCore.getBytes(rawValue)
            }
        }

        public let URI: String
        public let payload: Bytes
        public let salt: Bytes
        public var uuid: UUID
        public var controlBitmask: ControlBitmask
        public var meta: Bytes? {
            didSet {
                if meta != nil {
                    controlBitmask.insert(.containsMeta)
                } else {
                    controlBitmask.remove(.containsMeta)
                }
            }
        }

        public var contentType: ContentType {
            return controlBitmask.contentType
        }

        public var containsError: Bool {
            return controlBitmask.contains(.containsError)
        }

        public var payloadAsString: String {
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

        public static func error(message: String) -> Message {
            return self.init(URI: "", payload: message.bytes, salt: [])
        }

        public func getLikeThis(
            payload: Bytes,
            controlBitmask: Message.ControlBitmask? = nil,
            URI: String? = nil,
            uuid: UUID? = nil
        ) -> Message {
            return Message(
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
        return lhs.payload == rhs.payload && lhs.uuid == rhs.uuid
    }
}
