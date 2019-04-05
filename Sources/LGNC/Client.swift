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
        controlBitmask: LGNP.Message.ControlBitmask? = nil,
        uuid: UUID = UUID(),
        requestInfo: LGNCore.RequestInfo? = nil
    ) -> EventLoopFuture<Self.Response> {
        let controlBitmask = controlBitmask ?? client.controlBitmask
        let payload: Bytes
        let contentType = controlBitmask.contentType
        let eventLoop = client.eventLoopGroup.next()

        do {
            if contentType != .PlainText {
                payload = try [LGNC.ENTITY_KEY: try request.getDictionary()].pack(to: contentType)
            } else {
                requestInfo?.logger.critical("Plain text not implemented")
                payload = Bytes()
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }

        var meta: Bytes?
        if let requestInfo = requestInfo {
            meta = LGNC.getMeta(from: requestInfo)
        }

        return client.request(
            at: address,
            with: LGNP.Message(
                URI: URI,
                payload: payload,
                meta: meta,
                salt: client.cryptor.salt.bytes,
                controlBitmask: controlBitmask,
                uuid: uuid
            ),
            on: eventLoop
        ).flatMapThrowing { responseMessage in
            try responseMessage.unpackPayload()
        }.flatMap { (dict: [String: Any]) -> Future<LGNC.Entity.Result> in
            LGNC.Entity.Result.initFromResponse(
                from: dict,
                on: eventLoop,
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
                requestInfo?.logger.error("""
                Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                @ \(address): \(error)
                """)
                throw LGNC.ContractError.RemoteContractExecutionFailed
            }
            throw $0
        }
    }
}
