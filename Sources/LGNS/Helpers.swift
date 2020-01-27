import LGNCore
import LGNP
import NIO

public typealias FutureVoid = Future<Void>

public extension Channel {
    var remoteAddrString: String {
        var remoteAddr: String = ""
        if let remoteAddress = self.remoteAddress {
            switch remoteAddress {
            case .unixDomainSocket: remoteAddr = remoteAddress.description
            case let .v4(ip): remoteAddr = ip.host
            case let .v6(ip): remoteAddr = ip.host
            }
        }
        return remoteAddr
    }
}

internal extension ByteBufferAllocator {
    func allocateBuffer(from string: String, encoding _: String.Encoding = .utf8) -> ByteBuffer {
        let bytes = Bytes(string.utf8)
        var buf = self.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        return buf
    }

    func allocateBuffer(from bytes: Bytes) -> ByteBuffer {
        var buf = self.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        return buf
    }

    func buffer(capacity: UInt8) -> ByteBuffer {
        return self.buffer(capacity: Int(capacity))
    }
}

internal extension ByteBuffer {
    mutating func readAllBytes() -> Bytes? {
        return self.readBytes(length: readableBytes)
    }

    mutating func readBytes<T: UnsignedInteger>(length: T) -> Bytes? {
        return self.readBytes(length: Int(length))
    }
}
