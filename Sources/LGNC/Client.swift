import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

public typealias Address = LGNS.Address

public extension Contract {
    static func execute(
        at address: Address,
        with request: Self.Request,
        using client: LGNS.Client,
        as clientID: String? = nil,
        controlBitmask: LGNP.Message.ControlBitmask? = nil,
        uuid: UUID = UUID(),
        requestInfo: LGNCore.RequestInfo? = nil
    ) -> Future<Self.Response> {
        let profiler = LGNCore.Profiler.begin()
        let logger = requestInfo?.logger ?? client.logger
        let controlBitmask = controlBitmask ?? client.controlBitmask
        let payload: Bytes
        let contentType = controlBitmask.contentType
        let eventLoop = client.eventLoopGroup.next()

        do {
            if contentType != .PlainText {
                payload = try [LGNC.ENTITY_KEY: try request.getDictionary()].pack(to: contentType)
            } else {
                logger.critical("Plain text not implemented")
                payload = Bytes()
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }

        logger.debug(
            "Executing remote contract lgns://\(address)/\(URI)",
            metadata: [
                "requestID": "\(uuid.string)",
            ]
        )

        let result: Future<Self.Response> = client.request(
            at: address,
            with: LGNP.Message(
                URI: URI,
                payload: payload,
                meta: LGNC.getMeta(from: requestInfo, clientID: clientID),
                salt: client.cryptor.salt.bytes,
                controlBitmask: controlBitmask,
                uuid: uuid
            ),
            on: eventLoop
        ).flatMapThrowing { responseMessage, responseRequestInfo in
            (try responseMessage.unpackPayload(), responseRequestInfo)
        }.flatMap { (dict: [String: Any], responseRequestInfo: LGNCore.RequestInfo) -> Future<LGNC.Entity.Result> in
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
                (requestInfo?.logger ?? Logger(label: "LGNC.Client")).error("""
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
