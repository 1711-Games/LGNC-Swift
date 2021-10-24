import Foundation
import NIO
import LGNLog

public extension LGNCore {
    enum Transport: String, Sendable {
        case LGNS, HTTP, WebSocket
        // case LGNSS, HTTPS // once, maybe
    }

    /// Request or response context
    struct Context: @unchecked Sendable {
        /// Network address from which this request physically came from.
        /// It might not be actual client address, but rather last proxy server address.
        public let remoteAddr: String

        /// End client address.
        public let clientAddr: String

        /// Unique client identifier (currently implemented only in LGNS, as `cid` meta key in LGNP message).
        /// Used for identifying clients where necessary.
        public let clientID: String?

        /// User agent. In HTTP - `User-Agent` header, in LGNS - `ua` meta key in LGNP message.
        public let userAgent: String

        /// User locale of request of response. In HTTP - `Accept-Language` header, in LGNS - `lc` meta key in LGNP message.
        public let locale: LGNCore.i18n.Locale

        /// Unique identifier of request/response in UUID v4 format.
        public let uuid: UUID

        /// Indicates if request was encrypted and/or signed.
        /// Currently supported only in LGNS (`.encrypted`, `.hasSignature` in control bitmask), HTTPS doesn't set this value to `true`.
        public let isSecure: Bool

        /// Request transport
        public let transport: Transport

        public let meta: [String: String]

        /// Event loop on which this request is being processed
        public let eventLoop: EventLoop

        public var logger: Logger {
            var logger = Logging.Logger(label: "LGNCore.Context")
            logger[metadataKey: "requestID"] = "\(self.uuid.string)"
            return logger
        }

        public init(
            remoteAddr: String,
            clientAddr: String,
            clientID: String? = nil,
            userAgent: String,
            locale: LGNCore.i18n.Locale,
            uuid: UUID,
            isSecure: Bool,
            transport: Transport,
            meta: [String: String],
            eventLoop: EventLoop
        ) {
            self.remoteAddr = remoteAddr
            self.clientAddr = clientAddr
            self.clientID = clientID
            self.userAgent = userAgent
            self.locale = locale
            self.uuid = uuid
            self.isSecure = isSecure
            self.transport = transport
            self.meta = meta
            self.eventLoop = eventLoop
        }

        /// Clones current context
        public func cloned(
            remoteAddr: String? = nil,
            clientAddr: String? = nil,
            clientID: String? = nil,
            userAgent: String? = nil,
            locale: LGNCore.i18n.Locale? = nil,
            uuid: UUID? = nil,
            isSecure: Bool? = nil,
            transport: Transport? = nil,
            meta: [String: String]? = nil
        ) -> Context {
            Self(
                remoteAddr: remoteAddr ?? self.remoteAddr,
                clientAddr: clientAddr ?? self.clientAddr,
                clientID: clientID ?? self.clientID,
                userAgent: userAgent ?? self.userAgent,
                locale: locale ?? self.locale,
                uuid: uuid ?? self.uuid,
                isSecure: isSecure ?? self.isSecure,
                transport: transport ?? self.transport,
                meta: meta ?? self.meta,
                eventLoop: self.eventLoop
            )
        }
    }
}

public extension LGNCore.Context {
    @TaskLocal
    static var current = LGNCore.Context(
        remoteAddr: "",
        clientAddr: "",
        clientID: nil,
        userAgent: "",
        locale: .enUS,
        uuid: UUID(),
        isSecure: false,
        transport: .HTTP,
        meta: [:],
        eventLoop: EmbeddedEventLoop()
    )
}
