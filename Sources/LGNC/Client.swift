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
    var logger: Logger { get }
    var eventLoopGroup: EventLoopGroup { get }

    func send<C: Contract>(
        contract: C.Type,
        dict: Entita.Dict,
        at address: LGNCore.Address,
        over transport: LGNCore.Transport?,
        on eventLoop: EventLoop,
        requestInfo maybeRequestInfo: LGNCore.RequestInfo?
    ) -> Future<(Entita.Dict, LGNCore.RequestInfo)>
}

extension LGNS.Client: LGNCClient {
    public func send<C: Contract>(
        contract: C.Type,
        dict: Entita.Dict,
        at address: LGNCore.Address,
        over transport: LGNCore.Transport? = nil,
        on eventLoop: EventLoop,
        requestInfo maybeRequestInfo: LGNCore.RequestInfo?
    ) -> Future<(Entita.Dict, LGNCore.RequestInfo)> {
        let transport: LGNCore.Transport = .LGNS

        let contentType = C.preferredContentType
        let requestInfo = LGNC.Client.getRequestInfo(
            from: maybeRequestInfo,
            transport: transport,
            eventLoop: eventLoop
        )

        let logger = requestInfo.logger

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
                    meta: LGNC.getMeta(from: requestInfo, clientID: requestInfo.clientID),
                    salt: self.cryptor.salt.bytes,
                    controlBitmask: self.controlBitmask,
                    uuid: requestInfo.uuid
                )
            )
            .flatMapThrowing { responseMessage, responseRequestInfo in
                (try responseMessage.unpackPayload(), responseRequestInfo)
            }
    }
}

public extension LGNC.Client {
    static func getRequestInfo(
        from maybeRequestInfo: LGNCore.RequestInfo?,
        transport: LGNCore.Transport,
        eventLoop: EventLoop
    ) -> LGNCore.RequestInfo {
        if let requestInfo = maybeRequestInfo {
            if transport == requestInfo.transport {
                return requestInfo
            }

            return requestInfo.clone(transport: transport)
        }

        return LGNCore.RequestInfo(
            remoteAddr: "127.0.0.1",
            clientAddr: "127.0.0.1",
            userAgent: "\(self)",
            locale: maybeRequestInfo?.locale ?? .enUS,
            uuid: maybeRequestInfo?.uuid ?? UUID(),
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
            requestInfo maybeRequestInfo: LGNCore.RequestInfo? = nil
        ) -> Future<(Entita.Dict, LGNCore.RequestInfo)> {
            let requestInfo = LGNC.Client.getRequestInfo(
                from: maybeRequestInfo,
                transport: C.preferredTransport,
                eventLoop: eventLoop
            )

            return eventLoop
                .makeSucceededFuture(())
                .flatMap {
                    C.ParentService.executeContract(URI: C.URI, dict: dict, requestInfo: requestInfo)
                }
                .flatMapThrowing { response in
                    (try response.getDictionary(), requestInfo)
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
            requestInfo maybeRequestInfo: LGNCore.RequestInfo?
        ) -> Future<(Entita.Dict, LGNCore.RequestInfo)> {
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
                requestInfo: maybeRequestInfo
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
        requestInfo maybeRequestInfo: LGNCore.RequestInfo? = nil
    ) -> Future<Self.Response> {
        let profiler = LGNCore.Profiler.begin()
        let eventLoop = maybeRequestInfo?.eventLoop ?? client.eventLoopGroup.next()
        let logger = maybeRequestInfo?.logger ?? client.logger
        let transport = Self.preferredTransport

        let requestInfo = LGNC.Client.getRequestInfo(
            from: maybeRequestInfo,
            transport: transport,
            eventLoop: eventLoop
        )

        requestInfo.logger.debug(
            "Executing remote contract \(transport.rawValue.lowercased())://\(address)/\(Self.URI)",
            metadata: [
                "requestID": "\(requestInfo.uuid.string)",
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
            requestInfo: requestInfo
        ).flatMap { (dict: Entita.Dict, responseRequestInfo: LGNCore.RequestInfo) -> Future<LGNC.Entity.Result> in
            LGNC.Entity.Result.initFromResponse(
                from: dict,
                requestInfo: responseRequestInfo,
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
