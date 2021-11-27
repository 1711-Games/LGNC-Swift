import Foundation
import AsyncHTTPClient
import NIOHTTP1
import LGNCore
import Entita
import LGNP
import LGNS
import NIO
import LGNLog

public extension LGNC {
    enum Client {}
}

public extension LGNC.Client {
    enum E: Error {
        case Noop(String)
        case UnsupportedTransport(LGNCore.Transport)
        case PackError(String)
        case UnpackError(String)
        case EmptyResponse
    }
}

/// A type erased LGNC client
public protocol LGNCClient {
    var eventLoopGroup: EventLoopGroup { get }

    /// Sends a request to a specific contract at given address.
    /// If transport is not specified, preferred contract transport is used.
    func send<C: Contract>(
        contract: C.Type,
        payload: Bytes,
        at address: LGNCore.Address,
        context: LGNCore.Context
    ) async throws -> Bytes
}

public extension LGNCClient {
    func log(transport: LGNCore.Transport, address: LGNCore.Address, URI: String, extra: String = "") {
        let prefix = transport == .LGNS ? transport.rawValue.lowercased() + "://" : ""
        Logger.current.debug("Executing remote contract \(prefix)\(address)/\(URI) \(extra)")
    }
}

extension LGNS.Client: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        payload: Bytes,
        at address: LGNCore.Address,
        context: LGNCore.Context
    ) async throws -> Bytes {
        let requestContext = LGNC.Client.getRequestContext(
            from: context,
            transport: .LGNS,
            eventLoop: context.eventLoop
        )

        self.log(transport: .LGNS, address: address, URI: C.URI)

        return try await self
            .singleRequest(
                at: address,
                with: LGNP.Message(
                    URI: C.URI,
                    payload: payload,
                    meta: LGNC.getPackedMeta(from: requestContext, clientID: requestContext.clientID),
                    controlBitmask: self.controlBitmask,
                    msid: requestContext.requestID
                ),
                on: context.eventLoop
            )
            .payload
    }
}

extension HTTPClient: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        payload: Bytes,
        at address: LGNCore.Address,
        context: LGNCore.Context
    ) async throws -> Bytes {
        let contentType = C.preferredContentType
        let requestContext = LGNC.Client.getRequestContext(
            from: context,
            transport: .HTTP,
            eventLoop: context.eventLoop
        )

        self.log(transport: .HTTP, address: address, URI: C.URI)

        let request = try HTTPClient.Request(
            url: address.description + "/" + C.URI,
            method: .POST,
            headers: HTTPHeaders([
                ("Content-Type", contentType.type),
                ("Accept-Language", requestContext.locale.rawValue),
            ]),
            body: .data(.init(payload))
        )

        let response = try await self
            .execute(request: request, eventLoop: .delegateAndChannel(on: context.eventLoop))
            .get()

        guard var body = response.body, let bytes = body.readBytes(length: body.readableBytes) else {
            throw LGNC.Client.E.EmptyResponse
        }

        return LGNCore.Context.$current.withValue(
            LGNCore.Context(
                remoteAddr: "127.0.0.1",
                clientAddr: "127.0.0.1",
                userAgent: "AsyncHTTPClient",
                locale: requestContext.locale,
                requestID: LGNCore.RequestID(),
                isSecure: false,
                transport: .HTTP,
                meta: response.headers["Cookie"].parseCookies(),
                eventLoop: context.eventLoop
            )
        ) { bytes } // todo fix
    }
}

public extension LGNC.Client {
    static func getRequestContext(
        from maybeContext: LGNCore.Context?,
        transport: LGNCore.Transport,
        eventLoop: EventLoop
    ) -> LGNCore.Context {
        if let context = maybeContext {
            if transport == context.transport {
                return context
            }

            return context.cloned(transport: transport)
        }

        return LGNCore.Context(
            remoteAddr: "127.0.0.1",
            clientAddr: "127.0.0.1",
            userAgent: "\(self)",
            locale: maybeContext?.locale ?? .enUS,
            requestID: maybeContext?.requestID ?? LGNCore.RequestID(),
            isSecure: transport == .LGNS,
            transport: transport,
            meta: maybeContext?.meta ?? [:],
            eventLoop: eventLoop
        )
    }
}

public extension LGNC.Client {
    /// This client implementation simply executes local contract (therefore one must previously guarantee it) without
    /// going to remote service over network. Useful for local development and testing.
    class Loopback: LGNCClient {
        public let eventLoopGroup: EventLoopGroup

        public init(eventLoopGroup: EventLoopGroup) {
            self.eventLoopGroup = eventLoopGroup
        }

        public func send<C: Contract>(
            contract: C.Type,
            payload: Bytes,
            at address: LGNCore.Address,
            context: LGNCore.Context
        ) async throws -> Bytes {
            self.log(transport: .LGNS, address: address, URI: C.URI, extra: "(loopback)")

            let result = try await C.ParentService.executeContract(
                URI: C.URI,
                dict: try payload.unpack(from: C.preferredContentType)
            )

            let body: Bytes

            switch result.result {
            case let .Structured(entity):
                body = try entity.getDictionary().pack(to: C.preferredContentType)
            case let .Binary(file, _):
                body = file.body
            }

            return body
        }
    }
}

public extension LGNC.Client {
    class Dynamic: LGNCClient {
        public let clientLGNS: LGNS.Client
        public let clientHTTP: HTTPClient

        public let eventLoopGroup: EventLoopGroup

        public var isConnected: Bool {
            self.clientLGNS.isConnected
        }

        public init(
            eventLoopGroup: EventLoopGroup,
            clientLGNS: LGNS.Client,
            clientHTTP: HTTPClient
        ) {
            self.eventLoopGroup = eventLoopGroup
            self.clientLGNS = clientLGNS
            self.clientHTTP = clientHTTP
        }

        deinit {
            assert(!self.isConnected, "You must disconnect Dynamic client manually before deinit")
            try? self.clientHTTP.syncShutdown()
        }

        public func disconnect() async throws {
            try await self.clientLGNS.disconnect()
        }

        public func send<C: Contract>(
            contract: C.Type,
            payload: Bytes,
            at address: LGNCore.Address,
            context: LGNCore.Context
        ) async throws -> Bytes {
            let transport: LGNCore.Transport = C.preferredTransport

            let client: LGNCClient

            switch transport {
            case .LGNS: client = self.clientLGNS
            case .HTTP: client = self.clientHTTP
            default: throw E.UnsupportedTransport(transport) // todo once
            }

            return try await client.send(
                contract: C.self,
                payload: payload,
                at: address,
                context: context
            )
        }
    }
}
