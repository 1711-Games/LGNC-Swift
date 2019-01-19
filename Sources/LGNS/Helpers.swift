import LGNP
import NIO
import LGNCore

public typealias FutureVoid = Future<Void>

public extension Channel {
    public var remoteAddrString: String {
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

public extension ClientBootstrap {
    public func connect(to address: LGNS.Address) -> Future<Channel> {
        switch address {
        case let .ip(host, port):
            return self.connect(host: host, port: port)
        case .localhost:
            return self.connect(host: "127.0.0.1", port: LGNS.DEFAULT_PORT)
        case let .unixDomainSocket(path):
            return self.connect(unixDomainSocketPath: path)
        }
    }
}

public extension ServerBootstrap {
    public func bind(to address: LGNS.Address) -> Future<Channel> {
        switch address {
        case let .ip(host, port):
            return self.bind(host: host, port: port)
        case .localhost:
            return self.bind(host: "127.0.0.1", port: LGNS.DEFAULT_PORT)
        case let .unixDomainSocket(path):
            return self.bind(unixDomainSocketPath: path)
        }
    }
}

internal func stringIpToInt(_ input: String) -> UInt32 {
    var result: UInt32 = 0
    var i = 0
    for part in input.split(separator: ".") {
        result |= UInt32(part)! << ((3 - i) * 8)
        i += 1
    }
    return result
}

internal extension ByteBufferAllocator {
    func allocateBuffer(from string: String, encoding _: String.Encoding = .utf8) -> ByteBuffer {
        let bytes = Bytes(string.utf8)
        var buf = self.buffer(capacity: bytes.count)
        buf.write(bytes: bytes)
        return buf
    }

    func allocateBuffer(from bytes: Bytes) -> ByteBuffer {
        var buf = self.buffer(capacity: bytes.count)
        buf.write(bytes: bytes)
        return buf
    }

    func buffer(capacity: UInt8) -> ByteBuffer {
        return self.buffer(capacity: Int(capacity))
    }
}

internal extension ByteBuffer {
    mutating func readAllBytes() -> Bytes? {
        return self.readBytes(length: self.readableBytes)
    }

    mutating func readBytes<T: UnsignedInteger>(length: T) -> Bytes? {
        return self.readBytes(length: Int(length))
    }
}
