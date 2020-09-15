import XCTest
import NIO

@testable import LGNS
@testable import LGNP

final class LGNSTests: XCTestCase {
    enum E: Error {
        case NoBytes
    }

    final class TestHandler: ChannelInboundHandler {
        public typealias InboundIn = ByteBuffer
        public typealias OutboundOut = ByteBuffer

        let payload: Bytes
        let promise: EventLoopPromise<Bytes>

        init(payload: Bytes, promise: EventLoopPromise<Bytes>) {
            self.payload = payload
            self.promise = promise
        }

        public func channelActive(context: ChannelHandlerContext) {
            var buffer = context.channel.allocator.buffer(capacity: self.payload.count)
            buffer.writeBytes(self.payload)
            context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var byteBuffer = self.unwrapInboundIn(data)
            guard let bytes = byteBuffer.readAllBytes() else {
                self.promise.fail(E.NoBytes)
                return
            }
            self.promise.succeed(bytes)
            context.close(promise: nil)
        }

        public func errorCaught(context: ChannelHandlerContext, error: Error) {
            self.promise.fail(error)
            context.close(promise: nil)
        }
    }

    static var eventLoopGroup: EventLoopGroup!
    static var eventLoop: EventLoop {
        self.eventLoopGroup.next()
    }

    var eventLoop: EventLoop {
        Self.eventLoop
    }

    var eventLoopGroup: EventLoopGroup {
        Self.eventLoopGroup
    }

    var semaphore: DispatchSemaphore {
        return DispatchSemaphore(value: 0)
    }

    var queue: DispatchQueue = DispatchQueue(label: "LGNSTests", qos: .userInteractive, attributes: .concurrent)

    override class func setUp() {
        super.setUp()
        var logger = Logger(label: "testlogger")
        logger.logLevel = .debug
        LGNS.logger = logger
        LGNS.Client.logger = logger
        LGNS.Server.logger = logger
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override class func tearDown() {
        super.tearDown()
        try! self.eventLoopGroup.syncShutdownGracefully()
    }

    func testLGNS() throws {
        let address = LGNCore.Address.port(32269)
        let cryptor = try! LGNP.Cryptor(key: "1234567812345678")
        let controlBitmask = LGNP.Message.ControlBitmask([.encrypted, .signatureSHA512, .contentTypeJSON])
        let nul: Bytes = [0]
        let nl: Bytes = [10]
        let meta: Bytes = [
            "ip": "195.248.161.225",
            "cid": "LGNSTests",
            "ua": "NIO",
            "lc": "en_US",
        ]
            .map { $0.key.bytes + nul + $0.value.bytes }
            .reduce(into: Bytes([])) { $0.append(contentsOf: $1 + nl) }

        let server = LGNS.Server(
            cryptor: cryptor,
            requiredBitmask: controlBitmask,
            eventLoopGroup: self.eventLoopGroup,
            readTimeout: .milliseconds(100),
            writeTimeout: .milliseconds(100)
        ) { message, context -> EventLoopFuture<LGNP.Message?> in
            XCTAssertEqual(context.clientAddr, "195.248.161.225")
            XCTAssertEqual(context.clientID, "LGNSTests")
            XCTAssertEqual(context.userAgent, "NIO")
            XCTAssertEqual(context.locale, .enUS)
            return context.eventLoop.makeSucceededFuture(
                message.copied(payload: message.payload + ", hooman".bytes)
            )
        }
        let promiseStart: PromiseVoid = self.eventLoop.makePromise()
        defer {
            XCTAssertNoThrow(try server.shutdown().wait())
        }
        self.queue.async {
            do {
                try server.bind(to: address).wait()
                promiseStart.succeed(())
                try server.waitForStop()

            } catch {
                promiseStart.fail(error)
            }
        }
        XCTAssertNoThrow(try promiseStart.futureResult.wait())
        let message: LGNP.Message = .init(
            URI: "/test1",
            payload: "henlo".bytes,
            meta: [0, 255] + meta,
            controlBitmask: controlBitmask
        )
        let LGNSClient = LGNS.Client(cryptor: cryptor, controlBitmask: controlBitmask, eventLoopGroup: self.eventLoopGroup)
        let response = try LGNSClient.request(
            at: address,
            with: message
        ).wait()

        XCTAssertEqual(
            response.0.payload,
            "henlo".bytes + ", hooman".bytes
        )

        XCTAssertEqual(
            try LGNSClient.request(
                at: address,
                with: .init(
                    URI: "/test2",
                    payload: "henlo".bytes,
                    meta: [0, 255] + meta,
                    controlBitmask: controlBitmask
                ),
                on: self.eventLoop
            ).wait().0.payload,
            "henlo".bytes + ", hooman".bytes
        )

        // 103 Message length cannot be zero
        let zeroErrorMessage = try LGNP.decode(
            body: self.write(
                to: address,
                payload: "LGNP".bytes + [0,0,0,0] + [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1] + [2,3,4]
            ),
            with: cryptor
        )

        XCTAssertEqual(zeroErrorMessage._payloadAsString.split(separator: " ", maxSplits: 1).first, "103")
        XCTAssertTrue(zeroErrorMessage.containsError)

        // 201 Required bitmask not satisfied
        let requiredBitmaskErrorMessage = try LGNP.decode(
            body: self.write(
                to: address,
                payload: "LGNP".bytes +
                    Bytes([20,0,0,0]) +
                    Bytes([1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]) +
                    Bytes([0,0]) +
                    Bytes(repeating: 0, count: 20)
            ),
            with: cryptor
        )
        XCTAssertEqual(requiredBitmaskErrorMessage._payloadAsString.split(separator: " ", maxSplits: 1).first, "201")
        XCTAssertTrue(requiredBitmaskErrorMessage.containsError)

        // 202 Connection timeout
        let timeoutErrorMessage = try LGNP.decode(body: self.write(to: address, payload: "LUL".bytes), with: cryptor)
        XCTAssertEqual(timeoutErrorMessage._payloadAsString.split(separator: " ", maxSplits: 1).first, "202")
        XCTAssertTrue(timeoutErrorMessage.containsError)
    }

    func testKeepAliveServer() {
        let address = LGNCore.Address.port(32269)
        let cryptor = try! LGNP.Cryptor(key: "1234567812345678")
        let controlBitmask = LGNP.Message.ControlBitmask.defaultValues

        let request1 = "first"
        let request2 = "second"
        let request3 = "third"
        let response1 = "first response"
        let response2 = "second response"
        let response3 = "third response, bye"

        let server: AnyServer = LGNS.Server(
            cryptor: cryptor,
            requiredBitmask: controlBitmask,
            eventLoopGroup: self.eventLoopGroup
        ) { message, context in
            XCTAssertTrue(message.controlBitmask.contains(.keepAlive))

            let response: LGNP.Message

            var responseControlBitmaskWithDisconnect = message.controlBitmask
            responseControlBitmaskWithDisconnect.remove(.keepAlive)

            switch message.URI {
            case request1:
                response = message.copied(payload: [], URI: response1)
            case request2:
                response = message.copied(payload: [], URI: response2)
            case request3:
                // disconnect
                response = message.copied(
                    payload: [],
                    controlBitmask: responseControlBitmaskWithDisconnect,
                    URI: response3
                )
            default:
                response = message.copied(
                    payload: "ERROR!".bytes,
                    controlBitmask: responseControlBitmaskWithDisconnect,
                    URI: "error"
                )
                XCTFail("We shouldn't've end up here")
            }

            return context.eventLoop.makeSucceededFuture(response)
        }
        try! server.bind(to: address).wait()
        defer { try! server.shutdown().wait() }

        let client = LGNS.Client(cryptor: cryptor, controlBitmask: controlBitmask, eventLoopGroup: self.eventLoopGroup)
        try! client.connect(at: address).wait()

        XCTAssertEqual(
            try client.request(
                at: address,
                with: LGNP.Message(URI: request1, payload: [], controlBitmask: [.keepAlive])
            ).wait().0.URI,
            response1
        )
        XCTAssertEqual(
            try client.request(
                at: address,
                with: LGNP.Message(URI: request2, payload: [], controlBitmask: [.keepAlive])
            ).wait().0.URI,
            response2
        )
        XCTAssertEqual(
            try client.request(
                at: address,
                with: LGNP.Message(
                    URI: request3,
                    payload: [],
                    controlBitmask: [
                        .keepAlive // this should be ignored by server
                    ]
                )
            ).wait().0.URI,
            response3
        )
        XCTAssertFalse(client.isConnected)
    }

    func write(to address: LGNCore.Address, payload: Bytes) throws -> Bytes {
        let promise: EventLoopPromise<Bytes> = self.eventLoop.makePromise()

        let channel = try ClientBootstrap(group: self.eventLoopGroup)
            .connectTimeout(.seconds(3))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers(TestHandler(payload: payload, promise: promise))
            }
            .connect(to: address, defaultPort: 0)
            .wait()

        return try promise
            .futureResult
            .flatMap { bytes in
                channel
                    .close()
                    .map { bytes }
            }
            .wait()
    }

    static var allTests = [
        ("testLGNS", testLGNS),
    ]
}
