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
        let promise: Promise<Bytes>

        init(payload: Bytes, promise: Promise<Bytes>) {
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
        let cryptor = try! LGNP.Cryptor(salt: "123456", key: "1234567812345678")
        let controlBitmask = LGNP.Message.ControlBitmask([.encrypted, .signatureSHA1, .contentTypeJSON])
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
        ) { message, context -> Future<LGNP.Message?> in
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
            salt: cryptor.salt,
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
                    salt: cryptor.salt,
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
            salt: []
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
            salt: []
        )
        XCTAssertEqual(requiredBitmaskErrorMessage._payloadAsString.split(separator: " ", maxSplits: 1).first, "201")
        XCTAssertTrue(requiredBitmaskErrorMessage.containsError)

        // 202 Connection timeout
        let timeoutErrorMessage = try LGNP.decode(body: self.write(to: address, payload: "LUL".bytes), salt: [])
        XCTAssertEqual(timeoutErrorMessage._payloadAsString.split(separator: " ", maxSplits: 1).first, "202")
        XCTAssertTrue(timeoutErrorMessage.containsError)
    }

    func write(to address: LGNCore.Address, payload: Bytes) throws -> Bytes {
        let promise: Promise<Bytes> = self.eventLoop.makePromise()

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
