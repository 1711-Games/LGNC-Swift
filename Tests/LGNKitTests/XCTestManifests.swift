import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(LGNCoreTests.allTests),
        testCase(EntitaTests.allTests),
        testCase(LGNSTests.allTests),
        testCase(LGNPTests.allTests),
    ]
}
#endif
