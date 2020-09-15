import XCTest
import LGNCore
import LGNS
import AsyncHTTPClient
@testable import LGNC

typealias A = Services.Auth.Contracts
typealias S = Services.Shop.Contracts

typealias Good = Services.Shared.Good

extension A.Login.Response: Equatable {
    public static func == (lhs: Services.Auth.Contracts.Login.Response, rhs: Services.Auth.Contracts.Login.Response) -> Bool {
        lhs.token == rhs.token && lhs.userID == rhs.userID
    }
}

extension A.Authenticate.Response: Equatable {
    public static func == (lhs: Services.Auth.Contracts.Authenticate.Response, rhs: Services.Auth.Contracts.Authenticate.Response) -> Bool {
        lhs.IDUser == rhs.IDUser
    }
}

extension S.Good: Equatable {
    public static func == (lhs: Services.Shared.Good, rhs: Services.Shared.Good) -> Bool {
        lhs.ID == rhs.ID && lhs.name == rhs.name && lhs.description == rhs.description && lhs.price == rhs.price
    }
}

extension S.Goods.Response: Equatable {
    public static func == (lhs: Services.Shop.Contracts.Goods.Response, rhs: Services.Shop.Contracts.Goods.Response) -> Bool {
        lhs.list == rhs.list
    }
}

final class LGNCTests: XCTestCase {
    static let eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    var queue1: DispatchQueue = DispatchQueue(label: "LGNCTests.1", qos: .userInteractive, attributes: .concurrent)
    var queue2: DispatchQueue = DispatchQueue(label: "LGNCTests.2", qos: .userInteractive, attributes: .concurrent)
    var queue3: DispatchQueue = DispatchQueue(label: "LGNCTests.3", qos: .userInteractive, attributes: .concurrent)
    var queue4: DispatchQueue = DispatchQueue(label: "LGNCTests.4", qos: .userInteractive, attributes: .concurrent)
    var eventLoop: EventLoop {
        Self.eventLoopGroup.next()
    }

    override static func setUp() {
        LoggingSystem.bootstrap(LGNCore.Logger.init)
        LGNCore.Logger.logLevel = .trace
    }

    override func setUp() {
        A.Signup.Request.validateEmail { (email, eventLoop) -> EventLoopFuture<A.Signup.Request.CallbackValidatorEmailAllowedValues?> in
            eventLoop.makeSucceededFuture(
                email == "foo@bar.com"
                    ? .UserWithGivenEmailAlreadyExists
                    : nil
            )
        }
        A.Signup.Request.validateUsername { (username, eventLoop) -> EventLoopFuture<A.Signup.Request.CallbackValidatorUsernameAllowedValues?> in
            eventLoop.makeSucceededFuture(
                username == "foobar"
                    ? .UserWithGivenUsernameAlreadyExists
                    : nil
            )
        }
        A.Signup.guarantee { (request, context) -> EventLoopFuture<A.Signup.Response> in
            context.eventLoop.makeSucceededFuture(A.Signup.Response())
        }

        A.Login.guarantee { (request, context) throws -> A.Login.Response in
            guard request.email == "bar@baz.com" && request.password == "123456" else {
                throw LGNC.E.singleError(
                    field: "password",
                    message: "Incorrect password",
                    code: 403
                )
            }
            return A.Login.Response(token: "kjsdfjkshdf", userID: 1337)
        }

        A.Authenticate.guarantee { (request, context) -> (response: A.Authenticate.Response, meta: Meta) in
            (
                response: A.Authenticate.Response(
                    IDUser: request.token == "kjsdfjkshdf"
                        ? 1337
                        : nil
                ),
                meta: [
                    "sas": "sos",
                ]
            )
        }

        S.Goods.guarantee { (_, context) -> EventLoopFuture<(response: S.Goods.Response, meta: Meta)> in
            context.eventLoop.makeSucceededFuture((
                response: S.Goods.Response(
                    list: [
                        Good(ID: 1, name: "foo", description: "bar", price: 13.37),
                        Good(ID: 2, name: "baz", price: 32.2),
                    ]
                ),
                meta: [
                    "lul": "kek",
                ]
            ))
        }
    }

    public func _test(using client: LGNCClient, addHTTP: Bool = false, portAuth: Int = 27020, portShop: Int = 27021) {
        let prefix = addHTTP ? "http://" : ""
        let addressAuth = LGNCore.Address.ip(host: prefix + "127.0.0.1", port: portAuth)
        let addressShop = LGNCore.Address.ip(host: prefix + "127.0.0.1", port: portShop)

        XCTAssertNoThrow(
            try A.Signup.execute(
                at: addressAuth,
                with: A.Signup.Request(
                    username: "123",
                    email: "lul@kek.com",
                    password1: "123456",
                    password2: "123456",
                    sex: "Male",
                    language: "ru",
                    recaptchaToken: "skjhdfjkshdf"
                ),
                using: client
            ).wait()
        )

        XCTAssertEqual(
            try A.Login.execute(
                at: addressAuth,
                with: A.Login.Request(
                    email: "bar@baz.com",
                    password: "123456"
                ),
                using: client
            ).wait(),
            A.Login.Response(token: "kjsdfjkshdf", userID: 1337)
        )

        XCTAssertEqual(
            try A.Authenticate.execute(
                at: addressAuth,
                with: A.Authenticate.Request(token: "kjsdfjkshdf"),
                using: client
            ).wait(),
            A.Authenticate.Response(IDUser: 1337)
        )

        XCTAssertEqual(
            try A.Authenticate.execute(
                at: addressAuth,
                with: A.Authenticate.Request(token: "invalid"),
                using: client
            ).wait(),
            A.Authenticate.Response(IDUser: nil)
        )

        XCTAssertEqual(
            try S.Goods.execute(
                at: addressShop,
                with: S.Goods.Request(),
                using: client
            ).wait(),
            S.Goods.Response(
                list: [
                    Good(ID: 1, name: "foo", description: "bar", price: 13.37),
                    Good(ID: 2, name: "baz", price: 32.2),
                ]
            )
        )

        XCTAssertThrowsError(
            try A.Signup.execute(
                at: addressAuth,
                with: A.Signup.Request(
                    username: "foobar",
                    email: "foo@bar.com",
                    password1: "123",
                    password2: "1234567",
                    sex: "Male",
                    language: "ru",
                    recaptchaToken: "skjhdfjkshdf"
                ),
                using: client
            ).wait()
        ) { error in
            guard case LGNC.E.MultipleError(let err) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(
                err["email"]?.first?.getErrorTuple().message,
                "User with given email already exists"
            )
            XCTAssertEqual(
                err["email"]?.first?.getErrorTuple().code,
                10002
            )
            XCTAssertEqual(
                err["username"]?.first?.getErrorTuple().message,
                "User with given username already exists"
            )
            XCTAssertEqual(
                err["username"]?.first?.getErrorTuple().code,
                10001
            )
            XCTAssertEqual(
                err["password1"]?.first?.getErrorTuple().message,
                "Password must be at least 6 characters long"
            )
            XCTAssertEqual(
                err["password2"]?.first?.getErrorTuple().message,
                "Passwords must match"
            )
        }

        XCTAssertThrowsError(
            try A.Signup.execute(
                at: addressAuth,
                with: A.Signup.Request(
                    username: "foobarr",
                    email: "invalid",
                    password1: "1234567",
                    password2: "1234567",
                    sex: "Male",
                    language: "ru",
                    recaptchaToken: "skjhdfjkshdf"
                ),
                using: client
            ).wait()
        ) { error in
            guard case LGNC.E.MultipleError(let err) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(
                err["email"]?.first?.getErrorTuple().message,
                "Invalid email format"
            )
        }

        XCTAssertThrowsError(
            try A.Login.execute(
                at: addressAuth,
                with: A.Login.Request(
                    email: "invalid",
                    password: "1234567"
                ),
                using: client
            ).wait()
        ) { error in
            guard case LGNC.E.MultipleError(let err) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(
                err["password"]?.first?.getErrorTuple().message,
                "Incorrect password"
            )
            XCTAssertEqual(
                err["password"]?.first?.getErrorTuple().code,
                403
            )
        }
    }

    func testWithLoopbackClient() {
        self._test(using: LGNC.Client.Loopback(eventLoopGroup: Self.eventLoopGroup))
    }

    func testWithDynamicClient() throws {
        let cryptor = try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
        let controlBitmask: LGNP.Message.ControlBitmask = [.contentTypeMsgPack]

        let promiseStartAuthLGNS: PromiseVoid = self.eventLoop.makePromise()
        let promiseStartShopLGNS: PromiseVoid = self.eventLoop.makePromise()
        let promiseStartAuthHTTP: PromiseVoid = self.eventLoop.makePromise()
        let promiseStartShopHTTP: PromiseVoid = self.eventLoop.makePromise()

        self.queue1.async {
            do {
                let server = try LGNC.startServerLGNS(
                    service: Services.Auth.self,
                    cryptor: cryptor,
                    eventLoopGroup: Self.eventLoopGroup,
                    requiredBitmask: controlBitmask
                ).wait()
                promiseStartAuthLGNS.succeed(())
                try server.waitForStop()
            } catch {
                promiseStartAuthLGNS.fail(error)
            }
        }
        self.queue2.async {
            do {
                let server = try Services.Shop.startServerLGNS(
                    cryptor: cryptor,
                    eventLoopGroup: Self.eventLoopGroup,
                    requiredBitmask: controlBitmask
                ).wait()
                promiseStartShopLGNS.succeed(())
                try server.waitForStop()
            } catch {
                promiseStartShopLGNS.fail(error)
            }
        }

        self.queue3.async {
            do {
                let server = try LGNC.startServerHTTP(
                    service: Services.Auth.self,
                    at: .ip(host: "127.0.0.1", port: 27022),
                    eventLoopGroup: Self.eventLoopGroup
                ).wait()
                promiseStartAuthHTTP.succeed(())
                try server.waitForStop()
            } catch {
                promiseStartAuthHTTP.fail(error)
            }
        }
        self.queue4.async {
            do {
                let server = try Services.Shop.startServerHTTP(
                    at: .ip(host: "127.0.0.1", port: 27023),
                    eventLoopGroup: Self.eventLoopGroup
                ).wait()
                promiseStartShopHTTP.succeed(())
                try server.waitForStop()
            } catch {
                promiseStartShopHTTP.fail(error)
            }
        }

        XCTAssertNoThrow(try promiseStartAuthLGNS.futureResult.wait())
        XCTAssertNoThrow(try promiseStartShopLGNS.futureResult.wait())
        XCTAssertNoThrow(try promiseStartAuthHTTP.futureResult.wait())
        XCTAssertNoThrow(try promiseStartShopHTTP.futureResult.wait())

        let client = LGNC.Client.Dynamic(
            eventLoopGroup: Self.eventLoopGroup,
            clientLGNS: LGNS.Client(
                cryptor: cryptor,
                controlBitmask: controlBitmask,
                eventLoopGroup: Self.eventLoopGroup
            ),
            clientHTTP: HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        )
        self._test(using: client)
        self._test(using: client.clientHTTP, addHTTP: true, portAuth: 27022, portShop: 27023)

        try client.disconnect().wait()
    }

    static var allTests = [
        ("testWithLoopbackClient", testWithLoopbackClient),
        ("testWithDynamicClient", testWithDynamicClient),
    ]
}
