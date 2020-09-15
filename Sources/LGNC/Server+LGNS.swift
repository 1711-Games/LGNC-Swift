import Entita
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension Service {
    static func startServerLGNS(
        at target: LGNCore.Address? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1)
    ) -> EventLoopFuture<AnyServer> {
        let address: LGNCore.Address

        do {
            try self.validate(transport: .LGNS)
            try self.validate(controlBitmask: requiredBitmask)

            address = try self.unwrapAddress(from: target)

            try self.checkGuarantees()
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }

        let server = LGNS.Server(
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

        return server.bind(to: address).map { server }
    }
}
