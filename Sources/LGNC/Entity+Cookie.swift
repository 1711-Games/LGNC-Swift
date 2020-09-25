import Foundation
import LGNCore
import Entita
import AsyncHTTPClient

public extension LGNC.Entity {
    typealias Cookie = HTTPClient.Cookie
}

internal extension Array where Element == String {
    func parseCookies() -> [String: String] {
        .init(
            self.compactMap { cookie in
                let parts = cookie.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    return nil
                }
                return (String(LGNC.HTTP.COOKIE_META_KEY_PREFIX + parts[0]), cookie)
            },
            uniquingKeysWith: { $1 }
        )
    }
}

extension LGNC.Entity.Cookie: ContractEntity {
    public static func initWithValidation(
        from dictionary: Entita.Dict, context: LGNCore.Context
    ) -> EventLoopFuture<Self> {
        let eventLoop = context.eventLoop

        if let error = self.ensureNecessaryItems(
            in: dictionary,
            necessaryItems: [
                "name",
                "value",
                "path",
                "domain",
                "expires",
                "maxAge",
                "httpOnly",
                "secure",
            ]
        ) {
            return eventLoop.makeFailedFuture(error)
        }

        let name: String? = try? (self.extract(param: "name", from: dictionary) as String)
        let value: String? = try? (self.extract(param: "value", from: dictionary) as String)
        let path: String? = try? (self.extract(param: "path", from: dictionary) as String)
        let domain: String?? = try? (self.extract(param: "domain", from: dictionary, isOptional: true) as String?)
        let expires: String?? = try? (self.extract(param: "expires", from: dictionary, isOptional: true) as String?)
        let maxAge: Int?? = try? (self.extract(param: "maxAge", from: dictionary, isOptional: true) as Int?)
        let httpOnly: Bool? = try? (self.extract(param: "httpOnly", from: dictionary) as Bool)
        let secure: Bool? = try? (self.extract(param: "secure", from: dictionary) as Bool)

        let validatorFutures: [String: EventLoopFuture<Void>] = [
            "name": eventLoop
                .submit {
                    guard let _ = name else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                },
            "value": eventLoop
                .submit {
                    guard let _ = value else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                },
            "path": eventLoop
                .submit {
                    guard let _ = path else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                },
            "domain": eventLoop
                .submit {
                    guard let domain = domain else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                    if domain == nil {
                        throw Validation.Error.SkipMissingOptionalValueValidators()
                    }
                },
            "expires": eventLoop
                .submit {
                    guard let expires = expires else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                    if expires == nil {
                        throw Validation.Error.SkipMissingOptionalValueValidators()
                    }
                }
                .flatMap {
                    if let expires = expires, let error = Validation.Date(format: "E, d MMM yyyy HH:mm:ss zzz").validate(expires!, context.locale) {
                        return eventLoop.makeFailedFuture(error)
                    }
                    return eventLoop.makeSucceededFuture()
                },
            "maxAge": eventLoop
                .submit {
                    guard let maxAge = maxAge else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                    if maxAge == nil {
                        throw Validation.Error.SkipMissingOptionalValueValidators()
                    }
                },
            "httpOnly": eventLoop
                .submit {
                    guard let _ = httpOnly else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                },
            "secure": eventLoop
                .submit {
                    guard let _ = secure else {
                        throw Validation.Error.MissingValue(context.locale)
                    }
                },
        ]

        return self
            .reduce(validators: validatorFutures, context: context)
            .flatMapThrowing {
                guard $0.count == 0 else {
                    throw LGNC.E.DecodeError($0)
                }

                return self.init(
                    name: name!,
                    value: value!,
                    path: path!,
                    domain: domain!,
                    expires: expires!.flatMap { LGNC.cookieDateFormatter.date(from: $0) },
                    maxAge: maxAge!,
                    httpOnly: httpOnly!,
                    secure: secure!
                )
            }
    }

    public init(from dictionary: Entita.Dict) throws {
        let rawDate: String? = try Self.extract(param: "expires", from: dictionary, isOptional: true)

        self.init(
            name: try Self.extract(param: "name", from: dictionary),
            value: try Self.extract(param: "value", from: dictionary),
            path: try Self.extract(param: "path", from: dictionary),
            domain: try Self.extract(param: "domain", from: dictionary, isOptional: true),
            expires: LGNC.cookieDateFormatter.date(from: rawDate ?? ""),
            maxAge: try Self.extract(param: "maxAge", from: dictionary, isOptional: true),
            httpOnly: try Self.extract(param: "httpOnly", from: dictionary),
            secure: try Self.extract(param: "secure", from: dictionary)
        )
    }

    public func getDictionary() throws -> Entita.Dict {
        [
            self.getDictionaryKey("name"): try self.encode(self.name),
            self.getDictionaryKey("value"): try self.encode(self.value),
            self.getDictionaryKey("path"): try self.encode(self.path),
            self.getDictionaryKey("domain"): try self.encode(self.domain),
            self.getDictionaryKey("expires"): try self.encode(self.expires.map { LGNC.cookieDateFormatter.string(from: $0) } ?? ""),
            self.getDictionaryKey("maxAge"): try self.encode(self.maxAge),
            self.getDictionaryKey("httpOnly"): try self.encode(self.httpOnly),
            self.getDictionaryKey("secure"): try self.encode(self.secure),
        ]
    }

    public func getCookieString() throws -> String {
        var result: [String] = ["\(self.name)=\(self.value)"]

        if let expires = self.expires {
            result.append("Expires=\(LGNC.cookieDateFormatter.string(from: expires))")
        }
        if let maxAge = self.maxAge {
            result.append("Max-Age=\(maxAge)")
        }
        if !self.path.isEmpty {
            result.append("Path=\(self.path)")
        }
        if let domain = self.domain {
            result.append("Domain=\(domain)")
        }
        if self.secure {
            result.append("Secure")
        }
        if self.httpOnly {
            result.append("HttpOnly")
        }

        return result.joined(separator: "; ")
    }
}

extension LGNC.Entity.Cookie: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return
           lhs.name     == rhs.name
        && lhs.value    == rhs.value
        && lhs.path     == rhs.path
        && lhs.domain   == rhs.domain
        && lhs.expires  == rhs.expires
        && lhs.maxAge   == rhs.maxAge
        && lhs.httpOnly == rhs.httpOnly
        && lhs.secure   == rhs.secure
    }
}

public extension LGNC.Entity.Meta {
    static func initFrom(cookie: LGNC.Entity.Cookie) throws -> Self {
        var result = Self()

        return try result.appending(cookie: cookie)
    }

    @discardableResult
    mutating func appending(cookie: LGNC.Entity.Cookie) throws -> Self {
        self[LGNC.HTTP.COOKIE_META_KEY_PREFIX + cookie.name] = try cookie.getCookieString()

        return self
    }
}
