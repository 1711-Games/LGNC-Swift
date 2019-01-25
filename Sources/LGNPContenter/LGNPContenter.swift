import Foundation
import LGNCore
import LGNP
import SwiftMsgPack

public struct LGNPConenter {
    public enum E: Error {
        case ContentError(String)
        case UnpackError(String)
        case ContentTypeNotAllowed(String)
    }
}

public extension Dictionary where Key == String {
    public func getMsgPack() throws -> Bytes {
        return try autoreleasepool {
            var msgpack = Data()
            return try msgpack.pack(self).bytes
        }
    }

    public func getJSON() throws -> Bytes {
        return try autoreleasepool {
            try JSONSerialization.data(withJSONObject: self, options: .prettyPrinted).bytes
        }
    }

    public func pack(to format: LGNP.Message.ContentType) throws -> Bytes {
        return try autoreleasepool {
            switch format {
            case .MsgPack: return try self.getMsgPack()
            case .JSON: return try JSONSerialization.data(withJSONObject: self).bytes
            case .XML: throw LGNPConenter.E.ContentError("XML content type not implemented yet")
            case .PlainText: throw LGNPConenter.E.ContentError("Dictionary cannot be plain text")
            }
        }
    }

    public func pack(to format: LGNP.Message.ContentType?) throws -> Bytes {
        guard let format = format else {
            return Bytes()
        }
        return try pack(to: format)
    }
}

protocol OptionalType {
    associatedtype Wrapped
    func map<U>(_ f: (Wrapped) throws -> U) rethrows -> U?
}

extension Optional: OptionalType {}

extension Sequence where Iterator.Element: OptionalType {
    func removeNils() -> [Iterator.Element.Wrapped] {
        var result: [Iterator.Element.Wrapped] = []
        for element in self {
            if let element = element.map({ $0 }) {
                result.append(element)
            }
        }
        return result
    }
}

public extension LGNP.Message {
    public func unpackPayload(
        _ allowedContentTypes: [LGNP.Message.ContentType] = LGNP.Message.ContentType.all
    ) throws -> [String: Any] {
        let contentType = self.contentType
        guard allowedContentTypes.contains(contentType) else {
            throw LGNPConenter.E.ContentTypeNotAllowed("Content type \(contentType) not allowed (allowed content types: \(allowedContentTypes)")
        }
        switch contentType {
        case .MsgPack: return try payload.unpackFromMsgPack()
        case .JSON: return try payload.unpackFromJSON()
        case .XML: throw LGNPConenter.E.ContentError("XML content type not implemented yet")
        case .PlainText: throw LGNPConenter.E.ContentError("Plain text content type not supported")
        }
    }
}

public extension Array where Element == Byte {
    public var ascii: String {
        return String(bytes: self, encoding: .ascii)!
    }

    public func unpackFromMsgPack() throws -> [String: Any] {
        do {
            let result: [String: Any] = try autoreleasepool {
                let copy = Data(self) // decoder is bugged and cannot accept sliced Data
                guard let result = (try copy.unpack() as Any?) as? [String: Any] else {
                    throw LGNPConenter.E.UnpackError("Could not unpack value from MsgPack")
                }
                return result
            }
            func unwrap(_ input: [String: Any]) -> [String: Any] {
                var result = input
                for (key, value) in input {
                    if let value = value as? [String: Any] {
                        result[key] = unwrap(value)
                    } else if let value = value as? [Any?] {
                        result[key] = value.removeNils()
                    }
                }
                return result
            }
            return unwrap(result)
        } catch {
            throw LGNPConenter.E.UnpackError("Could not unpack value from MsgPack: \(error)")
        }
    }

    public func unpackFromJSON() throws -> [String: Any] {
        return try autoreleasepool {
            guard let result = (try? JSONSerialization.jsonObject(with: Data(self))) as? [String: Any] else {
                throw LGNPConenter.E.UnpackError("Could not unpack value from JSON")
            }
            return result
        }
    }

    public func unpack() throws -> Any? {
        return try autoreleasepool {
            try Data(self).unpack()
        }
    }
}
