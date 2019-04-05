import Foundation
import NIO
import Logging

public extension LGNCore {
    enum Transport: String {
        case LGNS, HTTP
        // case LGNSS, HTTPS // once, maybe
    }

    struct RequestInfo {
        public let remoteAddr: String
        public let clientAddr: String
        public let userAgent: String
        public let locale: LGNCore.Translation.Locale
        public let uuid: UUID
        public let isSecure: Bool
        public let transport: Transport
        public var eventLoop: EventLoop
        public var logger: Logging.Logger

        public init(
            remoteAddr: String,
            clientAddr: String,
            userAgent: String,
            locale: LGNCore.Translation.Locale,
            uuid: UUID,
            isSecure: Bool,
            transport: Transport,
            eventLoop: EventLoop
        ) {
            self.remoteAddr = remoteAddr
            self.clientAddr = clientAddr
            self.userAgent = userAgent
            self.locale = locale
            self.uuid = uuid
            self.isSecure = isSecure
            self.transport = transport
            self.eventLoop = eventLoop

            self.logger = Logging.Logger(label: "LGNC.RequestInfo")
            logger[metadataKey: "UUID"] = "\(self.uuid.string)"
        }
    }
}
