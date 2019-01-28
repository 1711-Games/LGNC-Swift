import Foundation
import LGNS

public protocol ValidatorErrorRepresentable: ClientError {
    func getErrorTuple() -> (message: String, code: Int)
}

public protocol CallbackWithAllowedValuesRepresentable {
    associatedtype InputValue
}

public protocol ValidatorError: ValidatorErrorRepresentable {
    var code: Int { get }
    var message: String { get }
}

public extension ValidatorError {
    public func getErrorTuple() -> (message: String, code: Int) {
        return (message: message, code: code)
    }
}

public struct Validation {
    public struct Error {
    }
}

public extension Validation.Error {
    public struct InvalidType: ValidatorError {
        public let code: Int = 412
        public let message: String = "Type mismatch"
    }

    public struct MissingValue: ValidatorError {
        public let code: Int
        public let message: String

        public init(message: String = "Value missing", code: Int = 412) {
            self.message = message
            self.code = code
        }
    }
}

public protocol Validator {
    func validate(input: Any) -> ValidatorError?
    func validate(input: Any, on eventLoop: EventLoop) -> Future<ValidatorError?>
}

public extension Validator {
    public func validate(input: Any, on eventLoop: EventLoop) -> Future<ValidatorError?> {
        return eventLoop.newSucceededFuture(result: validate(input: input))
    }
}

public extension Validation {
    public struct Regexp: Validator {
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

        public func validate(input: Any) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType()
            }
            guard value.range(of: pattern, options: .regularExpression) != nil else {
                return Error(message: message)
            }
            return nil
        }
    }

    public struct UUID: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let message: String

        public init(message: String = "Invalid value") {
            self.message = message
        }

        public func validate(input: Any) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType()
            }
            guard let _ = Foundation.UUID(uuidString: value) else {
                return Error(message: message)
            }
            return nil
        }
    }

    public struct In<T: Equatable>: Validator {
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

        public func validate(input: Any) -> ValidatorError? {
            guard let value = input as? T else {
                return Validation.Error.InvalidType()
            }
            guard allowedValues.contains(value) else {
                return Error(message: message)
            }
            return nil
        }
    }

    public enum In2AllowedValues: String {
        case Male
        case Female
        case AttackHelicopter = "Attack helicopter"
    }

    public struct In2<T: RawRepresentable>: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let message: String

        public init(message: String = "Invalid value") {
            self.message = message
        }

        public func validate(input: T.RawValue) -> ValidatorError? {
            guard let _ = T(rawValue: input) else {
                return Error(message: message)
            }
            return nil
        }

        public func validate(input: Any) -> ValidatorError? {
            guard let value = input as? T.RawValue else {
                return Validation.Error.InvalidType()
            }
            return validate(input: value)
        }
    }

    public struct Length {
        public struct Error: ValidatorError {
            public let code: Int = 416
            public let message: String
        }

        public struct Min: Validator {
            public let length: Int
            public let message: String

            public init(length: Int, message: String = "Value must be at least {{VALUE}} characters long") {
                self.length = length
                self.message = message.replacingOccurrences(of: "{{VALUE}}", with: String(length))
            }

            public func validate(input: Any) -> ValidatorError? {
                guard let value = input as? String else {
                    return Validation.Error.InvalidType()
                }
                guard value.count >= length else {
                    return Length.Error(message: message)
                }
                return nil
            }
        }

        public struct Max: Validator {
            public let length: Int
            public let message: String

            public init(length: Int, message: String = "Value must be at most {{VALUE}} characters long") {
                self.length = length
                self.message = message.replacingOccurrences(of: "{{VALUE}}", with: String(length))
            }

            public func validate(input: Any) -> ValidatorError? {
                guard let value = input as? String else {
                    return Validation.Error.InvalidType()
                }
                guard value.count <= length else {
                    return Length.Error(message: message)
                }
                return nil
            }
        }
    }

    public struct Identical: Validator {
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

        public func validate(input: Any) -> ValidatorError? {
            guard let left = input as? String else {
                return Validation.Error.InvalidType()
            }
            guard left == right else {
                return Error(message: message)
            }
            return nil
        }
    }

    public struct Date: Validator {
        public struct Error: ValidatorError {
            public let code: Int = 412
            public let message: String
        }

        public let format: String
        public let message: String

        public init(format: String = "yyyy-MM-dd kk:mm:ss.SSSSxxx", message: String = "Invalid date format") {
            self.format = format
            self.message = "\(message) (valid format: \(format))"
        }

        public func validate(input: Any) -> ValidatorError? {
            guard let value = input as? String else {
                return Validation.Error.InvalidType()
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = format
            guard let _ = dateFormatter.date(from: value) else {
                return Error(message: message)
            }
            return nil
        }
    }

    public struct Callback<Value>: Validator {
        public typealias Callback = (Value, EventLoop) -> Future<(message: String, code: Int)?>

        public struct Error: ValidatorError {
            public let code: Int
            public let message: String
        }

        public let callback: Callback

        public init(callback: @escaping Callback) {
            self.callback = callback
        }

        public func validate(input _: Any) -> ValidatorError? {
            // not relevant here
            return nil
        }

        public func validate(input: Any, on eventLoop: EventLoop) -> Future<ValidatorError?> {
            guard let value = input as? Value else {
                return eventLoop.newSucceededFuture(result: Validation.Error.InvalidType())
            }
            return callback(
                value,
                eventLoop
            ).map {
                guard let errorTuple = $0 else {
                    return nil
                }
                return Error(code: errorTuple.code, message: errorTuple.message)
            }
        }
    }

    public struct CallbackWithAllowedValues<AllowedValues: CallbackWithAllowedValuesRepresentable & ValidatorErrorRepresentable>: Validator {
        public typealias Callback = (AllowedValues.InputValue, EventLoop) -> Future<AllowedValues?>

        public struct Error: ValidatorError {
            public let code: Int
            public let message: String
        }

        public let callback: Callback

        public init(callback: @escaping Callback) {
            self.callback = callback
        }

        public func validate(input _: Any) -> ValidatorError? {
            return nil
        }

        public func validate(input: Any, on eventLoop: EventLoop) -> Future<ValidatorError?> {
            guard let value = input as? AllowedValues.InputValue else {
                return eventLoop.newSucceededFuture(result: Validation.Error.InvalidType())
            }
            return callback(
                value,
                eventLoop
            ).map {
                guard let error = $0 else {
                    return nil
                }
                let errorTuple = error.getErrorTuple()
                return Error(code: errorTuple.code, message: errorTuple.message)
            }
        }
    }
}
