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
    public static let defaultRequestTimeout: TimeInterval = SDKConstants.defaultRequestTimeoutSeconds
    public static let defaultFlushOnBackground = true
    public static let defaultCaptureScreenViews = true
    public static let defaultFlushIntervalMs = SDKConstants.defaultFlushIntervalMs
    public static let defaultFlushEventThreshold = SDKConstants.defaultFlushEventThreshold
    public static let defaultMaxBatchSize = SDKConstants.defaultMaxBatchSize

    public static let defaultMode: TrackingMode = .product

    // MARK: - Properties

    /// Collection policy. Defaults to `.product`.
    /// Audience mode omits client identifiers and uses memory-only state and queues.
    /// Create a new client to change modes.
    public var mode: TrackingMode

    /// The base URL of the Altertable API.
    /// - Default: `"https://api.altertable.ai"`
    public var baseURL: URL

    /// The product analytics environment.
    ///
    /// - Deprecated: The API key determines the environment. This value is accepted for source
    ///   compatibility and ignored by all requests and persisted state.
    /// - Default: `"production"`
    @available(*, deprecated, message: "The API key determines the environment. Remove this setting.")
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

    /// When the total number of buffered events reaches this value, the SDK flushes immediately.
    /// - Default: `20`
    /// - Note: This property can only be set at initialization time. Changes via `configure()` are ignored.
    public var flushEventThreshold: Int

    /// Periodic flush interval in milliseconds.
    /// - Default: `1000` (1 second)
    /// - Note: This property can only be set at initialization time. Changes via `configure()` are ignored.
    public var flushIntervalMs: Int

    /// Maximum number of payloads per HTTP request for a given endpoint.
    /// - Default: `20`
    /// - Note: This property can only be set at initialization time. Changes via `configure()` are ignored.
    public var maxBatchSize: Int

    public init(
        mode: TrackingMode = AltertableConfig.defaultMode,
        baseURL: URL = AltertableConfig.defaultBaseURL,
        trackingConsent: TrackingConsentState = AltertableConfig.defaultTrackingConsent,
        release: String? = nil,
        onError: ((Error) -> Void)? = nil,
        debug: Bool = AltertableConfig.defaultDebug,
        requestTimeout: TimeInterval = AltertableConfig.defaultRequestTimeout,
        flushOnBackground: Bool = AltertableConfig.defaultFlushOnBackground,
        captureScreenViews: Bool = AltertableConfig.defaultCaptureScreenViews,
        flushEventThreshold: Int = AltertableConfig.defaultFlushEventThreshold,
        flushIntervalMs: Int = AltertableConfig.defaultFlushIntervalMs,
        maxBatchSize: Int = AltertableConfig.defaultMaxBatchSize
    ) {
        self.mode = mode
        self.baseURL = baseURL
        self.environment = AltertableConfig.defaultEnvironment
        self.trackingConsent = trackingConsent
        self.release = release
        self.onError = onError
        self.debug = debug
        self.requestTimeout = requestTimeout
        self.flushOnBackground = flushOnBackground
        self.captureScreenViews = captureScreenViews
        self.flushEventThreshold = flushEventThreshold
        self.flushIntervalMs = flushIntervalMs
        self.maxBatchSize = maxBatchSize
    }

    @available(*, deprecated, message: "The API key determines the environment. Remove the environment argument.")
    public init(
        mode: TrackingMode = AltertableConfig.defaultMode,
        baseURL: URL = AltertableConfig.defaultBaseURL,
        environment: String = AltertableConfig.defaultEnvironment,
        trackingConsent: TrackingConsentState = AltertableConfig.defaultTrackingConsent,
        release: String? = nil,
        onError: ((Error) -> Void)? = nil,
        debug: Bool = AltertableConfig.defaultDebug,
        requestTimeout: TimeInterval = AltertableConfig.defaultRequestTimeout,
        flushOnBackground: Bool = AltertableConfig.defaultFlushOnBackground,
        captureScreenViews: Bool = AltertableConfig.defaultCaptureScreenViews,
        flushEventThreshold: Int = AltertableConfig.defaultFlushEventThreshold,
        flushIntervalMs: Int = AltertableConfig.defaultFlushIntervalMs,
        maxBatchSize: Int = AltertableConfig.defaultMaxBatchSize
    ) {
        self.mode = mode
        self.baseURL = baseURL
        self.environment = environment
        self.trackingConsent = trackingConsent
        self.release = release
        self.onError = onError
        self.debug = debug
        self.requestTimeout = requestTimeout
        self.flushOnBackground = flushOnBackground
        self.captureScreenViews = captureScreenViews
        self.flushEventThreshold = flushEventThreshold
        self.flushIntervalMs = flushIntervalMs
        self.maxBatchSize = maxBatchSize
    }
}

public enum TrackingConsentState: String, Codable, Sendable {
    case granted
    case denied
    case pending
    case dismissed
}

/// Collection intent. Audience mode omits identity and uses memory-only state.
public enum TrackingMode: String, Codable, Sendable {
    /// Product analytics with client identities.
    case product
    /// Audience events without client identifiers. Requires an environment-bound API key.
    case audience
}

enum ConfigurationError: LocalizedError {
    case modeChange
    case storageMigration

    var errorDescription: String? {
        switch self {
        case .modeChange:
            return "Create a new Altertable client to change the tracking mode. " +
                "Events and identities cannot be migrated between modes."
        case .storageMigration:
            return "Legacy SDK state could not be migrated. Restart the app to retry; events are not collected until migration succeeds."
        }
    }
}
