import Foundation
import LGNCore
import LGNS

import _Concurrency

public typealias ValidationClosure = () async throws -> Void

public typealias ErrorTuple = (code: Int, message: String)

public protocol ValidatorErrorRepresentable: ClientError {
    func getErrorTuple() -> ErrorTuple
}

public protocol CallbackWithAllowedValuesRepresentable {
    associatedtype InputValue
}

public protocol ValidatorError: ValidatorErrorRepresentable {
    var code: Int { get }
    var message: String { get }
}

public extension ValidatorError {
    func getErrorTuple() -> ErrorTuple {
        (code: code, message: message)
    }
}

public enum Validation {
    public enum Error {}
}

internal extension String {
    @usableFromInline
    func _t(
        _ interpolations: [String: Any] = [:],
        _ locale: LGNCore.i18n.Locale = LGNCore.Context.current.locale
    ) -> String {
        LGNCore.i18n.tr(self, locale, interpolations)
    }
}

public extension Validation.Error {
    struct UnknownError: ValidatorError {
        public let code: Int = 400
        public let message: String

        public init(message: String = "Unknown error") {
            self.message = message._t()
        }
    }

    struct InvalidType: ValidatorError {
        public let code: Int = 412
        public let message: String

        public init(message: String = "Type mismatch") {
            self.message = message._t()
        }
    }

    struct SkipMissingOptionalValueValidators: ValidatorError {
        public let code: Int = 200
        public let message: String = "Skip all validators"

        public init() {}
    }

    struct MissingValue: ValidatorError {
        public let code: Int
        public let message: String

        public init(message: String = "Value missing", code: Int = 412) {
            self.message = message._t()
            self.code = code
        }
    }
}

public protocol Validator {
    /// This function VERY SHOULD throw `ValidatorError`
    func validate(_ input: Any) async throws
}

public extension Validation {
    struct Regexp: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let pattern: String
        public let message: String

        public init(pattern: String, message: String = "Invalid value") {
            self.pattern = pattern
            self.message = message
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? String else {
                throw Validation.Error.InvalidType()
            }
            guard value.range(of: pattern, options: .regularExpression) != nil else {
                throw Error(message: self.message._t())
            }
        }
    }

    struct NotEmpty: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let message: String

        public init(message: String = "Value missing") {
            self.message = message
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? String else {
                throw Validation.Error.InvalidType()
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Error(message: self.message._t())
            }
        }
    }

    struct UUID: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let message: String

        public init(message: String = "Invalid value") {
            self.message = message
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? String else {
                throw Validation.Error.InvalidType()
            }
            guard let _ = Foundation.UUID(uuidString: value) else {
                throw Error(message: self.message._t())
            }
        }
    }

    struct In<T: Equatable>: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let allowedValues: [T]
        public let message: String

        public init(allowedValues: [T], message: String = "Invalid value") {
            self.allowedValues = allowedValues
            self.message = message
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? T else {
                throw Validation.Error.InvalidType()
            }
            guard allowedValues.contains(value) else {
                throw Error(message: self.message._t())
            }
        }
    }

    struct Length {
        public struct Error: ValidatorError {
            public let code: Int = 416
            public let message: String
        }

        public struct Min: Validator {
            public let length: Int
            public let message: String

            public init(length: Int, message: String = "Value must be at least {Length} characters long") {
                self.length = length
                self.message = message
            }

            public func validate(_ input: Any) async throws {
                guard let value = input as? String else {
                    throw Validation.Error.InvalidType()
                }
                guard value.count >= length else {
                    throw Length.Error(message: self.message._t(["Length": self.length]))
                }
            }
        }

        public struct Max: Validator {
            public let length: Int
            public let message: String

            public init(length: Int, message: String = "Value must be at most {Length} characters long") {
                self.length = length
                self.message = message
            }

            public func validate(_ input: Any) async throws {
                guard let value = input as? String else {
                    throw Validation.Error.InvalidType()
                }
                guard value.count <= length else {
                    throw Length.Error(message: self.message._t(["Length": self.length]))
                }
            }
        }
    }

    struct Identical: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 416
            public let message: String
        }

        public let right: String
        public let message: String

        public init(right: String, message: String = "Fields must be identical") {
            self.right = right
            self.message = message
        }

        public func validate(_ input: Any) async throws {
            guard let left = input as? String else {
                throw Validation.Error.InvalidType()
            }
            guard left == right else {
                throw Error(message: self.message._t())
            }
        }
    }

    struct Date: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let format: String
        public let message: String

        public init(format: String = "yyyy-MM-dd kk:mm:ss.SSSSxxx", message: String? = nil) {
            self.format = format
            self.message = message ?? "Invalid date format (valid format: \(format))"
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? String else {
                throw Validation.Error.InvalidType()
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = format
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            guard let _ = dateFormatter.date(from: value) else {
                throw Error(message: self.message._t())
            }
        }
    }

    struct Callback<Value>: Validator {
        public typealias Callback = (Value) async throws -> [ErrorTuple]?
        public typealias CallbackWithSingleError = (Value) async throws -> ErrorTuple?

        public struct Error: ValidatorError {
            public let code: Int
            public let message: String
        }

        public let callback: Callback

        public init(callback: @escaping Callback) {
            self.callback = callback
        }

        public init(callback: @escaping CallbackWithSingleError) {
            self.init { (value) -> [ErrorTuple]? in
                if let result = try await callback(value) {
                    return [result]
                }
                return nil
            }
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? Value else {
                throw Validation.Error.InvalidType()
            }
            guard let errors = try await self.callback(value) else {
                return
            }
            throw LGNC.E.MultipleFieldDecodeError(
                errors.map { code, message in Error(code: code, message: message._t()) }
            )
        }
    }

    struct CallbackWithAllowedValues<
        AllowedValues: CallbackWithAllowedValuesRepresentable & ValidatorErrorRepresentable
    >: Validator {
        public typealias Callback = (AllowedValues.InputValue) async throws -> AllowedValues?

        public struct Error: ValidatorError {
            public let message: String
            public let code: Int
        }

        public let callback: Callback

        public init(callback: @escaping Callback) {
            self.callback = callback
        }

        public func validate(_ input: Any) async throws {
            guard let value = input as? AllowedValues.InputValue else {
                throw Validation.Error.InvalidType()
            }
            guard let error = try await self.callback(value) else {
                return
            }
            let errorTuple = error.getErrorTuple()
            throw Error(message: errorTuple.message._t(), code: errorTuple.code)
        }
    }

    static func cumulative(_ validationClosures: [ValidationClosure]) async throws {
        var errors: [ValidatorError] = []

        for closure in validationClosures {
            do {
                try await closure()
            } catch {
                if let error = error as? ValidatorError {
                    errors.append(error)
                } else if case let LGNC.E.MultipleFieldDecodeError(multipleErrors) = error {
                    errors.append(contentsOf: multipleErrors)
                } else {
                    throw error
                }
            }
        }

        if errors.count > 0 {
            throw LGNC.E.MultipleFieldDecodeError(errors)
        }
    }
}
