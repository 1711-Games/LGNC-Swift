import Entita
import Foundation
import LGNS

public extension Contracts {
}

public protocol ContractEntity: Entity {
    static func initWithValidation(from dictionary: Entita.Dict, requestInfo: LGNCore.RequestInfo) -> Future<Self>
}

public extension ContractEntity {
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
}
