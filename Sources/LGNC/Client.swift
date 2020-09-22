import Foundation
import AsyncHTTPClient
import NIOHTTP1
import LGNCore
import Entita
import LGNP
import LGNS
import NIO

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
    ) -> EventLoopFuture<(response: Bytes, context: LGNCore.Context)>
}

extension LGNS.Client: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        payload: Bytes,
        at address: LGNCore.Address,
        context: LGNCore.Context
    ) -> EventLoopFuture<(response: Bytes, context: LGNCore.Context)> {
        let requestContext = LGNC.Client.getRequestContext(
            from: context,
            transport: .LGNS,
            eventLoop: context.eventLoop
        )

        return self
            .singleRequest(
                at: address,
                with: LGNP.Message(
                    URI: C.URI,
                    payload: payload,
                    meta: LGNC.getCompiledMeta(from: requestContext, clientID: requestContext.clientID),
                    controlBitmask: self.controlBitmask,
                    uuid: requestContext.uuid
                ),
                on: context.eventLoop
            )
            .flatMapThrowing { responseMessage, responseContext in
                (response: responseMessage.payload, responseContext)
            }
    }
}

extension HTTPClient: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        payload: Bytes,
        at address: LGNCore.Address,
        context: LGNCore.Context
    ) -> EventLoopFuture<(response: Bytes, context: LGNCore.Context)> {
        let contentType = C.preferredContentType
        let requestContext = LGNC.Client.getRequestContext(
            from: context,
            transport: .HTTP,
            eventLoop: context.eventLoop
        )

        let headers = HTTPHeaders([
            ("Content-Type", contentType.header),
            ("Accept-Language", requestContext.locale.rawValue),
        ])
        var request: HTTPClient.Request

        do {
            request = try HTTPClient.Request(
                url: address.description + "/" + C.URI,
                method: .POST,
                headers: headers,
                body: .data(.init(payload))
            )
        } catch {
            return context.eventLoop.makeFailedFuture(error)
        }

        return self
            .execute(request: request, eventLoop: .delegateAndChannel(on: context.eventLoop))
            .flatMapThrowing { response in
                guard var body = response.body, let bytes = body.readBytes(length: body.readableBytes) else {
                    throw LGNC.Client.E.EmptyResponse
                }

                let isSecure = false // response.host.starts(with: "https://")

                return (
                    response: bytes,
                    context: LGNCore.Context(
                        remoteAddr: "127.0.0.1",
                        clientAddr: "127.0.0.1",
                        userAgent: "AsyncHTTPClient",
                        locale: requestContext.locale,
                        uuid: {
                            let result: UUID

                            let newUUID = UUID()
                            // TODO extract LGNC-UUID to const
                            if isSecure, let UUIDHeader = response.headers["LGNC-UUID"].first {
                                result = UUID(uuidString: UUIDHeader) ?? newUUID
                            } else {
                                result = newUUID
                            }

                            return result
                        }(),
                        isSecure: isSecure,
                        transport: .HTTP,
                        meta: response.headers["Set-Cookie"].parseCookies(),
                        eventLoop: context.eventLoop
                    )
                )
            }
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
            uuid: maybeContext?.uuid ?? UUID(),
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
        public lazy var logger: Logger = Logger(label: "\(self)")
        public let eventLoopGroup: EventLoopGroup

        public init(eventLoopGroup: EventLoopGroup) {
            self.eventLoopGroup = eventLoopGroup
        }

        public func send<C: Contract>(
            contract: C.Type,
            payload: Bytes,
            at address: LGNCore.Address,
            context: LGNCore.Context
        ) -> EventLoopFuture<(response: Bytes, context: LGNCore.Context)> {
            let requestContext = LGNC.Client.getRequestContext(
                from: context,
                transport: C.preferredTransport,
                eventLoop: context.eventLoop
            )
            let dict: Entita.Dict
            do {
                dict = try payload.unpack(from: C.preferredContentType)
            } catch {
                return context.eventLoop.makeFailedFuture(error)
            }

            return context.eventLoop
                .makeSucceededFuture(())
                .flatMap {
                    C.ParentService.executeContract(URI: C.URI, dict: dict, context: requestContext)
                }
                .flatMapThrowing { response in
                    (try response.getDictionary().pack(to: C.preferredContentType), requestContext)
                }
        }
    }
}

public extension LGNC.Client {
    class Dynamic: LGNCClient {
        public lazy var logger: Logger = Logger(label: "\(self)")

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

        public func disconnect() -> EventLoopFuture<Void> {
            self.clientLGNS.disconnect()
        }

        public func send<C: Contract>(
            contract: C.Type,
            payload: Bytes,
            at address: LGNCore.Address,
            context: LGNCore.Context
        ) -> EventLoopFuture<(response: Bytes, context: LGNCore.Context)> {
            let transport: LGNCore.Transport = C.preferredTransport

            let client: LGNCClient

            switch transport {
            case .LGNS: client = self.clientLGNS
            case .HTTP: client = self.clientHTTP
            }

            return client.send(
                contract: C.self,
                payload: payload,
                at: address,
                context: context
            )
        }
    }
}
