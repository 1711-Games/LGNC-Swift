import NIO
import LGNS
import LGNP
import LGNPContenter
import Entita

public extension Service {
    public static func serveLGNS(
        at target: LGNS.Server.BindTo = .port(Self.port),
        cryptor: LGNP.Cryptor,
        eventLoopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1),
        promise: PromiseVoid? = nil
    ) throws {
        if LGNC.ALLOW_INCOMPLETE_GUARANTEE == false && self.checkContractsCallbacks() == false {
            throw LGNC.E.serverError("Not all contracts are guaranteed (to disable set LGNC.ALLOW_PART_GUARANTEE to true)")
        }

        let server = try LGNS.Server(
            cryptor: cryptor,
            requiredBitmask: requiredBitmask,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { request, info in
            LGNC.log("Serving request at URI '\(request.URI)'", prefix: request.uuid.string)
            do {
                return self.executeContract(
                    URI: request.URI,
                    uuid: request.uuid.string,
                    payload: try request.unpackPayload()[LGNC.ENTITY_KEY] as? Entita.Dict ?? Entita.Dict(),
                    requestInfo: info
                ).map {
                    do {
                        return request.getLikeThis(
                            payload: try $0.getDictionary().pack(to: request.contentType)
                        )
                    } catch {
                        LGNC.log("Could not pack entity to \(request.contentType): \(error)", prefix: info.uuid)
                        return request.getLikeThis(payload: LGNP.ERROR_RESPONSE)
                    }
                }
            } catch {
                return info.eventLoop.newFailedFuture(error: error)
            }
        }

        try server.serve(at: target, promise: promise)
    }
}
