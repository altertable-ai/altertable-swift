//
//  ContextTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

final class ContextTests: XCTestCase {
    func testGetSystemPropertiesContainsRequiredKeys() {
        let props = Context.getSystemProperties()
        XCTAssertNotNil(props[SDKConstants.propertyLib], "Should include \(SDKConstants.propertyLib)")
        XCTAssertNotNil(props[SDKConstants.propertyLibVersion], "Should include \(SDKConstants.propertyLibVersion)")
        XCTAssertNotNil(props[SDKConstants.propertyOs], "Should include \(SDKConstants.propertyOs)")
        XCTAssertNotNil(props[SDKConstants.propertyOsVersion], "Should include \(SDKConstants.propertyOsVersion)")
        XCTAssertNotNil(props[SDKConstants.propertyDeviceManufacturer], "Should include \(SDKConstants.propertyDeviceManufacturer)")
        XCTAssertNotNil(props[SDKConstants.propertyDeviceModel], "Should include \(SDKConstants.propertyDeviceModel)")
    }

    func testLibNameMatchesSDKConstant() {
        let props = Context.getSystemProperties()
        XCTAssertEqual(props[SDKConstants.propertyLib], .string(SDKConstants.libraryName))
    }

    func testLibVersionMatchesSDKConstant() {
        let props = Context.getSystemProperties()
        XCTAssertEqual(props[SDKConstants.propertyLibVersion], .string(SDKConstants.libraryVersion))
    }

    func testManufacturerIsApple() {
        XCTAssertEqual(Context.deviceManufacturer, "Apple")
    }

    func testDeviceModelIsNotEmpty() {
        XCTAssertFalse(Context.deviceModel.isEmpty)
        XCTAssertNotEqual(Context.deviceModel, "unknown")
    }

    func testDeviceNameIsNotEmpty() {
        XCTAssertFalse(Context.deviceName.isEmpty)
        XCTAssertNotEqual(Context.deviceName, "unknown")
    }

    func testDeviceTypeIsNotEmpty() {
        XCTAssertFalse(Context.deviceType.isEmpty)
        XCTAssertNotEqual(Context.deviceType, "unknown")
    }

    func testDeviceNameAndTypeInSystemProperties() {
        let props = Context.getSystemProperties()
        XCTAssertNotNil(props[SDKConstants.propertyDeviceName], "Should include \(SDKConstants.propertyDeviceName)")
        XCTAssertNotNil(props[SDKConstants.propertyDeviceType], "Should include \(SDKConstants.propertyDeviceType)")
    }

    func testAppPropertiesInSystemProperties() {
        let props = Context.getSystemProperties()
        XCTAssertNotNil(props[SDKConstants.propertyAppName], "Should include \(SDKConstants.propertyAppName)")
        XCTAssertNotNil(props[SDKConstants.propertyAppVersion], "Should include \(SDKConstants.propertyAppVersion)")
        XCTAssertNotNil(props[SDKConstants.propertyAppBuild], "Should include \(SDKConstants.propertyAppBuild)")
        XCTAssertNotNil(props[SDKConstants.propertyAppNamespace], "Should include \(SDKConstants.propertyAppNamespace)")
    }

    func testAppNameIsNotEmpty() {
        XCTAssertFalse(Context.appName.isEmpty)
    }

    func testAppVersionIsNotEmpty() {
        XCTAssertFalse(Context.appVersion.isEmpty)
    }

    func testAppBuildIsNotEmpty() {
        XCTAssertFalse(Context.appBuild.isEmpty)
    }

    func testAppNamespaceIsNotEmpty() {
        XCTAssertFalse(Context.appNamespace.isEmpty)
    }

    func testOsNameIsNotEmpty() {
        XCTAssertFalse(Context.osName.isEmpty)
        XCTAssertNotEqual(Context.osName, "unknown")
    }

    func testOsVersionIsNotEmpty() {
        XCTAssertFalse(Context.osVersion.isEmpty)
        #if os(iOS) || os(tvOS) || os(macOS) || os(watchOS)
        XCTAssertNotEqual(Context.osVersion, "unknown", "os_version must not be unknown on Apple platforms")
        XCTAssertTrue(Context.osVersion.first?.isNumber ?? false, "os_version should be a version string (e.g. 14.0)")
        #else
        XCTAssertEqual(Context.osVersion, "unknown")
        #endif
    }

    func testViewportInSystemProperties() {
        let props = Context.getSystemProperties()
        #if os(iOS) || os(tvOS) || os(macOS) || os(watchOS)
        XCTAssertNotNil(props[SDKConstants.propertyViewport], "Should include \(SDKConstants.propertyViewport) on Apple platforms")
        if case let .string(viewport) = props[SDKConstants.propertyViewport] {
            XCTAssertFalse(viewport.isEmpty)
            let components = viewport.split(separator: "x")
            XCTAssertEqual(components.count, 2, "Viewport should be in format 'widthxheight'")
            if components.count == 2,
               let width = Int(components[0]),
               let height = Int(components[1])
            {
                XCTAssertGreaterThan(width, 0)
                XCTAssertGreaterThan(height, 0)
            }
        }
        #else
        XCTAssertNil(props[SDKConstants.propertyViewport], "\(SDKConstants.propertyViewport) should be absent on unsupported platforms")
        #endif
    }
}
