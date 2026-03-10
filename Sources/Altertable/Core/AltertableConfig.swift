//
//  AltertableConfig.swift
//  Altertable
//

import Foundation

public struct AltertableConfig {
    // MARK: - Defaults

    public static let defaultBaseURL = URL(string: "https://api.altertable.ai")!
    public static let defaultEnvironment = "production"
    public static let defaultTrackingConsent: TrackingConsentState = .granted
    public static let defaultDebug = false
    public static let defaultRequestTimeout: TimeInterval = 10.0
    public static let defaultFlushOnBackground = true
    public static let defaultCaptureScreenViews = true

    // MARK: - Properties

    /// The base URL of the Altertable API.
    /// - Default: `"https://api.altertable.ai"`
    public var baseURL: URL

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
    /// - Note: This property can only be set at initialization time. Changes via `configure()` are ignored.
    public var requestTimeout: TimeInterval

    /// Whether to flush the event queue when the app moves to the background.
    /// - Default: `true`
    /// - Note: This property can only be set at initialization time. Changes via `configure()` are ignored.
    public var flushOnBackground: Bool

    /// Automatically track screen views.
    /// When enabled, the SDK automatically tracks screen views for UIKit view controllers
    /// and provides a SwiftUI view modifier for manual tracking.
    /// - Default: `true`
    public var captureScreenViews: Bool

    public init(
        baseURL: URL = AltertableConfig.defaultBaseURL,
        environment: String = AltertableConfig.defaultEnvironment,
        trackingConsent: TrackingConsentState = AltertableConfig.defaultTrackingConsent,
        release: String? = nil,
        onError: ((Error) -> Void)? = nil,
        debug: Bool = AltertableConfig.defaultDebug,
        requestTimeout: TimeInterval = AltertableConfig.defaultRequestTimeout,
        flushOnBackground: Bool = AltertableConfig.defaultFlushOnBackground,
        captureScreenViews: Bool = AltertableConfig.defaultCaptureScreenViews
    ) {
        self.baseURL = baseURL
        self.environment = environment
        self.trackingConsent = trackingConsent
        self.release = release
        self.onError = onError
        self.debug = debug
        self.requestTimeout = requestTimeout
        self.flushOnBackground = flushOnBackground
        self.captureScreenViews = captureScreenViews
    }
}

public enum TrackingConsentState: String, Codable, Sendable {
    case granted
    case denied
    case pending
    case dismissed
}
