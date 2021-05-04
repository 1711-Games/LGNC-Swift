import Entita
import LGNP
import LGNPContenter
import LGNS
import NIO

public extension Service {
    static func validateContract(requiredBitmask: LGNP.Message.ControlBitmask) throws {
        try self.validate(transport: .LGNS)
        try self.validate(controlBitmask: requiredBitmask)
        try self.checkGuarantees()
    }

    static func getLGNSResolver(request: LGNP.Message) async throws -> LGNP.Message? {
        let context = LGNCore.Context.current

        context.logger.debug("Serving request at LGNS URI '\(request.URI)'")

        let result = try await self.executeContract(URI: request.URI, dict: try request.unpackPayload())
        do {
            return request.copied(payload: try result.getDictionary().pack(to: request.contentType))
        } catch {
            context.logger.error("Could not pack entity to \(request.contentType): \(error)")
            return request.copied(payload: LGNP.ERROR_RESPONSE)
        }
    }

    static func getServerLGNS(
        at target: LGNCore.Address? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .minutes(1),
        writeTimeout: TimeAmount = .minutes(1)
    ) throws -> AnyServer {
        try self.validateContract(requiredBitmask: requiredBitmask)

        return LGNS.Server(
            address: try self.unwrapAddress(from: target),
            cryptor: cryptor,
            requiredBitmask: requiredBitmask,
            eventLoopGroup: eventLoopGroup,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout,
            resolver: self.getLGNSResolver(request:)
        )
    }

    static func startServerLGNS(
        at target: LGNCore.Address? = nil,
        cryptor: LGNP.Cryptor,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount),
        requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
        readTimeout: TimeAmount = .seconds(1),
        writeTimeout: TimeAmount = .seconds(1)
    ) async throws -> AnyServer {
        let server: AnyServer = try self.getServerLGNS(
            at: target,
            cryptor: cryptor,
            eventLoopGroup: eventLoopGroup,
            requiredBitmask: requiredBitmask,
            readTimeout: readTimeout,
            writeTimeout: writeTimeout
        )
        try await server.bind()
        return server
    }
}
