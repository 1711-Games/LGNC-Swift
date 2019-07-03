import Entita
import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

public struct LGNC {
    public static let VERSION = "0.1.0a"

    public static let ID_KEY = "a"
    public static let GLOBAL_ERROR_KEY = "_"

    private static let logger = Logger(label: "LGNC.Internal")

    /// Allows service startup without all contracts guaranteed.
    ///
    /// Intended to be used only for early development stages
    public static var ALLOW_INCOMPLETE_GUARANTEE = false {
        didSet {
            if self.ALLOW_INCOMPLETE_GUARANTEE == true {
                self.logger.warning(
                    "LGNC.ALLOW_INCOMPLETE_GUARANTEE is set to true, service may bootstrap without all contracts guaranteed"
                )
            }
        }
    }

    /// If set to `true`, `Transports` directive in LGNC scheme is ignored, and all contracts can be executed via HTTP
    ///
    /// Intended to be used only for early development stages
    public static var ALLOW_ALL_TRANSPORTS = false {
        didSet {
            if self.ALLOW_ALL_TRANSPORTS == true {
                self.logger.warning("LGNC.ALLOW_ALL_TRANSPORTS is set to true, all contracts may be executed via HTTP")
            }
        }
    }

    public static var translator: LGNCTranslator = LGNCore.i18n.DummyTranslator()

    public static func getMeta(
        from requestInfo: LGNCore.RequestInfo?,
        clientID: String? = nil
    ) -> Bytes? {
        return self.getMeta(
            clientAddr: requestInfo?.clientAddr,
            clientID: clientID,
            userAgent: requestInfo?.userAgent,
            locale: requestInfo?.locale
        )
    }

    public static func getMeta(
        clientAddr: String? = nil,
        clientID: String? = nil,
        userAgent: String? = nil,
        locale: LGNCore.i18n.Locale? = nil
    ) -> Bytes? {
        var meta: [String: String] = [:]
        if let clientAddr = clientAddr {
            meta["ip"] = clientAddr
        }
        if let clientID = clientID {
            meta["cid"] = clientID
        }
        if let userAgent = userAgent {
            meta["ua"] = userAgent
        }
        if let locale = locale {
            meta["lc"] = locale.rawValue
        }
        if meta.isEmpty {
            return nil
        }
        var metaBytes = Bytes([0, 255])
        for (k, v) in meta {
            metaBytes.append(contentsOf: Bytes("\(k)\u{00}\(v)".replacingOccurrences(of: "\n", with: "").utf8))
            metaBytes.append(10) // EOL
        }
        return metaBytes
    }
}

public extension LGNC {
    struct Entity {}
}

public extension LGNC.Entity {
    final class Result: ContractEntity {
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
        public var meta: [String: String]
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
            requestInfo: LGNCore.RequestInfo,
            type: T.Type
        ) -> EventLoopFuture<Result> {
            let eventLoop = requestInfo.eventLoop

            let errors: [String: [LGNC.Entity.Error]]? = try? self.extract(param: "errors", from: dictionary)
            let result: Entita.Dict?? = try? self.extract(param: "result", from: dictionary, isOptional: true)
            let meta: [String: String]? = try? self.extract(param: "meta", from: dictionary)
            let success: Bool? = try? self.extract(param: "success", from: dictionary)

            let validatorFutures: [String: Future<Void>] = [
                "result": eventLoop.submit {
                    let _: Entita.Dict? = try self.extract(param: "result", from: dictionary, isOptional: true)
                    guard let result = result else {
                        throw Validation.Error.MissingValue(requestInfo.locale)
                    }
                    if result == nil {
                        throw Validation.Error.SkipMissingOptionalValueValidators()
                    }
                },
                "errors": eventLoop.submit {
                    guard let _ = errors else {
                        throw Validation.Error.MissingValue(requestInfo.locale)
                    }
                },
                "meta": eventLoop.submit {
                    guard let _ = meta else {
                        throw Validation.Error.MissingValue(requestInfo.locale)
                    }
                },
                "success": eventLoop.submit {
                    guard let _ = success else {
                        throw Validation.Error.MissingValue(requestInfo.locale)
                    }
                },
            ]

            return self
                .reduce(validators: validatorFutures, requestInfo: requestInfo)
                .flatMap {
                    guard $0.count == 0 else {
                        return eventLoop.makeFailedFuture(LGNC.E.DecodeError($0.mapValues { [$0] }))
                    }

                    let future: Future<T?>
                    if let result = result {
                        future = T
                            .initWithValidation(from: result!, requestInfo: requestInfo)
                            .map { $0 }
                    } else {
                        future = eventLoop.makeSucceededFuture(nil)
                    }

                    return future.map { (result: T?) in
                        self.init(
                            result: result,
                            errors: errors!,
                            meta: meta!,
                            success: success!
                        )
                    }
                }
        }

        public static func initWithValidation(
            from dictionary: Entita.Dict,
            requestInfo: LGNCore.RequestInfo
        ) -> EventLoopFuture<Result> {
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
                    errors["result"]?.append(Validation.Error.MissingValue(requestInfo.locale))
                }

                do {
                    _errors = try Result.extract(param: "errors", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["errors"]?.append(Validation.Error.MissingValue(requestInfo.locale))
                }

                do {
                    _meta = try Result.extract(param: "meta", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["meta"]?.append(Validation.Error.MissingValue(requestInfo.locale))
                }

                do {
                    _success = try Result.extract(param: "success", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["success"]?.append(Validation.Error.MissingValue(requestInfo.locale))
                }

                let filteredErrors = errors.filter({ _, value in value.count > 0 })
                guard filteredErrors.count == 0 else {
                    throw LGNC.E.DecodeError(filteredErrors)
                }
            } catch {
                return requestInfo.eventLoop.makeFailedFuture(error)
            }

            return requestInfo.eventLoop.makeSucceededFuture(
                self.init(
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

    final class Error: ContractEntity, ClientError {
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

        public static func initWithValidation(
            from dictionary: Entita.Dict,
            requestInfo: LGNCore.RequestInfo
        ) -> EventLoopFuture<Error> {
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
                    errors["message"]?.append(Validation.Error.MissingValue(requestInfo.locale))
                }

                do {
                    _code = try Error.extract(param: "code", from: dictionary)
                } catch Entita.E.ExtractError {
                    errors["code"]?.append(Validation.Error.MissingValue(requestInfo.locale))
                }

                let filteredErrors = errors.filter({ _, value in value.count > 0 })
                guard filteredErrors.count == 0 else {
                    throw LGNC.E.DecodeError(filteredErrors)
                }
            } catch {
                return requestInfo.eventLoop.makeFailedFuture(error)
            }

            return requestInfo.eventLoop.makeSucceededFuture(
                self.init(
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

    final class Empty: ContractEntity {
        public required init() {}

        public static func initWithValidation(
            from _: Entita.Dict,
            requestInfo: LGNCore.RequestInfo
        ) -> EventLoopFuture<Empty> {
            return requestInfo.eventLoop.makeSucceededFuture(self.init())
        }

        public convenience init(from _: Entita.Dict) throws {
            self.init()
        }

        public func getDictionary() throws -> Entita.Dict {
            return [:]
        }
    }
}
