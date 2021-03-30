import Foundation
import Entita
import LGNCore
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension Service {
    static func getServerHTTP(
        at target: LGNCore.Address? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) throws -> AnyServer {
        try self.validate(transport: .HTTP)
        try self.checkGuarantees()

        let GETSafeURLs = self
            .contractMap
            .filter { _, contract in contract.isGETSafe }
            .map { URI, _ in URI.lowercased() }

        return LGNC.HTTP.Server(
            address: try self.unwrapAddress(from: target),
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { (request: LGNC.HTTP.Request) in
            let context = LGNCore.Context(
                remoteAddr: request.remoteAddr,
                clientAddr: request.remoteAddr,
                userAgent: request.headers["User-Agent"].first ?? "",
                locale: LGNCore.i18n.Locale(
                    maybeLocale: request.headers["Accept-Language"].first,
                    allowedLocales: LGNCore.i18n.translator.allowedLocales
                ),
                uuid: request.uuid,
                isSecure: false,
                transport: .HTTP,
                meta: request.meta,
                eventLoop: request.eventLoop
            )
            context.logger.debug("Serving request at HTTP URI '\(request.URI)'")
            return try await Task.withLocal(\.context, boundTo: context) {
                let payload: Entita.Dict
                let URI: String

                guard !request.URI.isEmpty else {
                    throw LGNC.E.clientError("No URI", 400)
                }

                if request.method == .GET {
                    let components = request.URI.split(separator: "?", maxSplits: 1)
                    URI = String(components[0])
                    guard GETSafeURLs.contains(URI.lowercased()) else {
                        return (
                            body: LGNCore.getBytes("This contract cannot be invoked with GET"),
                            headers: []
                        )
                    }
                    payload = self.parseQueryParams(components.last ?? "")
                } else {
                    URI = request.URI
                    switch request.contentType {
                    case .JSON: payload = try request.body.unpackFromJSON()
                    case .MsgPack: payload = try request.body.unpackFromMsgPack()
                    default: throw LGNC.E.clientError("Only JSON and MsgPack are allowed", 400)
                    }
                }

                let result = try await self.executeContract(URI: URI, dict: payload)

                let body: Bytes
                var headers: [(name: String, value: String)] = [
                    ("Content-Language", context.locale.rawValue),
                    ("LGNC-UUID", request.uuid.string),
                    ("Content-Type", request.contentType.header),
                ]

                var metaContainsHeaders = false
                headers.append(
                    contentsOf: result
                        .meta
                        .filter { k, _ in k.starts(with: LGNC.HTTP.HEADER_PREFIX) }
                        .map { k, value in
                            if metaContainsHeaders == false {
                                metaContainsHeaders = true
                            }

                            let key: String
                            if k.starts(with: LGNC.HTTP.COOKIE_META_KEY_PREFIX) {
                                key = "Set-Cookie"
                            } else {
                                key = k.replacingOccurrences(of: LGNC.HTTP.HEADER_PREFIX, with: "")
                            }
                            return (key, value)
                        }
                )

                if metaContainsHeaders {
                    result.meta = result.meta.filter { k, _ in !k.starts(with: LGNC.HTTP.HEADER_PREFIX) }
                }

                do {
                    body = try result.getDictionary().pack(to: request.contentType)
                } catch {
                    context.logger.critical("Could not pack entity to \(request.contentType): \(error)")
                    body = LGNCore.getBytes("500 Internal Server Error")
                }

                return (body: body, headers: headers)
            }
        }
    }

    static func startServerHTTP(
        at target: LGNCore.Address? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) async throws -> AnyServer {
        let server: AnyServer = try self.getServerHTTP(
            at: target,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        )
        try await server.bind()
        return server
    }
}

fileprivate extension Service {
    static func parseQueryParams(_ input: Substring) -> [String: Any] {
        guard let input = input.removingPercentEncoding else {
            return [:]
        }
        var result: [String: Any] = [:]

        for component in input.split(separator: "&") {
            let kv = component.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else {
                continue
            }

            let key = String(kv[0])
            let value: Any
            let rawValue = String(kv[1])
            if let bool = Bool(rawValue) {
                value = bool
            } else if let int = Int(rawValue) {
                value = int
            } else {
                value = rawValue
            }
            result[key] = value
        }

        return result
    }
}
