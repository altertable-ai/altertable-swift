//
//  ContextTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

final class ContextTests: XCTestCase {
    func testGetSystemPropertiesContainsRequiredKeys() {
        let props = Context.getSystemProperties()
        XCTAssertNotNil(props["$lib"], "Should include $lib")
        XCTAssertNotNil(props["$lib_version"], "Should include $lib_version")
        XCTAssertNotNil(props["os"], "Should include os")
        XCTAssertNotNil(props["os_version"], "Should include os_version")
        XCTAssertNotNil(props["manufacturer"], "Should include manufacturer")
        XCTAssertNotNil(props["model"], "Should include model")
    }

    func testLibNameMatchesSDKConstant() {
        let props = Context.getSystemProperties()
        XCTAssertEqual(props["$lib"]?.value as? String, SDKConstants.libraryName)
    }

    func testLibVersionMatchesSDKConstant() {
        let props = Context.getSystemProperties()
        XCTAssertEqual(props["$lib_version"]?.value as? String, SDKConstants.libraryVersion)
    }

    func testManufacturerIsApple() {
        XCTAssertEqual(Context.deviceManufacturer, "Apple")
    }

    func testOsNameIsNotEmpty() {
        XCTAssertFalse(Context.osName.isEmpty)
        XCTAssertNotEqual(Context.osName, "unknown")
    }

    func testOsVersionIsNotEmpty() {
        XCTAssertFalse(Context.osVersion.isEmpty)
    }
}
