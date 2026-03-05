//
//  AltertableTests.swift
//  AltertableTests
//

import XCTest
@testable import Altertable

final class AltertableTests: XCTestCase {
    func testInitialization() throws {
        let client = Altertable(apiKey: "pk_test_123")
        XCTAssertNotNil(client)
    }
}
