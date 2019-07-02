import Entita
import Foundation
import LGNS

public extension Contracts {}

public protocol ContractEntity: Entity {
    static func initWithValidation(from dictionary: Entita.Dict, requestInfo: LGNCore.RequestInfo) -> Future<Self>
}

public extension ContractEntity {
    // deprecated
    static func reduce(
        validators: [String: [Future<(String, ValidatorError?)>]],
        on eventLoop: EventLoop
    ) -> Future<[String: [ValidatorError]]> {
        return Future<[String: [ValidatorError]]>
            .reduce(
                into: Dictionary(uniqueKeysWithValues: validators.keys.map { ($0, []) }),
                validators.values.reduce(into: []) { $0.append(contentsOf: $1) },
                on: eventLoop
            ) { carry, result in
                if let error = result.1 {
                    carry[result.0]!.append(error)
                }
            }.map {
                $0.filter { $0.value.count > 0 }
            }
    }

    static func reduce(
        validators: [String: Future<Void>],
        requestInfo: LGNCore.RequestInfo
        ) -> Future<[String: ValidatorError]> {
        return Future.reduce(
            into: [:],
            validators.map { (key: String, future: Future<Void>) -> Future<(String, ValidatorError?)> in
                future
                    .map { nil }
                    .flatMapErrorThrowing { (error: Error) -> ValidatorError? in
                        if error is Validation.Error.SkipMissingOptionalValueValidators {
                            return nil
                        }
                        if error is Entita.E {
                            return Validation.Error.MissingValue(requestInfo.locale)
                        }
                        if !(error is ValidatorError) {
                            requestInfo.logger.error("Unknown error while parsing contract entity: \(error)")
                            return Validation.Error.UnknownError(requestInfo.locale)
                        }
                        return (error as! ValidatorError)
                    }
                    .map { maybeError in (key, maybeError) }
            },
            on: requestInfo.eventLoop,
            { carry, resultTuple in
                if let error = resultTuple.1 {
                    carry[resultTuple.0] = error
                }
        }
        )
    }
}
