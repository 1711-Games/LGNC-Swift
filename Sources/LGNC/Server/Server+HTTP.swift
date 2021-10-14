import Foundation
import Entita
import LGNCore
import LGNP
import LGNPContenter
import LGNS
import NIO

public struct Redirect: Error {
    public let location: String

    public init(location: String) {
        self.location = location
    }
}

public extension Service {
    static func getServerHTTP(
        at target: LGNCore.Address? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        webSocketRouter: WebsocketRouter.Type? = nil,
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) throws -> AnyServer {
        try self.validate(transport: .HTTP)
        try self.checkGuarantees()

        let GETSafeURLs = self
            .contractMap
            .filter { _, contract in contract.isGETSafe }
            .map { URI, _ in URI.lowercased() }

        let webSocketOnlyContracts = self.webSocketOnlyContracts
        if webSocketRouter == nil && webSocketOnlyContracts.count > 0 {
            LGNCore.Context.current.logger.warning("Starting HTTP server without WebSocket upgrader while there are WebSocket-only contracts: \(webSocketOnlyContracts.map { $0.URI })")
        }

        return LGNC.HTTP.Server(
            address: try self.unwrapAddress(from: target),
            eventLoopGroup: eventLoopGroup,
            service: self,
            webSocketRouter: webSocketRouter,
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
            return try await LGNCore.Context.$current.withValue(context) {
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
                    payload = HTTP.parseQueryParams(String(components.last ?? ""))
                } else if request.isURLEncoded {
                    URI = request.URI
                    payload = HTTP.parseQueryParams(request.body._string)
                } else if let boundary = request.headers.getMultipartBoundary() {
                    context.logger.debug("Parsing multipart formdata")
                    URI = request.URI
                    payload = HTTP.parseMultipartFormdata(boundary: boundary, input: request.body)
                } else {
                    URI = request.URI
                    switch request.contentType {
                    case .JSON: payload = try request.body.unpackFromJSON()
                    case .MsgPack: payload = try request.body.unpackFromMsgPack()
                    default: throw LGNC.E.clientError("Only JSON and MsgPack are allowed", 400)
                    }
                }

                var result = try await self.executeContract(URI: URI, dict: payload)

                var headers: [(name: String, value: String)] = [
                    ("Content-Language", context.locale.rawValue),
                    ("LGNC-UUID", request.uuid.string),
                    ("Content-Type", request.contentType.HTTPHeader), // todo response content-type
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

                let contentType: String
                let body: Bytes

                switch result.result {
                case let .Structured(entity):
                    contentType = request.contentType.HTTPHeader
                    body = try entity.getDictionary().pack(to: request.contentType)
                case let .Binary(file, maybeDisposition):
                    if let disposition = maybeDisposition {
                        headers.append(disposition.header(forFile: file))
                    }
                    contentType = file.contentType.header
                    body = file.body
                }

                headers.append((name: "Content-Type", value: contentType))

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