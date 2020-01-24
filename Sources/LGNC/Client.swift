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
    ) -> Future<(response: Bytes, context: LGNCore.Context)>
}

//internal extension LGNCClient {
//    static func
//}

extension LGNS.Client: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        payload: Bytes,
        at address: LGNCore.Address,
        context: LGNCore.Context
    ) -> Future<(response: Bytes, context: LGNCore.Context)> {
        let requestContext = LGNC.Client.getRequestContext(
            from: context,
            transport: .LGNS,
            eventLoop: context.eventLoop
        )

        return self
            .request(
                at: address,
                with: LGNP.Message(
                    URI: C.URI,
                    payload: payload,
                    meta: LGNC.getCompiledMeta(from: requestContext, clientID: requestContext.clientID),
                    salt: self.cryptor.salt,
                    controlBitmask: self.controlBitmask,
                    uuid: requestContext.uuid
                )
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
    ) -> Future<(response: Bytes, context: LGNCore.Context)> {
        let contentType = C.preferredContentType
        let requestContext = LGNC.Client.getRequestContext(
            from: context,
            transport: .HTTP,
            eventLoop: context.eventLoop
        )

//        let payload: Bytes
//        do {
//            if contentType != .PlainText {
//                payload = try dict.pack(to: contentType)
//            } else {
//                context.logger.critical("Plain text not implemented")
//                payload = Bytes()
//            }
//        } catch {
//            return eventLoop.makeFailedFuture(error)
//        }

        let headers = HTTPHeaders([
            ("Content-type", contentType.header),
            ("Accept-Language", requestContext.locale.rawValue),
        ])
        var request: HTTPClient.Request

        do {
            request = try HTTPClient.Request(
                url: address.description,
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

                let isSecure = response.host.starts(with: "https://")

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

            return context.clone(transport: transport)
        }

        return LGNCore.Context(
            remoteAddr: "127.0.0.1",
            clientAddr: "127.0.0.1",
            userAgent: "\(self)",
            locale: maybeContext?.locale ?? .enUS,
            uuid: maybeContext?.uuid ?? UUID(),
            isSecure: transport == .LGNS,
            transport: transport,
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
        ) -> Future<(response: Bytes, context: LGNCore.Context)> {
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

        private let clientLGNS: LGNCClient
        private let clientHTTP: HTTPClient

        public let eventLoopGroup: EventLoopGroup

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
            try? self.clientHTTP.syncShutdown()
        }

        public func send<C: Contract>(
            contract: C.Type,
            payload: Bytes,
            at address: LGNCore.Address,
            context: LGNCore.Context
        ) -> Future<(response: Bytes, context: LGNCore.Context)> {
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

public extension Contract {
    static func execute(
        at address: LGNCore.Address,
        with request: Self.Request,
        using client: LGNCClient,
        //as clientID: String? = nil,
        context maybeContext: LGNCore.Context? = nil
    ) -> Future<Self.Response> {
        let profiler = LGNCore.Profiler.begin()
        let eventLoop = maybeContext?.eventLoop ?? client.eventLoopGroup.next()
        let transport = Self.preferredTransport

        let context = LGNC.Client.getRequestContext(
            from: maybeContext,
            transport: transport,
            eventLoop: eventLoop
        )

        context.logger.debug(
            "Executing remote contract \(transport.rawValue.lowercased())://\(address)/\(Self.URI)",
            metadata: [
                "requestID": "\(context.uuid.string)",
            ]
        )

        let payload: Bytes
        do {
            payload = try request.getDictionary().pack(to: Self.preferredContentType)
        } catch {
            return eventLoop.makeFailedFuture(LGNC.Client.E.PackError("Could not pack request: \(error)"))
        }

        let result: Future<Self.Response> = client
            .send(
                contract: Self.self,
                payload: payload,
                at: address,
                context: context
            )
            .flatMapThrowing { responseBytes, responseContext in
                (dict: try responseBytes.unpack(from: Self.preferredContentType), responseContext: responseContext)
            }
            .flatMap { (dict: Entita.Dict, responseContext: LGNCore.Context) -> Future<LGNC.Entity.Result> in
                LGNC.Entity.Result.initFromResponse(
                    from: dict,
                    context: responseContext,
                    type: Self.Response.self
                )
            }
            .flatMapThrowing { (result: LGNC.Entity.Result) in
                guard result.success == true else {
                    throw LGNC.E.MultipleError(result.errors)
                }
                guard let resultEntity = result.result else {
                    throw LGNC.E.UnpackError("Empty result")
                }
                return resultEntity as! Self.Response
            }
            .flatMapErrorThrowing {
                if let error = $0 as? NIOConnectionError {
                    context.logger.error("""
                        Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                        @ \(address): \(error)
                    """)
                    throw LGNC.ContractError.RemoteContractExecutionFailed
                }
                throw $0
            }

        result.whenComplete { _ in
            context.logger.info(
                "Remote contract 'lgns://\(address)/\(URI)' execution took \(profiler.end().rounded(toPlaces: 4))s"
            )
        }

        return result
    }
}
