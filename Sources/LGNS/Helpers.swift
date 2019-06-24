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

public extension ClientBootstrap {
    func connect(to address: LGNCore.Address) -> Future<Channel> {
        switch address {
        case let .ip(host, port):
            return connect(host: host, port: port)
        case .localhost:
            return connect(host: "127.0.0.1", port: LGNS.DEFAULT_PORT)
        case let .unixDomainSocket(path):
            return connect(unixDomainSocketPath: path)
        }
    }
}

public extension ServerBootstrap {
    func bind(to address: LGNCore.Address) -> Future<Channel> {
        switch address {
        case let .ip(host, port):
            return bind(host: host, port: port)
        case .localhost:
            return bind(host: "127.0.0.1", port: LGNS.DEFAULT_PORT)
        case let .unixDomainSocket(path):
            return bind(unixDomainSocketPath: path)
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
        var buf = buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        return buf
    }

    func allocateBuffer(from bytes: Bytes) -> ByteBuffer {
        var buf = buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        return buf
    }

    func buffer(capacity: UInt8) -> ByteBuffer {
        return buffer(capacity: Int(capacity))
    }
}

internal extension ByteBuffer {
    mutating func readAllBytes() -> Bytes? {
        return readBytes(length: readableBytes)
    }

    mutating func readBytes<T: UnsignedInteger>(length: T) -> Bytes? {
        return readBytes(length: Int(length))
    }
}
