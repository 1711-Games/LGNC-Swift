import Foundation
import LGNCore
import LGNS
import LGNP
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
                URI: self.URI,
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
            if case ChannelError.connectFailed(let error) = $0 {
                LGNCore.log("""
                    Could not execute contract '\(self)' on service '\(self.ParentService.self)' \
                    @ \(address): \(error)
                    """, prefix: uuid.string)
                throw LGNC.ContractError.RemoteContractExecutionFailed
            }
            throw $0
        }
    }

//    public static func execute(
//        at address: Address,
//        with request: Self.Request,
//        cryptor: LGNP.Cryptor,
//        on eventLoop: EventLoop,
//        controlBitmask: LGNP.Message.ControlBitmask = .defaultValues,
//        uuid: _UUID = UUID(),
//        requestInfo: RequestInfo? = nil
//    ) -> EventLoopFuture<Self.Response> {
//        let promise: EventLoopPromise<LGNC.Entity.Result> = eventLoop.newPromise()
//        DispatchQueue(label: "com.elegion.contract", qos: .userInitiated, attributes: .concurrent).async {
//            do {
//                let payload: Bytes
//                let contentType = controlBitmask.contentType
//                if contentType != .PlainText {
//                    payload = try [LGNC.ENTITY_KEY: try request.getDictionary()].pack(to: contentType)
//                } else {
//                    LGNCore.log("Plain text not implemented")
//                    payload = Bytes()
//                }
//
//                var meta: Bytes?
//                if let requestInfo = requestInfo {
//                    meta = LGNC.getMeta(from: requestInfo)
//                }
//
//                let requestMessage = LGNP.Message(
//                    URI: self.URI,
//                    payload: payload,
//                    meta: meta,
//                    salt: salt.bytes,
//                    controlBitmask: controlBitmask,
//                    uuid: uuid
//                )
//
////                print("Opening socket")
//                let connection: Socket = try Socket.create(family: .inet, type: .stream, proto: .tcp)
//                //print("Hello \(requestMessage.URI)")
//                defer {
//                    //print("Bye \(requestMessage.URI)")
//                    connection.close()
//                }
//
//                //print("Connecting to \(address)")
//                switch address {
//                case .ip(let host, let port): try connection.connect(to: host, port: Int32(port))
//                case .localhost: try connection.connect(to: "127.0.0.1", port: Int32(LGNS.DEFAULT_PORT))
//                case .unixDomainSocket(let path): try connection.connect(to: path)
//                }
//
//                var cryptor: LGNP.Cryptor? = nil
//                if let key = key {
//                    cryptor = try LGNP.Cryptor(salt: salt, key: key)
//                }
//
//                let encoded = try LGNP.encode(
//                    message: requestMessage,
//                    with: cryptor
//                )
//                //        print("Request message")
//                //        dump(encoded.ascii)
//
//                //print("Writing to socket")
//                let _ = try connection.write(from: Data(encoded))
//                //print("Written \(written) bytes")
//                var output = Data()
//                //print("Reading from socket")
//                let _ = try connection.read(into: &output)
//                //print("Read")
//                //        print("Response message")
//                //        dump(output.ascii)
//                //        print("Unpacked payload")
//                //        dump(unpacked)
//                //        dump(response)
//                promise.succeed(
//                    result: try LGNC.Entity.Result.initFromResponse(
//                        from: try LGNP.decode(
//                            body: output.bytes,
//                            with: cryptor,
//                            salt: salt.bytes
//                        ).unpackPayload(),
//                        type: Self.Response.self
//                    )
//                )
//            } catch {
//                promise.fail(error: error)
//            }
//        }
//        return promise.futureResult.thenThrowing { response in
//            guard response.success == true else {
//                throw LGNC.E.MultipleError(response.errors)
//            }
//            guard let result = response.result else {
//                throw LGNC.E.UnpackError("Empty result")
//            }
//            return result as! Self.Response
//        }
//    }
}
