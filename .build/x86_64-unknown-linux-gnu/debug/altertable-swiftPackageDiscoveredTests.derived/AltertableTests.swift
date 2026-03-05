import XCTest
@testable import AltertableTests

fileprivate extension AltertableTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__AltertableTests = [
        ("testInitialization", testInitialization)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __AltertableTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AltertableTests.__allTests__AltertableTests)
    ]
}