import NIO
import LGNS
import LGNP
import LGNPContenter
import Entita

public extension Service {
    public static func serveLGNS(
        at target: LGNS.Server.BindTo? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1),
        promise: PromiseVoid? = nil
    ) throws {
        try self.validate(transport: .LGNS)

        let address = try self.unwrapAddress(from: target)

        try self.checkGuarantees()

        let server = LGNS.Server(
            cryptor: cryptor,
            requiredBitmask: requiredBitmask,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { request, info in
            LGNCore.log("Serving request at LGNS URI '\(request.URI)'", prefix: request.uuid.string)
            do {
                return self.executeContract(
                    URI: request.URI,
                    uuid: request.uuid.string,
                                                      // what is the reason for it again?
                                                      // vvvvvvvvvvvvvvv
                    payload: try request.unpackPayload()[LGNC.ENTITY_KEY] as? Entita.Dict ?? Entita.Dict(),
                    requestInfo: LGNC.RequestInfo(from: info, transport: .LGNS)
                ).map {
                    do {
                        return request.getLikeThis(
                            payload: try $0.getDictionary().pack(to: request.contentType)
                        )
                    } catch {
                        LGNCore.log("Could not pack entity to \(request.contentType): \(error)", prefix: info.uuid.string)
                        return request.getLikeThis(payload: LGNP.ERROR_RESPONSE)
                    }
                }
            } catch {
                return info.eventLoop.newFailedFuture(error: error)
            }
        }

        try server.serve(at: address, promise: promise)
    }
}
