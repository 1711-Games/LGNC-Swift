import Entita
import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

public struct LGNC {
    public static let VERSION = "0.1.0a"

    public static let ENTITY_KEY = "a"
    public static let ID_KEY = "a"
    public static let GLOBAL_ERROR_KEY = "_"

    public static var ALLOW_INCOMPLETE_GUARANTEE = false
    public static var ALLOW_ALL_TRANSPORTS = false

    public static func getMeta(from requestInfo: LGNC.RequestInfo) -> Bytes {
        return getMeta(clientAddr: requestInfo.clientAddr, userAgent: requestInfo.userAgent)
    }

    public static func getMeta(clientAddr: String, userAgent: String) -> Bytes {
        let meta = [
            "ip": clientAddr,
            "ua": userAgent,
        ]
        var metaBytes = Bytes([0, 255])
        for (k, v) in meta {
            metaBytes.append(contentsOf: Bytes("\(k)\u{00}\(v)".replacingOccurrences(of: "\n", with: "").utf8))
            metaBytes.append(10) // EOL
        }
        return metaBytes
    }
}

public extension LGNC {
    public struct Entity {}
}

public extension LGNC {
    public struct RequestInfo {
        public let remoteAddr: String
        public let clientAddr: String
        public let userAgent: String
        public let uuid: UUID
        public let isSecure: Bool
        public let transport: LGNC.Transport
        public var eventLoop: EventLoop

        public init(
            remoteAddr: String,
            clientAddr: String,
            userAgent: String,
            uuid: UUID,
            isSecure: Bool,
            transport: LGNC.Transport,
            eventLoop: EventLoop
        ) {
            self.remoteAddr = remoteAddr
            self.clientAddr = clientAddr
            self.userAgent = userAgent
            self.uuid = uuid
            self.isSecure = isSecure
            self.transport = transport
            self.eventLoop = eventLoop
        }

        public init(
            from innerRequestInfo: LGNS.RequestInfo,
            transport: LGNC.Transport
        ) {
            remoteAddr = innerRequestInfo.remoteAddr
            clientAddr = innerRequestInfo.clientAddr
            userAgent = innerRequestInfo.userAgent
            uuid = innerRequestInfo.uuid
            isSecure = innerRequestInfo.isSecure
            eventLoop = innerRequestInfo.eventLoop
            self.transport = transport
        }
    }
}

public extension LGNC.Entity {
    public final class Result: ContractEntity {
        public static var keyDictionary: [String: String] {
            return [
//                "success": "a",
//                "result": "b",
//                "errors": "c",
//                "meta": "d",
                :
            ]
        }

        public static var internalError: Result {
            return Result(
                result: nil,
                errors: [LGNC.GLOBAL_ERROR_KEY: [LGNC.Entity.Error.internalError]],
                meta: [:],
                success: false
            )
        }

        public let result: Entity?
        public let errors: [String: [Error]]
        public let meta: [String: String]
        public let success: Bool

        public required init(
            result: Entity?,
            errors: [String: [Error]],
            meta: [String: String],
            success: Bool
        ) {
            self.result = result
            self.errors = errors
            self.meta = meta
            self.success = success
        }

        public convenience init(from errors: [String: [Error]]) {
            self.init(
                result: nil,
                errors: errors,
                meta: [:],
                success: false
            )
        }

        public convenience init(from multipleErrors: [String: [ClientError]]) {
            self.init(from: Dictionary(uniqueKeysWithValues: multipleErrors.map { key, errors in
                (key, errors.map { LGNC.Entity.Error(from: $0.getErrorTuple()) })
            }))
        }

        public convenience init(from entity: Entity, success: Bool = true) {
            self.init(result: entity, errors: [:], meta: [:], success: success)
        }

        public static func initFromResponse<T: ContractEntity>(
            from dictionary: Entita.Dict,
            on eventLoop: EventLoop,
            type _: T.Type
        ) -> EventLoopFuture<Result> {
            var errors: [String: [ValidatorError]] = [
                "result": [],
                "errors": [],
                "meta": [],
                "success": [],
            ]
            var _result: Entita.Dict?
            var _errors: [String: [Error]] = [:]
            var _meta: [String: String] = [:]
            var _success: Bool!

            do {
                do {
                    _result = try Result.extract(param: "result", from: dictionary, isOptional: true)
                } catch Entita.E.ExtractError {
                    errors["result"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _errors = try Result.extract(param: "errors", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["errors"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _meta = try Result.extract(param: "meta", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["meta"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _success = try Result.extract(param: "success", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["success"]?.append(Validation.Error.MissingValue())
                }

                let filteredErrors = errors.filter({ _, value in value.count > 0 })
                guard filteredErrors.count == 0 else {
                    throw LGNC.E.DecodeError(filteredErrors)
                }
            } catch {
                return eventLoop.newFailedFuture(error: error)
            }

            let future: Future<T?>
            if let _result = _result {
                future = T
                    .initWithValidation(from: _result, on: eventLoop)
                    .map { $0 }
            } else {
                future = eventLoop.newSucceededFuture(result: nil)
            }

            return future.map { (result: T?) in
                self.init(
                    result: result,
                    errors: _errors,
                    meta: _meta,
                    success: _success
                )
            }
        }

        public static func initWithValidation(from dictionary: Entita.Dict, on eventLoop: EventLoop) -> EventLoopFuture<Result> {
            var errors: [String: [ValidatorError]] = [
                "result": [],
                "errors": [],
                "meta": [],
                "success": [],
            ]

            var _result: Entity?
            var _errors: [String: [Error]] = [:]
            var _meta: [String: String] = [:]
            var _success: Bool!

            do {
                do {
                    _result = try Result.extract(param: "result", from: dictionary, isOptional: true)
                } catch Entita.E.ExtractError {
                    errors["result"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _errors = try Result.extract(param: "errors", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["errors"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _meta = try Result.extract(param: "meta", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["meta"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _success = try Result.extract(param: "success", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["success"]?.append(Validation.Error.MissingValue())
                }

                let filteredErrors = errors.filter({ _, value in value.count > 0 })
                guard filteredErrors.count == 0 else {
                    throw LGNC.E.DecodeError(filteredErrors)
                }
            } catch {
                return eventLoop.newFailedFuture(error: error)
            }

            return eventLoop.newSucceededFuture(
                result: self.init(
                    result: _result,
                    errors: _errors,
                    meta: _meta,
                    success: _success
                )
            )
        }

        public convenience init(from dictionary: Entita.Dict) throws {
            self.init(
                result: try Result.extract(param: "result", from: dictionary),
                errors: try Result.extract(param: "errors", from: dictionary),
                meta: try Result.extract(param: "meta", from: dictionary),
                success: try Result.extract(param: "success", from: dictionary)
            )
        }

        public func getDictionary() throws -> Entita.Dict {
            return [
                self.getDictionaryKey("result"): try self.encode(self.result),
                self.getDictionaryKey("errors"): try self.encode(self.errors),
                self.getDictionaryKey("meta"): try self.encode(self.meta),
                self.getDictionaryKey("success"): try self.encode(self.success),
            ]
        }
    }

    public final class Error: ContractEntity, ClientError {
        public static let keyDictionary: [String: String] = [
//            "message": "a",
//            "code": "b",
            :
        ]

        public let message: String
        public let code: Int

        public static var internalError: Error {
            return self.init(from: LGNC.ContractError.InternalError)
        }

        public required init(
            message: String,
            code: Int
        ) {
            self.message = message
            self.code = code
        }

        public convenience init(from tuple: (message: String, code: Int)) {
            self.init(message: tuple.message, code: tuple.code)
        }

        public convenience init(from error: ClientError) {
            self.init(from: error.getErrorTuple())
        }

        public func getErrorTuple() -> (message: String, code: Int) {
            return (message: message, code: code)
        }

        public static func initWithValidation(from dictionary: Entita.Dict, on eventLoop: EventLoop) -> EventLoopFuture<Error> {
            var errors: [String: [ValidatorError]] = [
                "message": [],
                "code": [],
            ]

            var _message: String!
            var _code: Int!

            do {
                do {
                    _message = try Error.extract(param: "message", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["message"]?.append(Validation.Error.MissingValue())
                }

                do {
                    _code = try Error.extract(param: "code", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["code"]?.append(Validation.Error.MissingValue())
                }

                let filteredErrors = errors.filter({ _, value in value.count > 0 })
                guard filteredErrors.count == 0 else {
                    throw LGNC.E.DecodeError(filteredErrors)
                }
            } catch {
                return eventLoop.newFailedFuture(error: error)
            }

            return eventLoop.newSucceededFuture(
                result: self.init(
                    message: _message,
                    code: _code
                )
            )
        }

        public convenience init(from dictionary: Entita.Dict) throws {
            self.init(
                message: try Error.extract(param: "message", from: dictionary),
                code: try Error.extract(param: "code", from: dictionary)
            )
        }

        public func getDictionary() throws -> Entita.Dict {
            return [
                self.getDictionaryKey("message"): try self.encode(self.message),
                self.getDictionaryKey("code"): try self.encode(self.code),
            ]
        }
    }

    public final class Empty: ContractEntity {
        public required init() {}

        public static func initWithValidation(from _: Entita.Dict, on eventLoop: EventLoop) -> EventLoopFuture<Empty> {
            return eventLoop.newSucceededFuture(result: self.init())
        }

        public convenience init(from _: Entita.Dict) throws {
            self.init()
        }

        public func getDictionary() throws -> Entita.Dict {
            return [:]
        }
    }
}
