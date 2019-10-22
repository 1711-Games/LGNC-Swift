import Entita
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension Service {
    static func serveLGNS(
        at target: LGNS.Server.BindTo? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1),
        promise: PromiseVoid? = nil
    ) throws {
        try validate(transport: .LGNS)

        let address = try unwrapAddress(from: target)

        try checkGuarantees()

        let server = LGNS.Server(
            cryptor: cryptor,
            requiredBitmask: requiredBitmask,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { request, info in
            info.logger.debug("Serving request at LGNS URI '\(request.URI)'")
            do {
                return self.executeContract(
                    URI: request.URI,
                    dict: try request.unpackPayload(),
                    context: info
                ).map {
                    do {
                        return request.getLikeThis(
                            payload: try $0.getDictionary().pack(to: request.contentType)
                        )
                    } catch {
                        info.logger.error("Could not pack entity to \(request.contentType): \(error)")
                        return request.getLikeThis(payload: LGNP.ERROR_RESPONSE)
                    }
                }
            } catch {
                return info.eventLoop.makeFailedFuture(error)
            }
        }

        try server.serve(at: address, promise: promise)
    }
}
