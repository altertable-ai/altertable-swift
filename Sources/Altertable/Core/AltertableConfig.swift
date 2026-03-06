//
//  AltertableConfig.swift
//  Altertable
//

import Foundation

public class AltertableConfig {
    /// The base URL of the Altertable API.
    /// - Default: `"https://api.altertable.ai"`
    public var baseURL: String

    /// The environment of the application.
    /// - Default: `"production"`
    public var environment: String

    /// The tracking consent state.
    /// - Default: `.granted`
    public var trackingConsent: TrackingConsentState

    /// The release ID of the application.
    /// This is helpful to identify the version of the application an event is coming from.
    /// When `nil`, the SDK automatically reads `CFBundleShortVersionString` from your app's bundle.
    public var release: String?

    /// Optional error handler for intercepting SDK errors.
    public var onError: ((Error) -> Void)?

    /// Whether to log events to the console.
    /// - Default: `false`
    public var debug: Bool

    /// The timeout interval for outgoing HTTP requests.
    /// - Default: `10` seconds
    public var requestTimeout: TimeInterval

    /// Whether to flush the event queue when the app moves to the background.
    /// - Default: `true`
    public var flushOnBackground: Bool

    public init(
        baseURL: String = SDKConstants.defaultBaseURL,
        environment: String = SDKConstants.defaultEnvironment,
        trackingConsent: TrackingConsentState = SDKConstants.defaultTrackingConsent,
        release: String? = nil,
        onError: ((Error) -> Void)? = nil,
        debug: Bool = SDKConstants.defaultDebug,
        requestTimeout: TimeInterval = SDKConstants.mobileRequestTimeout,
        flushOnBackground: Bool = SDKConstants.defaultFlushOnBackground
    ) {
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

public class PartialAltertableConfig {
    /// The tracking consent state to apply.
    public var trackingConsent: TrackingConsentState?

    /// Whether to enable debug logging.
    public var debug: Bool?

    /// The environment to apply.
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
