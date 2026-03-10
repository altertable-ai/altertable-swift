//
//  Context.swift
//  Altertable
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(WatchKit)
    import WatchKit
#endif

enum Context {
    static var libName: String {
        SDKConstants.libraryName
    }

    static var libVersion: String {
        SDKConstants.libraryVersion
    }

    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "unknown"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    static var appNamespace: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    static var osName: String {
        #if os(iOS)
            return "iOS"
        #elseif os(macOS)
            return "macOS"
        #elseif os(tvOS)
            return "tvOS"
        #elseif os(watchOS)
            return "watchOS"
        #elseif os(Linux)
            return "Linux"
        #else
            return "unknown"
        #endif
    }

    static var osVersion: String {
        #if canImport(UIKit) && !os(watchOS)
            return UIDevice.current.systemVersion
        #elseif os(macOS) || os(watchOS)
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
            return "unknown"
        #endif
    }

    static var deviceModel: String {
        #if targetEnvironment(simulator)
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #elseif os(iOS) || os(tvOS) || os(watchOS)
            return sysctlString("hw.machine") ?? "unknown"
        #elseif os(macOS)
            return sysctlString("hw.model") ?? "unknown"
        #else
            return "unknown"
        #endif
    }

    static var deviceName: String {
        #if canImport(UIKit) && !os(watchOS)
            return UIDevice.current.model
        #elseif os(watchOS)
            return "Apple Watch"
        #elseif os(macOS)
            return "Mac"
        #else
            return "unknown"
        #endif
    }

    static var deviceType: String {
        #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? "Tablet" : "Mobile"
        #elseif os(macOS)
            return "Desktop"
        #elseif os(tvOS)
            return "TV"
        #elseif os(watchOS)
            return "Watch"
        #else
            return "unknown"
        #endif
    }

    static var deviceManufacturer: String {
        "Apple"
    }

    private static func sysctlString(_ name: String) -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }

    static var viewport: String? {
        #if os(iOS) || os(tvOS)
            let width = Int(UIScreen.main.bounds.width)
            let height = Int(UIScreen.main.bounds.height)
            return "\(width)x\(height)"
        #elseif os(macOS)
            guard let screen = NSScreen.main else { return nil }
            let width = Int(screen.frame.width)
            let height = Int(screen.frame.height)
            return "\(width)x\(height)"
        #elseif os(watchOS)
            let width = Int(WKInterfaceDevice.current().screenBounds.width)
            let height = Int(WKInterfaceDevice.current().screenBounds.height)
            return "\(width)x\(height)"
        #else
            return nil
        #endif
    }

    static func getSystemProperties() -> [String: JSONValue] {
        var props: [String: JSONValue] = [
            SDKConstants.propertyLib: JSONValue(libName),
            SDKConstants.propertyLibVersion: JSONValue(libVersion),
            SDKConstants.propertyAppName: JSONValue(appName),
            SDKConstants.propertyAppVersion: JSONValue(appVersion),
            SDKConstants.propertyAppBuild: JSONValue(appBuild),
            SDKConstants.propertyAppNamespace: JSONValue(appNamespace),
            SDKConstants.propertyOs: JSONValue(osName),
            SDKConstants.propertyOsVersion: JSONValue(osVersion),
            SDKConstants.propertyDeviceManufacturer: JSONValue(deviceManufacturer),
            SDKConstants.propertyDeviceModel: JSONValue(deviceModel),
        ]
        if let viewportValue = viewport {
            props[SDKConstants.propertyViewport] = JSONValue(viewportValue)
        }
        props[SDKConstants.propertyDeviceName] = JSONValue(deviceName)
        props[SDKConstants.propertyDeviceType] = JSONValue(deviceType)
        return props
    }
}
