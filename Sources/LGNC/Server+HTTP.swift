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
            do {
                let payload: Entita.Dict
                switch request.contentType {
                case .JSON: payload = try request.body.unpackFromJSON()
                case .MsgPack: payload = try request.body.unpackFromMsgPack()
                default: throw LGNC.E.clientError("Only JSON and MsgPack are allowed", 400)
                }
                return self.executeContract(
                    URI: request.URI,
                    dict: payload,
                    context: context
                ).map {
                    let body: Bytes
                    var headers: [(name: String, value: String)] = [
                        ("Content-Language", context.locale.rawValue)
                    ]

                    headers.append(
                        contentsOf: $0
                            .meta
                            .filter { k, _ in k.starts(with: LGNC.HTTP.COOKIE_META_KEY_PREFIX) }
                            .map { _, v in ("Set-Cookie", v) }
                    )

                    do {
                        body = try $0.getDictionary().pack(to: request.contentType)
                    } catch {
                        context.logger.critical("Could not pack entity to \(request.contentType): \(error)")
                        body = LGNCore.getBytes("500 Internal Server Error")
                    }

                    return (body: body, headers: headers)
                }
            } catch {
                return request.eventLoop.makeFailedFuture(error)
            }
        }
    }

    static func startServerHTTP(
        at target: LGNCore.Address? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) -> EventLoopFuture<AnyServer> {
        do {
            let server: AnyServer = try self.getServerHTTP(
                at: target,
                eventLoopGroup: eventLoopGroup,
                readTimeout: readTimeout,
                writeTimeout: writeTimeout
            )
            return server.bind().map { server }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}
