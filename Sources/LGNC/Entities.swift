import Entita
import Foundation
import LGNS

/// A type erased contract entity. Must know how to init itself with validation.
public protocol ContractEntity: Entity {
    /// Returns a future of initiated self from given dictionary and context, or an error if initialization failed due to malformed request or validation failure.
    static func initWithValidation(from dictionary: Entita.Dict, context: LGNCore.Context) -> EventLoopFuture<Self>

    static var hasCookieFields: Bool { get }
}

public extension ContractEntity {
    static var hasCookieFields: Bool { false }

    /// An internal method for performing all previously setup validations
    @inlinable
    static func reduce(
        validators: [String: EventLoopFuture<Void>],
        context: LGNCore.Context
    ) -> EventLoopFuture<[String: [ValidatorError]]> {
        EventLoopFuture.reduce(
            into: [:],
            validators.map { (key: String, future: EventLoopFuture<Void>) in
                future
                    .map { nil }
                    .flatMapErrorThrowing { (error: Error) -> [ValidatorError]? in
                        if error is Validation.Error.SkipMissingOptionalValueValidators {
                            return nil
                        }
                        if error is Entita.E {
                            return [Validation.Error.MissingValue(context.locale)]
                        }
                        if case let LGNC.E.MultipleFieldDecodeError(errors) = error {
                            return errors
                        }
                        if let error = error as? ValidatorError {
                            return [error]
                        }
                        context.logger.error("Unknown error while parsing contract entity: \(error)")
                        return [Validation.Error.UnknownError(context.locale)]
                    }
                    .map { maybeError in (key, maybeError) }
            },
            on: context.eventLoop,
            { (carry: inout [String: [ValidatorError]], resultTuple: (String, [ValidatorError]?)) in
                if let errors = resultTuple.1 {
                    carry[resultTuple.0] = errors
                }
            }
        )
    }

    static func ensureNecessaryItems(in dictionary: Entita.Dict, necessaryItems: [String]) -> Error? {
        let inputSet = Set<String>(dictionary.keys)
        let diff = inputSet.subtracting(necessaryItems)

        if diff.count == 0 {
            return nil
        }

        return LGNC.ContractError.ExtraFieldsInRequest(Array(diff).sorted())
    }

    static func extractCookie(
        param dictKey: String,
        from dictionary: Entita.Dict,
        context: LGNCore.Context
    ) throws -> LGNC.Entity.Cookie? {
        /// We should not perform "either dictionary or meta" check here,
        /// because when contract responses with a cookie,
        /// and it's ALSO transparently set to response meta, LGNC client,
        /// who requested the contract, would fail, because cookie
        /// is present both in response and meta, which, as you might imagine,
        /// is completely normal.

        if let value = context.meta[LGNC.HTTP.COOKIE_META_KEY_PREFIX + dictKey] {
            return LGNC.Entity.Cookie(name: dictKey, value: value)
        }

        if let rawCookie = dictionary[dictKey] as? Entita.Dict {
            return try LGNC.Entity.Cookie(from: rawCookie)
        }

        return nil
    }
}
