import Entita
import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

public enum LGNC {
    public static let VERSION = "0.9.9.9"

    public static let ID_KEY = "a"
    public static let GLOBAL_ERROR_KEY = "_"

    public static var logger = Logger(label: "LGNC")

    public static let cookieDateFormatter: DateFormatter = {
        let formatter = DateFormatter()

        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"

        return formatter
    }()

    /// Allows service startup without all contracts guaranteed.
    ///
    /// Intended to be used only for early development stages
    public static var ALLOW_INCOMPLETE_GUARANTEE = false {
        didSet {
            if self.ALLOW_INCOMPLETE_GUARANTEE == true {
                self.logger.warning(
                    """
                    LGNC.ALLOW_INCOMPLETE_GUARANTEE is set to true, \
                    service may bootstrap without all contracts guaranteed
                    """
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
                self.logger.warning(
                    """
                    LGNC.ALLOW_ALL_TRANSPORTS is set to true, all contracts may be executed via HTTP, \
                    which is not secure and is recommended only for development purposes
                    """
                )
            }
        }
    }

    /// Translator, by default `LGNCore.i18n.DummyTranslator` which doesn't actually translate anything, but only proxy input
    public static var translator: LGNCTranslator = LGNCore.i18n.DummyTranslator()

    /// Starts an HTTP server for given service and params. Returns a future with a server, which must be waited for until claiming the server as operational.
    public static func startServerHTTP<S: Service>(
        service: S.Type,
        at target: LGNCore.Address? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) async throws -> AnyServer {
        try await S.startServerHTTP(
            at: target,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        )
    }

    /// Starts an LGNS server for given service and params. Returns a future with a server, which must be waited for until claiming the server as operational.
    public static func startServerLGNS<S: Service>(
        service: S.Type,
        at target: LGNCore.Address? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1)
    ) async throws -> AnyServer {
        try await S.startServerLGNS(
            at: target,
            cryptor: cryptor,
            eventLoopGroup: eventLoopGroup,
            requiredBitmask: requiredBitmask,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        )
    }

    public static func getCompiledMeta(
        from context: LGNCore.Context?,
        clientID: String? = nil
    ) -> Bytes? {
        self.getCompiledMeta(
            clientAddr: context?.clientAddr,
            clientID: clientID,
            userAgent: context?.userAgent,
            locale: context?.locale
        )
    }

    public static func getCompiledMeta(
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
    enum Entity {}
}

public extension LGNC.Entity {
    typealias Meta = [String: String]

    /// A general body-agnostic wrapper (envelope) for all contract responses
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
            Self(
                result: nil,
                errors: [LGNC.GLOBAL_ERROR_KEY: [LGNC.Entity.Error.internalError]],
                meta: [:],
                success: false
            )
        }

        public let result: Entity?
        public let errors: [String: [Error]]
        public var meta: Meta
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
            self.init(
                from: Dictionary(
                    uniqueKeysWithValues: multipleErrors.map { key, errors in
                        (
                            key,
                            errors.map { LGNC.Entity.Error(from: $0.getErrorTuple()) }
                        )
                    }
                )
            )
        }

        public convenience init(from response: CanonicalContractResponse) {
            self.init(from: response.response, meta: response.meta, success: true)
        }

        public convenience init(from entity: Entity, meta: Meta = [:], success: Bool = true) {
            self.init(result: entity, errors: [:], meta: meta, success: success)
        }

        public static func initFromResponse<T: ContractEntity>(
            from dictionary: Entita.Dict,
            type: T.Type
        ) async throws -> Result {
            let errors: [String: [LGNC.Entity.Error]]? = try? (self.extract(param: "errors", from: dictionary) as [String: [LGNC.Entity.Error]])
            let result: Entita.Dict?? = try? (self.extract(param: "result", from: dictionary, isOptional: true) as Entita.Dict?)
            let meta: Meta? = try? (self.extract(param: "meta", from: dictionary) as Meta)
            let success: Bool? = try? (self.extract(param: "success", from: dictionary) as Bool)

            let validatorClosures: [String: ValidationClosure] = [
                "result": {
                    guard let result = result else {
                        throw Validation.Error.MissingValue()
                    }
                    if result == nil {
                        throw Validation.Error.SkipMissingOptionalValueValidators()
                    }
                },
                "errors": {
                    guard let _ = errors else {
                        throw Validation.Error.MissingValue()
                    }
                },
                "meta": {
                    guard let _ = meta else {
                        throw Validation.Error.MissingValue()
                    }
                },
                "success": {
                    guard let _ = success else {
                        throw Validation.Error.MissingValue()
                    }
                },
            ]

            let __validationErrors = await self.reduce(closures: validatorClosures)
            guard __validationErrors.isEmpty else {
                throw LGNC.E.DecodeError(__validationErrors)
            }

            let __result: T?
            if let result = result?.flattened as? Entita.Dict {
                __result = try await T.initWithValidation(from: result)
            } else {
                __result = nil
            }

            return self.init(
                result: __result,
                errors: errors!,
                meta: meta!,
                success: success!
            )
        }

        public static func initWithValidation(from dictionary: Entita.Dict) async throws -> Result {
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

            return self.init(
                result: _result,
                errors: _errors,
                meta: _meta,
                success: _success
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

        public convenience init(from tuple: ErrorTuple) {
            self.init(message: tuple.message, code: tuple.code)
        }

        public convenience init(from error: ClientError) {
            self.init(from: error.getErrorTuple())
        }

        public func getErrorTuple() -> ErrorTuple {
            return (code: code, message: message)
        }

        public static func initWithValidation(from dictionary: Entita.Dict) async throws -> Error {
            var errors: [String: [ValidatorError]] = [
                "message": [],
                "code": [],
            ]

            var _message: String!
            var _code: Int!

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

            return self.init(message: _message, code: _code)
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

        public static func initWithValidation(from _: Entita.Dict) async throws -> Empty {
            self.init()
        }

        public convenience init(from _: Entita.Dict) throws {
            self.init()
        }

        public func getDictionary() throws -> Entita.Dict {
            return [:]
        }
    }

    final class WebSocketEvent: ContractEntity {
        public let kind: String
        public let body: Entity

        init(kind: String, body: Entity) {
            self.kind = kind
            self.body = body
        }

        public convenience init(from dictionary: Entita.Dict) throws {
            self.init(
                kind: try Result.extract(param: "kind", from: dictionary),
                body: try Result.extract(param: "body", from: dictionary)
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
