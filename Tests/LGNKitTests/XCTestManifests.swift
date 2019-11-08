import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(LGNSTests.allTests),
        testCase(Entita2FDBTests.allTests),
        testCase(Entita2Tests.allTests),
        testCase(EntitaTests.allTests),
        testCase(LGNCoreTests.allTests),
        testCase(LGNPTests.allTests),
    ]
}
#endif
