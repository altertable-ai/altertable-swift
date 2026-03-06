//
//  SDKConstants.swift
//  Altertable
//

import Foundation

public enum SDKConstants {
    public static let libraryName = "altertable-swift"
    public static let libraryVersion = "0.1.0"
    
    // API
    public static let defaultBaseURL = "https://api.altertable.ai"
    public static let mobileRequestTimeout: TimeInterval = 10.0
    
    // Storage
    public static let storageKeyPrefix = "atbl"
    public static let storageKeySeparator = "."
    public static let sessionExpirationTime: TimeInterval = 1800 // 30 minutes
    
    // ID Prefixes
    public static let prefixSessionId = "session"
    public static let prefixAnonymousId = "anonymous"
    public static let prefixDeviceId = "device"
    
    // Events
    public static let eventPageview = "$pageview"
    
    // Properties
    public static let propertyLib = "$lib"
    public static let propertyLibVersion = "$lib_version"
    public static let propertyRelease = "$release"
    
    // Limits
    public static let maxQueueSize = 1000
    
    // Defaults
    public static let defaultEnvironment = "production"
    public static let defaultTrackingConsent: TrackingConsentState = .granted
    public static let defaultFlushOnBackground = true
    public static let defaultDebug = false
}

public enum TrackingConsentState: String, Codable {
    case granted
    case denied
    case pending
    case dismissed
}
