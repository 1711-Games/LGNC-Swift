import Entita
import Foundation
import LGNS

/// A type erased contract entity. Must know how to init itself with validation.
public protocol ContractEntity: Entity {
    /// Returns a future of initiated self from given dictionary and context, or an error if initialization failed due to malformed request or validation failure.
    static func initWithValidation(from dictionary: Entita.Dict, context: LGNCore.Context) -> EventLoopFuture<Self>
}

public extension ContractEntity {
    /// An internal method for performing all previously setup validations
    @inlinable
    static func reduce(
        validators: [String: EventLoopFuture<Void>],
        context: LGNCore.Context
    ) -> EventLoopFuture<[String: ValidatorError]> {
        EventLoopFuture.reduce(
            into: [:],
            validators.map { (key: String, future: EventLoopFuture<Void>) -> EventLoopFuture<(String, ValidatorError?)> in
                future
                    .map { nil }
                    .flatMapErrorThrowing { (error: Error) -> ValidatorError? in
                        if error is Validation.Error.SkipMissingOptionalValueValidators {
                            return nil
                        }
                        if error is Entita.E {
                            return Validation.Error.MissingValue(context.locale)
                        }
                        if !(error is ValidatorError) {
                            context.logger.error("Unknown error while parsing contract entity: \(error)")
                            return Validation.Error.UnknownError(context.locale)
                        }
                        return (error as! ValidatorError)
                    }
                    .map { maybeError in (key, maybeError) }
            },
            on: context.eventLoop,
            { carry, resultTuple in
                if let error = resultTuple.1 {
                    carry[resultTuple.0] = error
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

        return LGNC.ContractError.ExtraFieldsInRequest(.init(diff))
    }
}
