import XCTest
@testable import LGNKit

final class LGNKitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(LGNKit().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
