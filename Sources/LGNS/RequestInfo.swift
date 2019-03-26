import Foundation
import LGNCore
import NIO

public extension LGNS {
    struct RequestInfo {
        public let remoteAddr: String
        public let clientAddr: String
        public let userAgent: String
        public let locale: LGNCore.Locale
        public let uuid: UUID
        public let isSecure: Bool
        public var eventLoop: EventLoop

        public init(
            remoteAddr: String,
            clientAddr: String,
            userAgent: String,
            locale: LGNCore.Locale,
            uuid: UUID,
            isSecure: Bool,
            eventLoop: EventLoop
        ) {
            self.remoteAddr = remoteAddr
            self.clientAddr = clientAddr
            self.userAgent = userAgent
            self.locale = locale
            self.uuid = uuid
            self.isSecure = isSecure
            self.eventLoop = eventLoop
        }
    }
}
