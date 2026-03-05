//
//  Context.swift
//  Altertable
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

class Context {
    static var libName: String { SDKConstants.libraryName }
    static var libVersion: String { SDKConstants.libraryVersion }
    
    static var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    
    static var appBuild: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
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
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "unknown"
        #endif
    }
    
    static var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "unknown"
        #endif
    }
    
    static var deviceManufacturer: String {
        return "Apple"
    }
    
    static func getSystemProperties() -> [String: AnyCodable] {
        let props: [String: AnyCodable] = [
            "$lib": AnyCodable(libName),
            "$lib_version": AnyCodable(libVersion),
            "$os": AnyCodable(osName),
            "$os_version": AnyCodable(osVersion),
            "$manufacturer": AnyCodable(deviceManufacturer),
            "$model": AnyCodable(deviceModel)
        ]
        
        // Release is usually passed in config, but we can default to app version
        // We leave "$release" to be set by the main track logic from config
        
        return props
    }
}
