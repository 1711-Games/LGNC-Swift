import XCTest
import LGNCore
import LGNLog
import LGNS
import AsyncHTTPClient
import NIOHTTP1
@testable import LGNC

typealias A = Services.Auth.Contracts
typealias S = Services.Shop.Contracts

typealias Good = Services.Shared.Good

extension A.Login.Response: Equatable {
    public static func == (lhs: Services.Auth.Contracts.Login.Response, rhs: Services.Auth.Contracts.Login.Response) -> Bool {
        lhs.token.value == rhs.token.value && lhs.userID == rhs.userID
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
    static let validToken = "authorized :ok:"
    static let cookieDate: Date = Date(timeIntervalSince1970: 605_404_800)

    static let queue1: DispatchQueue = DispatchQueue(label: "LGNCTests.1", qos: .userInteractive, attributes: .concurrent)
    static let queue2: DispatchQueue = DispatchQueue(label: "LGNCTests.2", qos: .userInteractive, attributes: .concurrent)
    static let queue3: DispatchQueue = DispatchQueue(label: "LGNCTests.3", qos: .userInteractive, attributes: .concurrent)
    static let queue4: DispatchQueue = DispatchQueue(label: "LGNCTests.4", qos: .userInteractive, attributes: .concurrent)
    var eventLoop: EventLoop {
        Self.eventLoopGroup.next()
    }

    override static func setUp() {
        LoggingSystem.bootstrap(LGNLogger.init)
        LGNLogger.logLevel = .trace
        LGNLogger.hideLabel = true
        LGNLogger.hideTimezone = true

        A.Signup.Request.validateEmail { email -> A.Signup.Request.CallbackValidatorEmailAllowedValues? in
            email == "foo@bar.com"
                ? .UserWithGivenEmailAlreadyExists
                : nil
        }
        A.Signup.Request.validateUsername { username -> A.Signup.Request.CallbackValidatorUsernameAllowedValues? in
            username == "foobar"
                ? .UserWithGivenUsernameAlreadyExists
                : nil
        }
        A.Signup.guarantee { request -> A.Signup.Response in
            A.Signup.Response()
        }

        A.Login.guarantee { request throws -> A.Login.Response in
            guard request.email == "bar@baz.com" && request.password == "123456" else {
                throw LGNC.E.singleError(
                    field: "password",
                    message: "Incorrect password",
                    code: 403
                )
            }
            let age = 86400 * 365 // a year
            return A.Login.Response(
                userID: 1337,
                token: LGNC.Entity.Cookie(
                    name: "token",
                    value: Self.validToken,
                    path: "/",
                    domain: ".1711.games",
                    expires: Self.cookieDate.addingTimeInterval(TimeInterval(age)),
                    maxAge: age,
                    httpOnly: true,
                    secure: true
                )
            )
        }

        A.Authenticate.guaranteeCanonical { request -> (response: A.Authenticate.Response, meta: Meta) in
            (
                response: A.Authenticate.Response(
                    IDUser: request.token.value == Self.validToken
                        ? 1337
                        : nil
                ),
                meta: [
                    "sas": "sos",
                ]
            )
        }

        S.Goods.guaranteeCanonical { _ -> (response: S.Goods.Response, meta: Meta) in
            (
                response: S.Goods.Response(
                    list: [
                        Good(ID: 1, name: "foo", description: "bar", price: 13.37),
                        Good(ID: 2, name: "baz", price: 32.2),
                    ]
                ),
                meta: [
                    "lul": "kek",
                ]
            )
        }

        S.DummyContract.guarantee { _ -> LGNC.Entity.Empty in
            .init()
        }

        let cryptor = try! LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
        let controlBitmask: LGNP.Message.ControlBitmask = [.contentTypeMsgPack]

        S.Purchases.guaranteeCanonical { request -> (response: S.Purchases.Response, meta: Meta) in
            let clientLGNS = LGNS.Client(
                cryptor: cryptor,
                controlBitmask: controlBitmask,
                eventLoopGroup: Self.eventLoopGroup
            )

            let authResponse = try await A.Authenticate.execute(
                at: LGNCore.Address.ip(host: "127.0.0.1", port: 27020),
                with: .init(token: request.token),
                using: clientLGNS
            )

            try await clientLGNS.disconnect()

            guard authResponse.IDUser != nil else {
                throw LGNC.ContractError.GeneralError("Not authenticated", 401)
            }

            return S.Purchases.withHeaders(
                response: S.Purchases.Response(
                    list: [Good(ID: 2, name: "baz", price: 32.2)]
                ),
                meta: [
                    LGNC.HTTP.HEADER_PREFIX + "Gerreg": "Tlaalt",
                ],
                headers: [
                    ("Lul", "Kek"),
                ]
            )
        }

        S.AboutUs.guarantee { (result: Result<LGNC.Entity.Empty, Error>) -> HTMLResponse in
            "default HTML response"
        }

        S.DownloadPurchase.guarantee { _ in
            LGNC.Entity.File(filename: "", contentType: .TextPlain, body: Bytes([1, 2, 3]))
        }

        S.Upload.guarantee { _ in
            "default upload response"
        }

        let promiseStartAuthLGNS: EventLoopPromise<Void> = Self.eventLoopGroup.next().makePromise()
        let promiseStartShopLGNS: EventLoopPromise<Void> = Self.eventLoopGroup.next().makePromise()
        let promiseStartAuthHTTP: EventLoopPromise<Void> = Self.eventLoopGroup.next().makePromise()
        let promiseStartShopHTTP: EventLoopPromise<Void> = Self.eventLoopGroup.next().makePromise()

        self.queue1.async {
            Task {
                do {
                    let server = try await LGNC.startServerLGNS(
                        service: Services.Auth.self,
                        cryptor: cryptor,
                        eventLoopGroup: Self.eventLoopGroup,
                        requiredBitmask: controlBitmask
                    )
                    promiseStartAuthLGNS.succeed(())
                    try server.waitForStop()
                } catch {
                    promiseStartAuthLGNS.fail(error)
                }
            }
        }
        self.queue2.async {
            Task {
                do {
                    let server = try await Services.Shop.startServerLGNS(
                        cryptor: cryptor,
                        eventLoopGroup: Self.eventLoopGroup,
                        requiredBitmask: controlBitmask
                    )
                    promiseStartShopLGNS.succeed(())
                    try server.waitForStop()
                } catch {
                    promiseStartShopLGNS.fail(error)
                }
            }
        }

        self.queue3.async {
            Task {
                do {
                    let server = try await LGNC.startServerHTTP(
                        service: Services.Auth.self,
                        at: .ip(host: "127.0.0.1", port: 27022),
                        eventLoopGroup: Self.eventLoopGroup
                    )
                    promiseStartAuthHTTP.succeed(())
                    try server.waitForStop()
                } catch {
                    promiseStartAuthHTTP.fail(error)
                }
            }
        }
        self.queue4.async {
            Task {
                do {
                    let server = try await Services.Shop.startServerHTTP(
                        at: .ip(host: "127.0.0.1", port: 27023),
                        eventLoopGroup: Self.eventLoopGroup
                    )
                    promiseStartShopHTTP.succeed(())
                    try server.waitForStop()
                } catch {
                    promiseStartShopHTTP.fail(error)
                }
            }
        }

        XCTAssertNoThrow(try promiseStartAuthLGNS.futureResult.wait())
        XCTAssertNoThrow(try promiseStartShopLGNS.futureResult.wait())
        XCTAssertNoThrow(try promiseStartAuthHTTP.futureResult.wait())
        XCTAssertNoThrow(try promiseStartShopHTTP.futureResult.wait())
    }

    public func _test(
        using client: LGNCClient,
        addHTTP: Bool = false,
        portAuth: Int = 27020,
        portShop: Int = 27021
    ) async throws {
        let prefix = addHTTP ? "http://" : ""
        let addressAuth = LGNCore.Address.ip(host: prefix + "127.0.0.1", port: portAuth)
        let addressShop = LGNCore.Address.ip(host: prefix + "127.0.0.1", port: portShop)

        _ = try await A.Signup.execute(
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
        )

        let response1 = try await A.Login.execute(
            at: addressAuth,
            with: A.Login.Request(
                email: "bar@baz.com",
                password: "123456"
            ),
            using: client
        )
        XCTAssertEqual(
            response1,
            A.Login.Response(userID: 1337, token: .init(name: "token", value: Self.validToken))
        )

        let response2 = try await A.Authenticate.execute(
            at: addressAuth,
            with: A.Authenticate.Request(token: .init(name: "token", value: Self.validToken)),
            using: client
        )
        XCTAssertEqual(
            response2,
            A.Authenticate.Response(IDUser: 1337)
        )

        let response3 = try await A.Authenticate.execute(
            at: addressAuth,
            with: A.Authenticate.Request(token: .init(name: "token", value: "invalid")),
            using: client
        )
        XCTAssertEqual(
            response3,
            A.Authenticate.Response(IDUser: nil)
        )

        let response4 = try await S.Goods.execute(
            at: addressShop,
            with: S.Goods.Request(),
            using: client
        )
        XCTAssertEqual(
            response4,
            S.Goods.Response(
                list: [
                    Good(ID: 1, name: "foo", description: "bar", price: 13.37),
                    Good(ID: 2, name: "baz", price: 32.2),
                ]
            )
        )

        do {
            _ = try await A.Signup.execute(
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
            )
            XCTFail("Should've failed")
        } catch {
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

        do {
            _ = try await A.Signup.execute(
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
            )
            XCTFail("Should've failed")
        } catch {
            guard case LGNC.E.MultipleError(let err) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(
                err["email"]?.first?.getErrorTuple().message,
                "Invalid email format"
            )
        }

        do {
            _ = try await A.Login.execute(
                at: addressAuth,
                with: A.Login.Request(
                    email: "invalid",
                    password: "1234567"
                ),
                using: client
            )
        } catch {
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

    func testWithLoopbackClient() async throws {
        try await self._test(using: LGNC.Client.Loopback(eventLoopGroup: Self.eventLoopGroup))
    }

    func testWithDynamicClient() async throws {
        let cryptor = try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
        let controlBitmask: LGNP.Message.ControlBitmask = [.contentTypeMsgPack]

        let client = LGNC.Client.Dynamic(
            eventLoopGroup: Self.eventLoopGroup,
            clientLGNS: LGNS.Client(
                cryptor: cryptor,
                controlBitmask: controlBitmask,
                eventLoopGroup: Self.eventLoopGroup
            ),
            clientHTTP: HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        )
        try await self._test(using: client)
        try await self._test(using: client.clientHTTP, addHTTP: true, portAuth: 27022, portShop: 27023)

        try await client.disconnect()
    }

    func testCookies() async throws {
        let cryptor = try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
        let controlBitmask: LGNP.Message.ControlBitmask = [.contentTypeMsgPack]

        let addressAuthLGNS = LGNCore.Address.ip(host: "127.0.0.1", port: 27020)
        let addressAuthHTTP = LGNCore.Address.ip(host: "http://127.0.0.1", port: 27022)

        let clientHTTP = HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        defer { try! clientHTTP.syncShutdown() }

        let clientLGNS = LGNS.Client(
            cryptor: cryptor,
            controlBitmask: controlBitmask,
            eventLoopGroup: Self.eventLoopGroup
        )

        let request = A.Login.Request(
            email: "bar@baz.com",
            password: "123456"
        )

        let age = 86400 * 365
        let expectedCookie = LGNC.Entity.Cookie(
            name: "token",
            value: Self.validToken,
            path: "/",
            domain: ".1711.games",
            expires: Self.cookieDate.addingTimeInterval(TimeInterval(age)),
            maxAge: age,
            httpOnly: true,
            secure: true
        )
        let loginResultHTTP = try await A.Login.executeReturningMeta(
            at: addressAuthHTTP,
            with: request,
            using: clientHTTP
        )
        XCTAssertEqual(expectedCookie, loginResultHTTP.response.token)

        let loginResultLGNS = try await A.Login.execute(
            at: addressAuthLGNS,
            with: request,
            using: clientLGNS
        )
        XCTAssertEqual(expectedCookie, loginResultLGNS.token)
    }

    func testGETSafe() async throws {
        let client = HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        defer { try! client.syncShutdown() }

        let addressShop = LGNCore.Address.ip(host: "http://127.0.0.1", port: 27023)

        let result = try await client.execute(
            request: HTTPClient.Request(
                url: "\(addressShop)/Purchases?page=1711&ignoreFree=true",
                method: .GET,
                headers: HTTPHeaders([
                    ("Cookie", "m-wf-loaded=q-icons-q_serif ; token=\(Self.validToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!); lul=kek%3Dchebu%3F%3F%3F%3Brek ; _ga = GA1.2.942846199.1482123615"),
                ])
            )
        ).get()
        XCTAssertNotNil(result.body)
        var body = result.body!
        XCTAssertGreaterThan(body.readableBytes, 0)
        let maybeBytes = body.readBytes(length: body.readableBytes)
        XCTAssertNotNil(maybeBytes)
        let json = try maybeBytes!.unpackFromJSON()
        XCTAssertTrue(json["success"] as? Bool == true, maybeBytes!._string)

        XCTAssertTrue(result.headers.contains(where: { k, v in k == "Lul" && v == "Kek" }))
        XCTAssertTrue(result.headers.contains(where: { k, v in k == "Gerreg" && v == "Tlaalt" }))
    }

    @discardableResult
    func _testHTMLContract(expectedBody: String) async throws -> HTTPClient.Response {
        let client = HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        defer { try! client.syncShutdown() }

        let addressShop = LGNCore.Address.ip(host: "http://127.0.0.1", port: 27023)

        let result = try await client
            .execute(request: HTTPClient.Request(url: "\(addressShop)/about_us", method: .GET))
            .get()

        XCTAssertNotNil(result.body)
        XCTAssertEqual(result.body!.getString(at: 0, length: result.body!.readableBytes), "<h1>Hello!</h1>")
        XCTAssertEqual(result.headers.first(name: "Content-Type"), "text/html; charset=UTF-8")

        return result
    }

    func testHTMLContract_string() async throws {
        let expectedBody = "<h1>Hello!</h1>"

        S.AboutUs.guarantee { (result: Result<LGNC.Entity.Empty, Error>) -> HTMLResponse in
            expectedBody
        }

        try await self._testHTMLContract(expectedBody: expectedBody)
    }

    func testHTMLContract_byteBuffer_string() async throws {
        let expectedBody = "<h1>Hello!</h1>"

        S.AboutUs.guarantee { (result: Result<LGNC.Entity.Empty, Error>) -> HTMLResponse in
            ByteBufferAllocator().buffer(string: expectedBody)
        }

        try await self._testHTMLContract(expectedBody: expectedBody)
    }

    func testHTMLContract_byteBuffer_bytes() async throws {
        let expectedBody = "<h1>Hello!</h1>"

        S.AboutUs.guarantee { (result: Result<LGNC.Entity.Empty, Error>) -> HTMLResponse in
            ByteBufferAllocator().buffer(bytes: LGNCore.getBytes(expectedBody))
        }

        try await self._testHTMLContract(expectedBody: expectedBody)
    }

    func testHTMLContract_ELF_byteBuffer() async throws {
        let expectedBody = "<h1>Hello!</h1>"

        S.AboutUs.guarantee { (result: Result<LGNC.Entity.Empty, Error>) -> HTMLResponse in
            self.eventLoop.makeSucceededFuture(ByteBufferAllocator().buffer(string: expectedBody))
        }

        try await self._testHTMLContract(expectedBody: expectedBody)
    }

    func testHTMLContract_withHeaders() async throws {
        let expectedBody = "<h1>Hello!</h1>"

        S.AboutUs.guarantee { (result: Result<LGNC.Entity.Empty, Error>) -> HTMLResponse in
            S.AboutUs.withHeaders(html: expectedBody, headers: ["X-Foo": "Bar"])
        }

        let result = try await self._testHTMLContract(expectedBody: expectedBody)
        XCTAssertEqual(result.headers.first(name: "X-Foo"), "Bar")
    }

    func _testFileContract_setup() -> Bytes {
        let bytes: Bytes = LGNCore.getBytes("😂 Привет мир! 😂")

        S.DownloadPurchase.guaranteeCanonical { _ in
            .init(
                file: .init(filename: "LGNC.exe", contentType: .ApplicationOctetStream, body: bytes),
                disposition: .Attachment,
                meta: HTTP.metaWithHeaders(
                    headers: ["X-Foo": "Bar"],
                    meta: ["Baz": "Sas"]
                )
            )
        }

        return bytes
    }

    func testFileContract_download_HTTP() async throws {
        let expected = self._testFileContract_setup()

        let client = HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        defer { try! client.syncShutdown() }

        let addressShop = LGNCore.Address.ip(host: "http://127.0.0.1", port: 27023)

        let result = try await client
            .execute(request: HTTPClient.Request(url: "\(addressShop)/download_purchase", method: .GET))
            .get()

        XCTAssertNotNil(result.body)
        XCTAssertEqual(result.body!.getBytes(at: 0, length: result.body!.readableBytes), expected)
        XCTAssertEqual(result.headers.first(name: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(result.headers.first(name: "Content-Disposition"), "Attachment; filename=\"LGNC.exe\"")
        XCTAssertEqual(result.headers.first(name: "X-Foo"), "Bar")
    }

    func testFileContract_download_LGNS() async throws {
        let expected = self._testFileContract_setup()

        let cryptor = try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
        let controlBitmask: LGNP.Message.ControlBitmask = [.contentTypeMsgPack]

        let client = LGNS.Client(
            cryptor: cryptor,
            controlBitmask: controlBitmask,
            eventLoopGroup: Self.eventLoopGroup
        )
        let result = try await S.DownloadPurchase.execute(
            at: LGNCore.Address.ip(host: "127.0.0.1", port: 27021),
            with: .init(),
            using: client
        )

        XCTAssertEqual(result.filename, "LGNC.exe")
        XCTAssertEqual(result.contentType.type, "application/octet-stream")
        XCTAssertEqual(result.body, expected)
    }

    public func testFileContract_upload() async throws {
        // upload example taken from https://stackoverflow.com/a/28380690/25705
        let upload = """
        -----------------------------141487394013402550553084642717
        Content-Disposition: form-data; name="text1"

        text default
        -----------------------------141487394013402550553084642717
        Content-Disposition: form-data; name="text2"

        aωb
        -----------------------------141487394013402550553084642717
        Content-Disposition: form-data; name="file1"; filename="a.txt"
        Content-Type: text/plain

        Content of a.txt.

        -----------------------------141487394013402550553084642717
        Content-Disposition: form-data; name="file2"; filename="a.html"
        Content-Type: text/html;charset = utf-8

        <!DOCTYPE html><title>Content of a.html.</title>

        -----------------------------141487394013402550553084642717
        Content-Disposition: form-data; name="file3"; filename="binary"
        Content-Type: application/octet-stream

        aωb
        -----------------------------141487394013402550553084642717--
        """.data(using: .utf8)!

        S.Upload.guarantee { _request in
            let result: String
            switch _request {
            case let .success(request):
                result = """
                text1=\(request.text1),
                text2=\(request.text2),
                file1=filename:\(request.file1.filename!) content-type:\(request.file1.contentType.header) body:\(String(bytes: request.file1.body, encoding: .utf8)!),
                file2=filename:\(request.file2.filename!) content-type:\(request.file2.contentType.header) body:\(String(bytes: request.file2.body, encoding: .utf8)!),
                file3=filename:\(request.file3.filename!) content-type:\(request.file3.contentType.header) body:\(String(bytes: request.file3.body, encoding: .utf8)!),
                """
            case let .failure(error):
                result = "This shouldn't've happen: \(error)"
            }
            return result
        }

        let client = HTTPClient(eventLoopGroupProvider: .shared(Self.eventLoopGroup))
        defer { try! client.syncShutdown() }

        let result = try await client
            .execute(
                request: HTTPClient.Request(
                    url: "\(LGNCore.Address.ip(host: "http://127.0.0.1", port: 27023))/Upload",
                    method: .POST,
                    headers: [
                        "Content-Type": "multipart/form-data; boundary=---------------------------141487394013402550553084642717",
                    ],
                    body: .data(upload)
                )
            )
            .get()

        XCTAssertNotNil(result.body)
        XCTAssertEqual(
            result.body!.getString(at: 0, length: result.body!.readableBytes)!,
            """
            text1=text default,
            text2=aωb,
            file1=filename:a.txt content-type:text/plain body:Content of a.txt.\n,
            file2=filename:a.html content-type:text/html; charset=utf-8 body:<!DOCTYPE html><title>Content of a.html.</title>\n,
            file3=filename:binary content-type:application/octet-stream body:aωb,
            """
        )
    }

//    static var allTests = [
//        ("testWithLoopbackClient", testWithLoopbackClient),
//        ("testWithDynamicClient", testWithDynamicClient),
//        ("testCookies", testCookies),
//        ("testGETSafe", testGETSafe),
//    ]
}
