import Foundation
import NIO

public extension LGNS {
    public struct RequestInfo {
        public let remoteAddr: String
        public let clientAddr: String
        public let userAgent: String
        public let uuid: UUID
        public let isSecure: Bool
        public var eventLoop: EventLoop

        public init(
            remoteAddr: String,
            clientAddr: String,
            userAgent: String,
            uuid: UUID,
            isSecure: Bool,
            eventLoop: EventLoop
        ) {
            self.remoteAddr = remoteAddr
            self.clientAddr = clientAddr
            self.userAgent = userAgent
            self.uuid = uuid
            self.isSecure = isSecure
            self.eventLoop = eventLoop
        }
    }
}
