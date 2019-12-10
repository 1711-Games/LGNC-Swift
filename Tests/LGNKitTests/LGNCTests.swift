import XCTest
import LGNCore
import LGNS
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
    var eventLoop: EventLoop {
        Self.eventLoopGroup.next()
    }

    override static func setUp() {
        LoggingSystem.bootstrap(LGNCore.Logger.init)
        LGNCore.Logger.logLevel = .trace
    }

    override func setUp() {
        A.Signup.Request.validateEmail { (email, eventLoop) -> Future<A.Signup.Request.CallbackValidatorEmailAllowedValues?> in
            eventLoop.makeSucceededFuture(
                email == "foo@bar.com"
                    ? .UserWithGivenEmailAlreadyExists
                    : nil
            )
        }
        A.Signup.Request.validateUsername { (username, eventLoop) -> Future<A.Signup.Request.CallbackValidatorUsernameAllowedValues?> in
            eventLoop.makeSucceededFuture(
                username == "foobar"
                    ? .UserWithGivenUsernameAlreadyExists
                    : nil
            )
        }
        A.Signup.guarantee { (request, context) -> Future<A.Signup.Response> in
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

        S.Goods.guarantee { (_, context) -> Future<(response: S.Goods.Response, meta: Meta)> in
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

    public func _test(using client: LGNCClient) {
        let addressAuth = LGNCore.Address.ip(host: "127.0.0.1", port: 27020)
        let addressShop = LGNCore.Address.ip(host: "127.0.0.1", port: 27021)

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
        let cryptor = try LGNP.Cryptor(salt: [1,2,3,4,5, 6], key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
        let controlBitmask: LGNP.Message.ControlBitmask = [.contentTypeMsgPack]

        let promiseStartAuth: PromiseVoid = self.eventLoop.makePromise()
        let promiseStartShop: PromiseVoid = self.eventLoop.makePromise()

        defer {
            XCTAssertNoThrow(try SignalObserver.fire(signal: 322).wait())
        }
        self.queue1.async {
            do {
                try Services.Auth.serveLGNS(
                    cryptor: cryptor,
                    eventLoopGroup: Self.eventLoopGroup,
                    requiredBitmask: controlBitmask,
                    promise: promiseStartAuth
                )
            } catch {
                promiseStartAuth.fail(error)
            }
        }
        self.queue2.async {
            do {
                try Services.Shop.serveLGNS(
                    cryptor: cryptor,
                    eventLoopGroup: Self.eventLoopGroup,
                    requiredBitmask: controlBitmask,
                    promise: promiseStartShop
                )
            } catch {
                promiseStartShop.fail(error)
            }
        }
        XCTAssertNoThrow(try promiseStartAuth.futureResult.wait())
        XCTAssertNoThrow(try promiseStartShop.futureResult.wait())

        self._test(
            using: LGNC.Client.Dynamic(
                eventLoopGroup: Self.eventLoopGroup,
                clientLGNS: LGNS.Client(
                    cryptor: cryptor,
                    controlBitmask: controlBitmask,
                    eventLoopGroup: Self.eventLoopGroup
                )
            )
        )
    }

    static var allTests = [
        ("testWithLoopbackClient", testWithLoopbackClient),
        ("testWithDynamicClient", testWithDynamicClient),
    ]
}
