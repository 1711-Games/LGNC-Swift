import Foundation
import NIO

public struct RequestInfo {
    public let remoteAddr: String
    public let clientAddr: String
    public let userAgent: String
    public let uuid: UUID
    public let isSecure: Bool
    public var eventLoop: EventLoop
}
