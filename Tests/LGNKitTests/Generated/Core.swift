import LGNCore
import Entita
import LGNS
import LGNC
import LGNP
import NIO

public enum Services {
    public enum Shared {}

    public static let list: [String: Service.Type] = [
        "Shop": Shop.self,
        "Auth": Auth.self,
    ]
}

public extension Services.Shared {
    final class Good: ContractEntity {
        public static let keyDictionary: [String: String] = [:]

        public let ID: Int
        public let name: String
        public let description: String?
        public let price: Float

        public init(ID: Int, name: String, description: String? = nil, price: Float) {
            self.ID = ID
            self.name = name
            self.description = description
            self.price = price
        }

        public static func initWithValidation(
            from dictionary: Entita.Dict, context: LGNCore.Context
        ) -> EventLoopFuture<Good> {
            let eventLoop = context.eventLoop

            let ID: Int? = try? (self.extract(param: "ID", from: dictionary) as Int)
            let name: String? = try? (self.extract(param: "name", from: dictionary) as String)
            let description: String?? = try? (self.extract(param: "description", from: dictionary, isOptional: true) as String?)
            let price: Float? = try? (self.extract(param: "price", from: dictionary) as Float)

            let validatorFutures: [String: EventLoopFuture<Void>] = [
                "ID": eventLoop
                    .submit {
                        guard let _ = ID else {
                            throw Validation.Error.MissingValue(context.locale)
                        }
                    },
                "name": eventLoop
                    .submit {
                        guard let _ = name else {
                            throw Validation.Error.MissingValue(context.locale)
                        }
                    },
                "description": eventLoop
                    .submit {
                        guard let description = description else {
                            throw Validation.Error.MissingValue(context.locale)
                        }
                        if description == nil {
                            throw Validation.Error.SkipMissingOptionalValueValidators()
                        }
                    },
                "price": eventLoop
                    .submit {
                        guard let _ = price else {
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
                        ID: ID!,
                        name: name!,
                        description: description!,
                        price: price!
                    )
                }
        }

        public convenience init(from dictionary: Entita.Dict) throws {
            self.init(
                ID: try Good.extract(param: "ID", from: dictionary),
                name: try Good.extract(param: "name", from: dictionary),
                description: try Good.extract(param: "description", from: dictionary, isOptional: true),
                price: try Good.extract(param: "price", from: dictionary)
            )
        }

        public func getDictionary() throws -> Entita.Dict {
            [
                self.getDictionaryKey("ID"): try self.encode(self.ID),
                self.getDictionaryKey("name"): try self.encode(self.name),
                self.getDictionaryKey("description"): try self.encode(self.description),
                self.getDictionaryKey("price"): try self.encode(self.price),
            ]
        }

    }
}