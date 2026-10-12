import LGNCore
import LGNP
import NIO

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

public extension Channel {
    /// Whether the peer is on a loopback, private or link-local address (or a Unix socket), i.e. is presumably a
    /// trusted reverse proxy rather than a client from the internet
    var isRemotePeerPrivate: Bool {
        guard let remoteAddress = self.remoteAddress else {
            return false
        }
        switch remoteAddress {
        case .unixDomainSocket:
            return true
        case .v4, .v6:
            return LGNS.isPrivateIPAddress(self.remoteAddrString)
        }
    }

    /// Address of the client: the `X-Real-IP` header if the peer is a trusted (private) proxy, the peer address
    /// otherwise (a client could spoof the header otherwise)
    func clientAddress(realIPHeader: String?) -> String {
        if let realIPHeader, !realIPHeader.isEmpty, self.isRemotePeerPrivate {
            return realIPHeader
        }
        return self.remoteAddrString
    }
}

public extension LGNS {
    /// Whether given textual IP address is loopback, private (RFC 1918, RFC 4193) or link-local
    static func isPrivateIPAddress(_ address: String) -> Bool {
        var address = address.lowercased()
        if address.hasPrefix("::ffff:") {
            address.removeFirst("::ffff:".count)
        }
        if address.contains(".") {
            let octets = address.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else {
                return false
            }
            switch (octets[0], octets[1]) {
            case (127, _), (10, _), (192, 168), (169, 254): return true
            case (172, 16 ... 31): return true
            default: return false
            }
        }
        return address == "::1" || address.hasPrefix("fc") || address.hasPrefix("fd") || address.hasPrefix("fe80:")
    }
}

