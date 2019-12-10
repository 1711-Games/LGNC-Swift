/**
 * This file has been autogenerated by LGNC assembler on 2019-12-10 14:48:57.174647.
 * All changes will be lost on next assembly.
 */

import Entita
import Foundation
import LGNC
import LGNCore
import LGNP
import LGNS
import NIO

public extension Services {
    enum Shop: Service {
        public enum Contracts {}

        public static let transports: [LGNCore.Transport: Int] = [
            .LGNS: 27021,
            .HTTP: 8080,
        ]

        public static let info: [String: String] = [
            "baz": "sas",
        ]
        public static var guaranteeStatuses: [String: Bool] = [
            Contracts.Goods.URI: Contracts.Goods.isGuaranteed,
        ]

        public static let contractMap: [String: AnyContract.Type] = [
            Contracts.Goods.URI: Contracts.Goods.self,
        ]

        public static let keyDictionary: [String: Entita.Dict] = [
            "Goods": [
                "Request": Contracts.Goods.Request.keyDictionary,
                "Response": Contracts.Goods.Response.keyDictionary,
            ],
        ]
    }
}

public extension Services.Shop.Contracts {
    typealias Empty = Services.Shared.Empty
    typealias Good = Services.Shared.Good

    enum Goods: Contract {
        public typealias ParentService = Services.Shop

        public typealias Request = LGNC.Entity.Empty

        public static let URI = "Goods"
        public static let transports: [LGNCore.Transport] = [.HTTP, .LGNS]
        public static var guaranteeClosure: Optional<Closure> = nil
        public static let contentTypes: [LGNCore.ContentType] = LGNCore.ContentType.allCases

        static let visibility: ContractVisibility = .Private

        public final class Response: ContractEntity {
            public static let keyDictionary: [String: String] = [
                "list": "b",
            ]

            public let list: [Good]

            public init(
                list: [Good]
            ) {
                self.list = list
            }

            public static func initWithValidation(from dictionary: Entita.Dict, context: LGNCore.Context) -> Future<Response> {
                let eventLoop = context.eventLoop

                let list: [Good]? = try? (self.extract(param: "list", from: dictionary) as [Good])

                let validatorFutures: [String: Future<Void>] = [
                    "list": eventLoop.submit {
                        guard let _ = list else {
                            throw Validation.Error.MissingValue(context.locale)
                        }
                    },
                ]

                return self
                    .reduce(validators: validatorFutures, context: context)
                    .flatMapThrowing {
                        guard $0.count == 0 else {
                            throw LGNC.E.DecodeError($0.mapValues { [$0] })
                        }

                        return self.init(
                            list: list!
                        )
                    }
            }

            public convenience init(from dictionary: Entita.Dict) throws {
                self.init(
                    list: try Response.extract(param: "list", from: dictionary)
                )
            }

            public func getDictionary() throws -> Entita.Dict {
                [
                    self.getDictionaryKey("list"): try self.encode(self.list),
                ]
            }
        }
    }
}