import Entita
import LGNCore
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension LGNP.Message.ContentType {
    init(from HTTPContentType: LGNC.HTTP.ContentType) {
        switch HTTPContentType {
        case .JSON: self = .JSON
        case .XML: self = .XML
        case .MsgPack: self = .MsgPack
        case .PlainText: self = .PlainText
        }
    }
}

public extension Service {
    static func serveHTTP(
        at target: LGNS.Server.BindTo? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1),
        promise: PromiseVoid? = nil
    ) throws {
        try validate(transport: .HTTP)

        let address = try unwrapAddress(from: target)

        try checkGuarantees()

        let server = LGNC.HTTP.Server(
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { request in
            let requestInfo = LGNCore.RequestInfo(
                remoteAddr: request.remoteAddr,
                clientAddr: request.remoteAddr,
                userAgent: request.headers["User-Agent"].first ?? "",
                locale: LGNCore.Translation.Locale(request.headers["Accept-Language"].first),
                uuid: request.uuid,
                isSecure: false,
                transport: .HTTP,
                eventLoop: request.eventLoop
            )
            requestInfo.logger.debug("Serving request at HTTP URI '\(request.URI)'")
            do {
                let payload: Entita.Dict
                switch request.contentType {
                case .JSON: payload = try request.body.unpackFromJSON()
                case .MsgPack: payload = try request.body.unpackFromMsgPack()
                default: throw LGNC.E.clientError("Only JSON and MsgPack are allowed", 400)
                }
                return self.executeContract(
                    URI: request.URI,
                    uuid: request.uuid,
                    payload: payload,
                    requestInfo: requestInfo
                ).map {
                    do {
                        return try $0.getDictionary().pack(to: LGNP.Message.ContentType(from: request.contentType))
                    } catch {
                        requestInfo.logger.critical("Could not pack entity to \(request.contentType): \(error)")
                        return "500 Internal Server Error".bytes
                    }
                }
            } catch {
                return request.eventLoop.makeFailedFuture(error)
            }
        }

        try server.serve(at: address, promise: promise)
    }
}
