import LGNCore
import NIO
import LGNS
import LGNP
import LGNPContenter
import Entita

public extension LGNP.Message.ContentType {
    public init(from HTTPContentType: LGNC.HTTP.ContentType) {
        switch HTTPContentType {
        case .JSON: self = .JSON
        case .XML: self = .XML
        case .MsgPack: self = .MsgPack
        case .PlainText: self = .PlainText
        }
    }
}

public extension Service {
    public static func serveHTTP(
        at target: LGNS.Server.BindTo? = nil,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1),
        promise: PromiseVoid? = nil
    ) throws {
        try self.validate(transport: .HTTP)

        let address = try self.unwrapAddress(from: target)

        try self.checkGuarantees()

        let server = LGNC.HTTP.Server(
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { request in
            LGNCore.log("Serving request at HTTP URI '\(request.URI)'", prefix: request.uuid.string)
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
                    requestInfo: LGNC.RequestInfo(
                        remoteAddr: request.remoteAddr,
                        clientAddr: request.remoteAddr,
                        userAgent: request.headers["User-Agent"].first ?? "",
                        uuid: request.uuid,
                        isSecure: false,
                        transport: .HTTP,
                        eventLoop: request.eventLoop
                    )
                ).map {
                    do {
                        return try $0.getDictionary().pack(to: LGNP.Message.ContentType(from: request.contentType))
                    } catch {
                        LGNCore.log(
                            "Could not pack entity to \(request.contentType): \(error)",
                            prefix: request.uuid.string
                        )
                        return "500 Internal Server Error".bytes
                    }
                }
            } catch {
                return request.eventLoop.newFailedFuture(error: error)
            }
        }

        try server.serve(at: address, promise: promise)
    }
}
