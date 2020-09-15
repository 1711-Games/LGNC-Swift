import Entita
import LGNCore
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension Service {
    static func startServerHTTP(
        at target: LGNCore.Address? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) -> EventLoopFuture<AnyServer> {
        let address: LGNCore.Address

        do {
            try self.validate(transport: .HTTP)

            address = try self.unwrapAddress(from: target)

            try self.checkGuarantees()
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }

        let server = LGNC.HTTP.Server(
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
                    let headers: [(name: String, value: String)] = [
                        ("Content-Language", context.locale.rawValue)
                    ]

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

        return server.bind(to: address).map { server }
    }
}
