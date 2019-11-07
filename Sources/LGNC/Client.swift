import Foundation
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
    }
}

public protocol LGNCClient {
    var eventLoopGroup: EventLoopGroup { get }

    func send<C: Contract>(
        contract: C.Type,
        dict: Entita.Dict,
        at address: LGNCore.Address,
        over transport: LGNCore.Transport?,
        on eventLoop: EventLoop,
        context maybeContext: LGNCore.Context?
    ) -> Future<(Entita.Dict, LGNCore.Context)>
}

extension LGNS.Client: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        dict: Entita.Dict,
        at address: LGNCore.Address,
        over transport: LGNCore.Transport? = nil,
        on eventLoop: EventLoop,
        context maybeContext: LGNCore.Context?
    ) -> Future<(Entita.Dict, LGNCore.Context)> {
        let transport: LGNCore.Transport = .LGNS

        let contentType = C.preferredContentType
        let context = LGNC.Client.getRequestContext(
            from: maybeContext,
            transport: transport,
            eventLoop: eventLoop
        )

        let logger = context.logger

        let payload: Bytes
        do {
            if contentType != .PlainText {
                payload = try dict.pack(to: contentType)
            } else {
                logger.critical("Plain text not implemented")
                payload = Bytes()
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }

        return self
            .request(
                at: address,
                with: LGNP.Message(
                    URI: C.URI,
                    payload: payload,
                    meta: LGNC.getMeta(from: context, clientID: context.clientID),
                    salt: self.cryptor.salt,
                    controlBitmask: self.controlBitmask,
                    uuid: context.uuid
                )
            )
            .flatMapThrowing { responseMessage, responseContext in
                (try responseMessage.unpackPayload(), responseContext)
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
            dict: Entita.Dict,
            at address: LGNCore.Address,
            over transport: LGNCore.Transport? = nil,
            on eventLoop: EventLoop,
            context maybeContext: LGNCore.Context? = nil
        ) -> Future<(Entita.Dict, LGNCore.Context)> {
            let context = LGNC.Client.getRequestContext(
                from: maybeContext,
                transport: C.preferredTransport,
                eventLoop: eventLoop
            )

            return eventLoop
                .makeSucceededFuture(())
                .flatMap {
                    C.ParentService.executeContract(URI: C.URI, dict: dict, context: context)
                }
                .flatMapThrowing { response in
                    (try response.getDictionary(), context)
                }
        }
    }
}

public extension LGNC.Client {
    class Dynamic: LGNCClient {
        public lazy var logger: Logger = Logger(label: "\(self)")
        private let clientLGNS: LGNCClient
        public let eventLoopGroup: EventLoopGroup

        public init(eventLoopGroup: EventLoopGroup, clientLGNS: LGNS.Client) {
            self.eventLoopGroup = eventLoopGroup
            self.clientLGNS = clientLGNS
        }

        public func send<C: Contract>(
            contract: C.Type,
            dict: Entita.Dict,
            at address: LGNCore.Address,
            over transport: LGNCore.Transport?,
            on eventLoop: EventLoop,
            context maybeContext: LGNCore.Context?
        ) -> Future<(Entita.Dict, LGNCore.Context)> {
            let transport = transport ?? C.preferredTransport

            let client: LGNCClient

            switch transport {
            case .LGNS: client = self.clientLGNS
            default: return eventLoop.makeFailedFuture(E.UnsupportedTransport(transport))
            }

            return client.send(
                contract: C.self,
                dict: dict,
                at: address,
                over: transport,
                on: eventLoop,
                context: maybeContext
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
        let logger = maybeContext?.logger ?? LGNC.logger
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

        let dict: Entita.Dict
        do {
            dict = try request.getDictionary()
        } catch {
            return eventLoop.makeFailedFuture(LGNC.Client.E.PackError("Could not pack request: \(error)"))
        }

        let result: Future<Self.Response> = client.send(
            contract: Self.self,
            dict: dict,
            at: address,
            over: nil,
            on: eventLoop,
            context: context
        ).flatMap { (dict: Entita.Dict, responseContext: LGNCore.Context) -> Future<LGNC.Entity.Result> in
            LGNC.Entity.Result.initFromResponse(
                from: dict,
                context: responseContext,
                type: Self.Response.self
            )
        }.flatMapThrowing { (result: LGNC.Entity.Result) in
            guard result.success == true else {
                throw LGNC.E.MultipleError(result.errors)
            }
            guard let resultEntity = result.result else {
                throw LGNC.E.UnpackError("Empty result")
            }
            return resultEntity as! Self.Response
        }.flatMapErrorThrowing {
            if let error = $0 as? NIOConnectionError {
                logger.error("""
                    Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                    @ \(address): \(error)
                """)
                throw LGNC.ContractError.RemoteContractExecutionFailed
            }
            throw $0
        }

        result.whenComplete { _ in
            logger.info(
                "Remote contract 'lgns://\(address)/\(URI)' execution took \(profiler.end().rounded(toPlaces: 4))s"
            )
        }

        return result
    }
}
