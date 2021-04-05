import Foundation
import LGNCore
import Entita
import AsyncHTTPClient

public extension LGNC.Entity {
    typealias Cookie = HTTPClient.Cookie
}

internal extension Array where Element == String {
    func parseCookies() -> [String: String] {
        var result = [String: String]()

        for cookieString in self {
            for cookie in cookieString.split(separator: ";") {
                let parts = cookie.split(separator: "=", maxSplits: 1)
                guard
                    parts.count == 2,
                    let name = parts[0].removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !name.isEmpty,
                    let value = parts[1].removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !value.isEmpty
                else { continue }
                result[LGNC.HTTP.COOKIE_META_KEY_PREFIX + name] = "\(name)=\(value)"
            }
        }

        return result
    }
}

extension LGNC.Entity.Cookie: ContractEntity {
    public static func initWithValidation(from dictionary: Entita.Dict) async throws -> Self {
        try self.ensureNecessaryItems(
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
        )

        let name: String? = try? (self.extract(param: "name", from: dictionary) as String)
        let value: String? = try? (self.extract(param: "value", from: dictionary) as String)
        let path: String? = try? (self.extract(param: "path", from: dictionary) as String)
        let domain: String?? = try? (self.extract(param: "domain", from: dictionary, isOptional: true) as String?)
        let expires: String?? = try? (self.extract(param: "expires", from: dictionary, isOptional: true) as String?)
        let maxAge: Int?? = try? (self.extract(param: "maxAge", from: dictionary, isOptional: true) as Int?)
        let httpOnly: Bool? = try? (self.extract(param: "httpOnly", from: dictionary) as Bool)
        let secure: Bool? = try? (self.extract(param: "secure", from: dictionary) as Bool)

        let validatorClosures: [String: ValidationClosure] = [
            "name": {
                guard let _ = name else {
                    throw Validation.Error.MissingValue()
                }
            },
            "value": {
                guard let _ = value else {
                    throw Validation.Error.MissingValue()
                }
            },
            "path": {
                guard let _ = path else {
                    throw Validation.Error.MissingValue()
                }
            },
            "domain": {
                guard let domain = domain else {
                    throw Validation.Error.MissingValue()
                }
                if domain == nil {
                    throw Validation.Error.SkipMissingOptionalValueValidators()
                }
            },
            "expires": {
                try await { () async throws -> Void in
                    guard let expires = expires else {
                        throw Validation.Error.MissingValue()
                    }
                    if expires == nil {
                        throw Validation.Error.SkipMissingOptionalValueValidators()
                    }
                }()
                try await { () async throws -> Void in
                    if let expires = expires {
                        try await Validation.Date(format: "E, d MMM yyyy HH:mm:ss zzz").validate(expires!)
                    }
                }()
            },
            "maxAge": {
                guard let maxAge = maxAge else {
                    throw Validation.Error.MissingValue()
                }
                if maxAge == nil {
                    throw Validation.Error.SkipMissingOptionalValueValidators()
                }
            },
            "httpOnly": {
                guard let _ = httpOnly else {
                    throw Validation.Error.MissingValue()
                }
            },
            "secure": {
                guard let _ = secure else {
                    throw Validation.Error.MissingValue()
                }
            },
        ]

        let __validationErrors = await self.reduce(closures: validatorClosures)
        guard __validationErrors.isEmpty else {
            throw LGNC.E.DecodeError(__validationErrors)
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
        guard let name = self.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw LGNC.E.serverError("Could not percent encode cookie name of cookie \(self)")
        }
        guard let value = self.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw LGNC.E.serverError("Could not percent encode cookie value of cookie \(self)")
        }

        var result: [String] = ["\(name)=\(value)"]

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

    static func initFrom(cookies: [LGNC.Entity.Cookie]) throws -> Self {
        var result = Self()

        try cookies.forEach { cookie in try result.appending(cookie: cookie) }

        return result
    }

    @discardableResult
    mutating func appending(cookie: LGNC.Entity.Cookie) throws -> Self {
        self[LGNC.HTTP.COOKIE_META_KEY_PREFIX + cookie.name] = try cookie.getCookieString()

        return self
    }
}

public extension LGNC.Entity.Cookie {
    init(_ value: String) {
        self.init(
            name: "",
            value: value,
            path: "",
            domain: nil,
            expires: nil,
            maxAge: nil,
            httpOnly: false,
            secure: false
        )
    }
}
