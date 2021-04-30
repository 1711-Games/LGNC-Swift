import Foundation
import LGNCore
import Entita
import NIO
import NIOWebSocket

public extension LGNC.WebSocket {
    static func getFrame(
        from entity: DictionaryEncodable,
        format: LGNCore.ContentType,
        allocator: ByteBufferAllocator,
        opcode: WebSocketOpcode = .text
    ) throws -> WebSocketFrame {
        WebSocketFrame(
            fin: true,
            opcode: opcode,
            data: try allocator.buffer(bytes: entity.getDictionary().pack(to: format))
        )
    }

    enum E: Error {
        case NoService
        case DecodeError
        case InvalidUpgradeURI
    }

    struct Request {
        public let remoteAddr: String
        public let body: Bytes
        public let eventLoop: EventLoop
    }

    struct Response {
        internal struct Box: DictionaryEncodable {
            let RequestID: String
            let Response: Entita.Dict

            init(RequestID: String, Response: LGNC.Entity.Result) throws {
                self.RequestID = RequestID
                self.Response = try Response.getDictionary()
            }

            func getDictionary() throws -> Entita.Dict {
                [
                    "RequestID": try self.encode(self.RequestID),
                    "Response": try self.encode(self.Response),
                ]
            }
        }

        let clientRequestID: String
        let frame: WebSocketFrame
        let close: Bool

        public init(clientRequestID: String, frame: WebSocketFrame, close: Bool = false) {
            self.clientRequestID = clientRequestID
            self.frame = frame
            self.close = close
        }
    }

    final class Event: ContractEntity {
        public let kind: String
        public let body: Entity

        public init(kind: String, body: Entity) {
            self.kind = kind
            self.body = body
        }

        public convenience init(from dictionary: Entita.Dict) throws {
            self.init(
                kind: try LGNC.Entity.Result.extract(param: "kind", from: dictionary),
                body: try LGNC.Entity.Result.extract(param: "body", from: dictionary)
            )
        }

        public func getDictionary() throws -> Entita.Dict {
            [
                self.getDictionaryKey("kind"): try self.encode(self.kind),
                self.getDictionaryKey("body"): try self.encode(self.body),
            ]
        }

        public static func initWithValidation(from dictionary: Entita.Dict) async throws -> Self {
            var errors: [String: [ValidatorError]] = [
                "kind": [],
                "body": [],
            ]

            var _kind: String?
            var _body: Entity?

            do {
                _kind = try Self.extract(param: "kind", from: dictionary)
            } catch Entita.E.ExtractError {
                errors["kind"]?.append(Validation.Error.MissingValue())
            }

            do {
                _body = try Self.extract(param: "body", from: dictionary)
            } catch Entita.E.ExtractError {
                errors["body"]?.append(Validation.Error.MissingValue())
            }

            let filteredErrors = errors.filter({ _, value in value.count > 0 })
            guard filteredErrors.count == 0 else {
                throw LGNC.E.DecodeError(filteredErrors)
            }

            return self.init(kind: _kind!, body: _body!)
        }
    }
}
