import Foundation
import LGNCore
import LGNS

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
    @usableFromInline func _t(_ locale: LGNCore.i18n.Locale, _ interpolations: [String: Any] = [:]) -> String {
        LGNCore.i18n.tr(self, locale, interpolations)
    }
}

public extension Validation.Error {
    struct UnknownError: ValidatorError {
        public let code: Int = 400
        public let message: String

        public init(message: String = "Unknown error", _ locale: LGNCore.i18n.Locale) {
            self.message = message._t(locale)
        }
    }

    struct InvalidType: ValidatorError {
        public let code: Int = 412
        public let message: String

        public init(message: String = "Type mismatch", _ locale: LGNCore.i18n.Locale) {
            self.message = message._t(locale)
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

        public init(_ locale: LGNCore.i18n.Locale, message: String = "Value missing", code: Int = 412) {
            self.message = message._t(locale)
            self.code = code
        }
    }
}

public protocol Validator {
    func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError?
    func validate(
        _ input: Any,
        _ locale: LGNCore.i18n.Locale,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<ValidatorError?>
}

public extension Validator {
    func validate(
        _ input: Any,
        _ locale: LGNCore.i18n.Locale,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<ValidatorError?> {
        return eventLoop.makeSucceededFuture(self.validate(input, locale))
    }
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

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType(locale)
            }
            guard value.range(of: pattern, options: .regularExpression) != nil else {
                return Error(message: self.message._t(locale))
            }
            return nil
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

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType(locale)
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return Error(message: self.message._t(locale))
            }
            return nil
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

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType(locale)
            }
            guard let _ = Foundation.UUID(uuidString: value) else {
                return Error(message: self.message._t(locale))
            }
            return nil
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

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            guard let value = input as? T else {
                return Validation.Error.InvalidType(locale)
            }
            guard allowedValues.contains(value) else {
                return Error(message: self.message._t(locale))
            }
            return nil
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

            public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
                guard let value = input as? String else {
                    return Validation.Error.InvalidType(locale)
                }
                guard value.count >= length else {
                    return Length.Error(message: self.message._t(locale, ["Length": self.length]))
                }
                return nil
            }
        }

        public struct Max: Validator {
            public let length: Int
            public let message: String

            public init(length: Int, message: String = "Value must be at most {Length} characters long") {
                self.length = length
                self.message = message
            }

            public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
                guard let value = input as? String else {
                    return Validation.Error.InvalidType(locale)
                }
                guard value.count <= length else {
                    return Length.Error(message: self.message._t(locale, ["Length": self.length]))
                }
                return nil
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

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            guard let left = input as? String else {
                return Validation.Error.InvalidType(locale)
            }
            guard left == right else {
                return Error(message: self.message._t(locale))
            }
            return nil
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

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType(locale)
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = format
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            guard let _ = dateFormatter.date(from: value) else {
                return Error(message: self.message._t(locale))
            }
            return nil
        }
    }

    struct Callback<Value>: Validator {
        public typealias Callback = (Value, EventLoop) -> EventLoopFuture<[ErrorTuple]?>
        public typealias CallbackWithSingleError = (Value, EventLoop) -> EventLoopFuture<ErrorTuple?>

        public struct Error: ValidatorError {
            public let code: Int
            public let message: String
        }

        public let callback: Callback

        public init(callback: @escaping Callback) {
            self.callback = callback
        }

        public init(callback: @escaping CallbackWithSingleError) {
            self.init { (value, eventLoop) -> EventLoopFuture<[ErrorTuple]?> in
                callback(value, eventLoop).map { $0.map { [$0] } }
            }
        }

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            // not relevant here
            nil
        }

        public func validate(
            _ input: Any,
            _ locale: LGNCore.i18n.Locale,
            on eventLoop: EventLoop
        ) -> EventLoopFuture<Swift.Error?> {
            guard let value = input as? Value else {
                return eventLoop.makeSucceededFuture(Validation.Error.InvalidType(locale))
            }
            return self.callback(
                value,
                eventLoop
            ).map {
                guard let errors = $0 else {
                    return nil
                }
                return LGNC.E.MultipleFieldDecodeError(
                    errors.map { code, message in Error(code: code, message: message._t(locale)) }
                )
            }
        }
    }

    struct CallbackWithAllowedValues<
        AllowedValues: CallbackWithAllowedValuesRepresentable & ValidatorErrorRepresentable
    >: Validator {
        public typealias Callback = (AllowedValues.InputValue, EventLoop) -> EventLoopFuture<AllowedValues?>

        public struct Error: ValidatorError {
            public let code: Int
            public let message: String
        }

        public let callback: Callback

        public init(callback: @escaping Callback) {
            self.callback = callback
        }

        public func validate(_ input: Any, _ locale: LGNCore.i18n.Locale) -> ValidatorError? {
            // not relevant here
            nil
        }

        public func validate(
            _ input: Any,
            _ locale: LGNCore.i18n.Locale,
            on eventLoop: EventLoop
        ) -> EventLoopFuture<ValidatorError?> {
            guard let value = input as? AllowedValues.InputValue else {
                return eventLoop.makeSucceededFuture(Validation.Error.InvalidType(locale))
            }
            return self.callback(
                value,
                eventLoop
            ).map {
                guard let error = $0 else {
                    return nil
                }
                let errorTuple = error.getErrorTuple()
                return Error(code: errorTuple.code, message: errorTuple.message._t(locale))
            }
        }
    }

    static func cumulative(
        _ validationFutures: [EventLoopFuture<Void>],
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        EventLoopFuture<Void>
            .whenAllComplete(validationFutures, on: eventLoop)
            .flatMapThrowing { (results: [Result<Void, Swift.Error>]) throws -> Void in
                var errors: [ValidatorError] = []

                for result in results {
                    switch result {
                    case .success: continue
                    case let .failure(error):
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
}
