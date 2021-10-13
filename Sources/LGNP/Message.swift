import Foundation
import LGNCore

public extension LGNP {
    struct Message {
        /// Message URI
        public let URI: String

        /// Message payload body
        public let payload: Bytes

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
            controlBitmask: ControlBitmask = .defaultValues,
            uuid: UUID = UUID()
        ) {
            self.URI = URI
            self.payload = payload
            self.meta = meta
            self.uuid = uuid

            var _controlBitmask = controlBitmask
            if let _ = self.meta {
                _controlBitmask.insert(.containsMeta)
            }

            self.controlBitmask = _controlBitmask
        }

        /// Returns a message with given error message in payload
        public static func error(message: String) -> Message {
            return self.init(URI: "", payload: LGNCore.getBytes(message))
        }

        /// Copies current message replacing payload, control bitmask (optional), URI (optional) and UUID (optional)
        public func copied(
            payload: Bytes,
            controlBitmask: Message.ControlBitmask? = nil,
            URI: String? = nil,
            uuid: UUID? = nil,
            meta: Bytes? = nil
        ) -> Message {
            Message(
                URI: URI ?? self.URI,
                payload: payload,
                meta: meta ?? self.meta,
                controlBitmask: (controlBitmask ?? self.controlBitmask).subtracting(.containsMeta),
                uuid: uuid ?? self.uuid
            )
        }
    }
}

extension LGNP.Message: Equatable {
    public static func == (lhs: LGNP.Message, rhs: LGNP.Message) -> Bool {
        true
            && lhs.payload == rhs.payload
            && lhs.uuid == rhs.uuid
            && lhs.URI == rhs.URI // why explicit method? what's wrong with synthesized one?
    }
}
