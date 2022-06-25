import Entita
import Foundation
import LGNS
import LGNLog

/// A type erased contract entity. Must know how to init itself with validation.
public protocol ContractEntity: Entity {
    /// Returns a future of initiated self from given dictionary and context, or an error if initialization failed due to malformed request or validation failure.
    static func initWithValidation(from dictionary: Entita.Dict) async throws -> Self

    static var hasCookieFields: Bool { get }
}

public extension ContractEntity {
    static var hasCookieFields: Bool { false }

    /// An internal method for performing all previously setup validations
    @inlinable
    static func reduce(closures: [String: ValidationClosure]) async -> [String: [ValidatorError]] {
        var result: [String: [ValidatorError]] = [:]

        for (key, closure) in closures {
            let maybeErrors: [ValidatorError]? = await {
                do {
                    try await closure()
                    return nil
                } catch let error {
                    if error is Validation.Error.SkipMissingOptionalValueValidators {
                        return nil
                    }
                    if error is Entita.E {
                        return [Validation.Error.MissingValue()]
                    }
                    if case let LGNC.E.MultipleFieldDecodeError(errors) = error {
                        return errors
                    }
                    if let error = error as? ValidatorError {
                        return [error]
                    }
                    Logger.current.error("Unknown error while parsing contract entity: \(error)")
                    return [Validation.Error.UnknownError()]
                }
            }()
            guard let errors = maybeErrors else {
                continue
            }
            result[key] = errors
        }

        return result
    }

    static func ensureNecessaryItems(in dictionary: Entita.Dict, necessaryItems: [String]) throws {
        let inputSet = Set<String>(dictionary.keys)
        let diff = inputSet.subtracting(necessaryItems)

        if diff.count == 0 {
            return
        }

        throw LGNC.ContractError.ExtraFieldsInRequest(Array(diff).sorted())
    }

    static func extractCookie(
        param dictKey: String,
        from dictionary: Entita.Dict
    ) async throws -> LGNC.Entity.Cookie? {
        /// We should not perform "either dictionary or meta" check here,
        /// because when contract responses with a cookie,
        /// and it's ALSO transparently set to response meta, LGNC client,
        /// who requested the contract, would fail, because cookie
        /// is present both in response and meta, which, as you might imagine,
        /// is completely normal.

        if let value = LGNCore.Context.current.meta[LGNC.HTTP.COOKIE_META_KEY_PREFIX + dictKey] {
            return LGNC.Entity.Cookie(header: value, defaultDomain: "nil")
        }

        if let rawCookie = dictionary[dictKey] as? Entita.Dict {
            return try LGNC.Entity.Cookie(from: rawCookie)
        }

        return nil
    }
}
