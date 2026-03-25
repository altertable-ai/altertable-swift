//
//  SDKConstants.swift
//  Altertable
//

import Foundation

enum SDKConstants {
    static let libraryName = "altertable-swift"
    static let libraryVersion = "0.1.0"

    enum StorageKeys {
        static let deviceId = "atbl.device_id"
        static let distinctId = "atbl.distinct_id"
        static let anonymousId = "atbl.anonymous_id"
        static let sessionId = "atbl.session_id"
        static let lastEventAt = "atbl.last_event_at"

        static let trackingConsent = "atbl.tracking_consent"

        static let all: [String] = [deviceId, distinctId, anonymousId, sessionId, lastEventAt, trackingConsent]
    }

    static let sessionExpirationTime: TimeInterval = 1800 // 30 minutes

    // ID Prefixes
    static let prefixSessionId = "session"
    static let prefixAnonymousId = "anonymous"
    static let prefixDeviceId = "device"

    /// Events
    static let eventPageview = "$pageview"
    static let eventScreenView = "$screen"

    // Properties
    static let propertyAppBuild = "$app_build"
    static let propertyAppName = "$app_name"
    static let propertyAppNamespace = "$app_namespace"
    static let propertyAppVersion = "$app_version"
    static let propertyDeviceManufacturer = "$device_manufacturer"
    static let propertyDeviceModel = "$device_model"
    static let propertyDeviceName = "$device"
    static let propertyDeviceType = "$device_type"
    static let propertyLib = "$lib"
    static let propertyLibVersion = "$lib_version"
    static let propertyOs = "$os"
    static let propertyOsVersion = "$os_version"
    static let propertyRelease = "$release"
    static let propertyScreenName = "$screen_name"
    static let propertyViewport = "$viewport"

    /// Limits
    static let maxQueueSize = 1000

    /// Outbound HTTP request timeout (seconds)
    static let defaultRequestTimeoutSeconds: TimeInterval = 10.0

    /// Batching
    static let defaultFlushIntervalMs = 1000
    static let defaultFlushEventThreshold = 20
    static let defaultMaxBatchSize = 20

    /// HTTP retries
    static let httpRetryMaxAttempts = 4
    static let httpRetryBaseDelaySeconds = 1.0
}
