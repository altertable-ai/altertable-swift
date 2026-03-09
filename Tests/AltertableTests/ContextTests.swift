//
//  ContextTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

final class ContextTests: XCTestCase {
    func testGetSystemPropertiesContainsRequiredKeys() {
        let props = Context.getSystemProperties()
        XCTAssertNotNil(props[SDKConstants.propertyLib], "Should include $lib")
        XCTAssertNotNil(props[SDKConstants.propertyLibVersion], "Should include $lib_version")
        XCTAssertNotNil(props[SDKConstants.propertyOs], "Should include os")
        XCTAssertNotNil(props[SDKConstants.propertyOsVersion], "Should include os_version")
        XCTAssertNotNil(props[SDKConstants.propertyDeviceManufacturer], "Should include device_manufacturer")
        XCTAssertNotNil(props[SDKConstants.propertyDeviceModel], "Should include device_model")
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
        XCTAssertNotNil(props[SDKConstants.propertyDeviceName], "Should include $device_name")
        XCTAssertNotNil(props[SDKConstants.propertyDeviceType], "Should include $device_type")
    }

    func testAppPropertiesInSystemProperties() {
        let props = Context.getSystemProperties()
        XCTAssertNotNil(props[SDKConstants.propertyAppName], "Should include $app_name")
        XCTAssertNotNil(props[SDKConstants.propertyAppVersion], "Should include $app_version")
        XCTAssertNotNil(props[SDKConstants.propertyAppBuild], "Should include $app_build")
        XCTAssertNotNil(props[SDKConstants.propertyAppNamespace], "Should include $app_namespace")
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
    }

    func testViewportInSystemProperties() {
        let props = Context.getSystemProperties()
        #if os(iOS) || os(tvOS) || os(macOS) || os(watchOS)
        XCTAssertNotNil(props[SDKConstants.propertyViewport], "Should include $viewport on Apple platforms")
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
        XCTAssertNil(props[SDKConstants.propertyViewport], "$viewport should be absent on unsupported platforms")
        #endif
    }
}
