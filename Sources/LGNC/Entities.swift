import Entita
import Foundation
import LGNS

public extension Contracts {}

public protocol ContractEntity: Entity {
    static func initWithValidation(from dictionary: Entita.Dict, context: LGNCore.Context) -> Future<Self>
}

public extension ContractEntity {
    @inlinable
    static func reduce(
        validators: [String: Future<Void>],
        context: LGNCore.Context
    ) -> Future<[String: ValidatorError]> {
        Future.reduce(
            into: [:],
            validators.map { (key: String, future: Future<Void>) -> Future<(String, ValidatorError?)> in
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
}
