import Foundation
import LGNCore
import LGNP
import LGNS
import NIO

public typealias Address = LGNS.Address

public extension Contract {
    public static func execute(
        at address: Address,
        with request: Self.Request,
        using client: LGNS.Client,
        controlBitmask: LGNP.Message.ControlBitmask? = nil,
        uuid: UUID = UUID(),
        requestInfo: LGNC.RequestInfo? = nil
    ) -> EventLoopFuture<Self.Response> {
        let controlBitmask = controlBitmask ?? client.controlBitmask
        let payload: Bytes
        let contentType = controlBitmask.contentType
        let eventLoop = client.eventLoopGroup.next()

        do {
            if contentType != .PlainText {
                payload = try [LGNC.ENTITY_KEY: try request.getDictionary()].pack(to: contentType)
            } else {
                LGNCore.log("Plain text not implemented")
                payload = Bytes()
            }
        } catch {
            return eventLoop.newFailedFuture(error: error)
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
        ).thenThrowing { responseMessage in
            try responseMessage.unpackPayload()
        }.then { (dict: [String: Any]) -> Future<LGNC.Entity.Result> in
            LGNC.Entity.Result.initFromResponse(
                from: dict,
                on: eventLoop,
                type: Self.Response.self
            )
        }.thenThrowing { result in
            guard result.success == true else {
                throw LGNC.E.MultipleError(result.errors)
            }
            guard let resultEntity = result.result else {
                throw LGNC.E.UnpackError("Empty result")
            }
            return resultEntity as! Self.Response
        }.thenIfErrorThrowing {
            if case let ChannelError.connectFailed(error) = $0 {
                LGNCore.log("""
                Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                @ \(address): \(error)
                """, prefix: uuid.string)
                throw LGNC.ContractError.RemoteContractExecutionFailed
            }
            throw $0
        }
    }
}
