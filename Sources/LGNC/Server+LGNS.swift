import Entita
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension Service {
    static func getServerLGNS(
        at target: LGNCore.Address? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1)
    ) throws -> AnyServer {
        try self.validate(transport: .LGNS)
        try self.validate(controlBitmask: requiredBitmask)
        try self.checkGuarantees()

        return LGNS.Server(
            address: try self.unwrapAddress(from: target),
            cryptor: cryptor,
            requiredBitmask: requiredBitmask,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        ) { request, context in
            context.logger.debug("Serving request at LGNS URI '\(request.URI)'")
            do {
                return self.executeContract(
                    URI: request.URI,
                    dict: try request.unpackPayload(),
                    context: context
                ).map {
                    do {
                        return request.copied(
                            payload: try $0.getDictionary().pack(to: request.contentType)
                        )
                    } catch {
                        context.logger.error("Could not pack entity to \(request.contentType): \(error)")
                        return request.copied(payload: LGNP.ERROR_RESPONSE)
                    }
                }
            } catch {
                return context.eventLoop.makeFailedFuture(error)
            }
        }
    }

    static func startServerLGNS(
        at target: LGNCore.Address? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1)
    ) -> EventLoopFuture<AnyServer> {
        do {
            let server: AnyServer = try self.getServerLGNS(
                at: target,
                cryptor: cryptor,
                eventLoopGroup: eventLoopGroup,
                requiredBitmask: requiredBitmask,
                readTimeout: readTimeout,
                writeTimeout: writeTimeout
            )
            return server.bind().map { server }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}
