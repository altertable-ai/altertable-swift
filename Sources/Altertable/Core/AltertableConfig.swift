//
//  AltertableConfig.swift
//  Altertable
//

import Foundation

public struct AltertableConfig {
    public let apiKey: String
    public var baseURL: String
    public var environment: String
    public var trackingConsent: TrackingConsentState
    public var release: String?
    public var onError: ((Error) -> Void)?
    public var debug: Bool
    public var requestTimeout: TimeInterval
    public var flushOnBackground: Bool
    
    public init(
        apiKey: String,
        baseURL: String = SDKConstants.defaultBaseURL,
        environment: String = SDKConstants.defaultEnvironment,
        trackingConsent: TrackingConsentState = SDKConstants.defaultTrackingConsent,
        release: String? = nil,
        onError: ((Error) -> Void)? = nil,
        debug: Bool = SDKConstants.defaultDebug,
        requestTimeout: TimeInterval = SDKConstants.mobileRequestTimeout,
        flushOnBackground: Bool = SDKConstants.defaultFlushOnBackground
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.environment = environment
        self.trackingConsent = trackingConsent
        self.release = release
        self.onError = onError
        self.debug = debug
        self.requestTimeout = requestTimeout
        self.flushOnBackground = flushOnBackground
    }
}

public struct PartialAltertableConfig {
    public var trackingConsent: TrackingConsentState?
    public var debug: Bool?
    public var environment: String?
    
    public init(
        trackingConsent: TrackingConsentState? = nil,
        debug: Bool? = nil,
        environment: String? = nil
    ) {
        self.trackingConsent = trackingConsent
        self.debug = debug
        self.environment = environment
    }
}
