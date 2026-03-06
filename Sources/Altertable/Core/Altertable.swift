//
//  Altertable.swift
//  Altertable
//

import Foundation
#if canImport(Combine)
    import Combine
#endif
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public class Altertable {
    /// All mutable state is accessed exclusively on this queue.
    private let queue = DispatchQueue(label: "ai.altertable.sdk", qos: .utility)

    private let configRef: Requester.ConfigRef
    private var config: AltertableConfig {
        get { configRef.config }
        set { configRef.config = newValue }
    }

    private let sessionManager: SessionManager
    private let storage: Storage
    private let requester: Requester
    private let logger: Logger

    // Identity state — accessed only on `queue`
    private var distinctId: String
    private var anonymousId: String?
    private var deviceId: String

    // Event queue — accessed only on `queue`
    private var eventQueue: [QueuedRequest] = []
    private let queueStorage: QueueStorage
    var maxQueueSize: Int = SDKConstants.maxQueueSize

    /// NotificationCenter token for lifecycle hooks
    private var backgroundObserver: AnyObject?

    enum QueuedRequest: Codable {
        case track(TrackPayload)
        case identify(IdentifyPayload)
        case alias(AliasPayload)
    }

    /// Initializes the Altertable SDK with your API key and optional configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your Altertable API key.
    ///   - config: Optional configuration options.
    ///
    /// - Example:
    /// ```swift
    /// let altertable = Altertable(apiKey: "YOUR_API_KEY", config: AltertableConfig(
    ///     environment: "development"
    /// ))
    /// ```
    public convenience init(apiKey: String, config: AltertableConfig? = nil) {
        self.init(apiKey: apiKey, config: config, session: nil)
    }

    init(apiKey: String, config: AltertableConfig? = nil, session: URLSession? = nil) {
        // Create an internal copy of the config so external mutations don't bypass SDK side effects
        let internalConfig: AltertableConfig
        if let provided = config {
            internalConfig = AltertableConfig(
                baseURL: provided.baseURL,
                environment: provided.environment,
                trackingConsent: provided.trackingConsent,
                release: provided.release,
                onError: provided.onError,
                debug: provided.debug,
                requestTimeout: provided.requestTimeout,
                flushOnBackground: provided.flushOnBackground
            )
        } else {
            internalConfig = AltertableConfig()
        }
        
        let ref = Requester.ConfigRef(internalConfig)
        configRef = ref
        logger = Logger(isDebug: internalConfig.debug)
        queueStorage = QueueStorage(logger: logger)
        storage = UserDefaultsStorage()
        sessionManager = SessionManager(storage: storage)
        requester = Requester(apiKey: apiKey, configRef: ref, session: session)

        if let storedDevice = storage.string(forKey: SDKConstants.StorageKeys.deviceId) {
            deviceId = storedDevice
        } else {
            let newDevice = SDKConstants.prefixDeviceId + "-" + UUID().uuidString
            deviceId = newDevice
            storage.set(newDevice, forKey: SDKConstants.StorageKeys.deviceId)
        }

        if let storedDistinct = storage.string(forKey: SDKConstants.StorageKeys.distinctId) {
            distinctId = storedDistinct
        } else {
            let newDistinct = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
            distinctId = newDistinct
            storage.set(newDistinct, forKey: SDKConstants.StorageKeys.distinctId)
        }

        anonymousId = storage.string(forKey: SDKConstants.StorageKeys.anonymousId)

        if let raw = storage.string(forKey: SDKConstants.StorageKeys.trackingConsent),
           let consent = TrackingConsentState(rawValue: raw)
        {
            internalConfig.trackingConsent = consent
        }

        eventQueue = queueStorage.load()

        setupLifecycleHooks()
    }

    deinit {
        if let token = backgroundObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Public API

    /// Tracks a custom event with optional properties.
    ///
    /// - Parameters:
    ///   - event: The event name.
    ///   - properties: Custom event properties.
    ///
    /// - Example:
    /// ```swift
    /// altertable.track(event: "Purchase Completed", properties: [
    ///     "product_id": "p_01jza8fr5efvgbxxdd1bwkd0m5",
    ///     "amount": 29.99,
    ///     "currency": "USD",
    /// ])
    /// ```
    public func track(event: String, properties: [String: AnyCodable] = [:]) {
        queue.async { [self] in
            let timestamp = Date().ISO8601Format()
            let sessionId = sessionManager.getSessionId()

            var finalProperties = Context.getSystemProperties()

            if let release = config.release ??
                (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            {
                finalProperties[SDKConstants.propertyRelease] = AnyCodable(release)
            }

            properties.forEach { finalProperties[$0] = $1 }

            let payload = TrackPayload(
                timestamp: timestamp,
                event: event,
                environment: config.environment,
                deviceId: deviceId,
                distinctId: distinctId,
                anonymousId: anonymousId,
                sessionId: sessionId,
                properties: finalProperties
            )

            enqueue(.track(payload))
        }
    }

    /// Identifies a user with their ID and optional traits.
    ///
    /// - Parameters:
    ///   - userId: The user's unique identifier.
    ///   - traits: User properties.
    ///
    /// - Note: You can call this method multiple times with the same ID.
    ///   To change traits, use ``updateTraits(_:)`` instead.
    ///   To switch to a new user ID, call ``reset(resetDeviceId:resetTrackingConsent:)`` first.
    ///
    /// - Example:
    /// ```swift
    /// altertable.identify(userId: "u_01jza857w4f23s1hf2s61befmw", traits: [
    ///     "email": "john.doe@example.com",
    ///     "name": "John Doe",
    ///     "company": "Acme Corp",
    ///     "role": "Software Engineer",
    /// ])
    /// ```
    public func identify(userId: String, traits: [String: AnyCodable] = [:]) {
        queue.async { [self] in
            do {
                try Validator.validateUserId(userId)
            } catch {
                logger.error(error.localizedDescription)
                config.onError?(error)
                return
            }
            let isIdentified = anonymousId != nil

            if isIdentified, distinctId != userId {
                logger.warn(
                    "User \"\(userId)\" is already identified as \"\(distinctId)\". " +
                        "The session has been automatically reset. " +
                        "Use alias() to link the new ID to the existing one if intentional."
                )
                resetLocked()
            }

            if distinctId != userId {
                anonymousId = distinctId
                distinctId = userId
                storage.set(userId, forKey: SDKConstants.StorageKeys.distinctId)
                storage.set(anonymousId!, forKey: SDKConstants.StorageKeys.anonymousId)
            }

            let payload = IdentifyPayload(
                environment: config.environment,
                deviceId: deviceId,
                distinctId: distinctId,
                anonymousId: anonymousId,
                traits: traits
            )

            enqueue(.identify(payload))
        }
    }

    /// Links a new ID to the current identity.
    ///
    /// - Parameter newUserId: The new user ID.
    ///
    /// - Example:
    /// ```swift
    /// altertable.alias(newUserId: "u_01jza857w4f23s1hf2s61befmw")
    /// ```
    public func alias(newUserId: String) {
        queue.async { [self] in
            do {
                try Validator.validateUserId(newUserId)
            } catch {
                logger.error(error.localizedDescription)
                config.onError?(error)
                return
            }

            let payload = AliasPayload(
                environment: config.environment,
                deviceId: deviceId,
                distinctId: distinctId,
                anonymousId: anonymousId,
                newUserId: newUserId
            )

            enqueue(.alias(payload))
        }
    }

    /// Updates user traits for the current user.
    ///
    /// - Parameter traits: User properties to update.
    ///
    /// - Example:
    /// ```swift
    /// altertable.updateTraits([
    ///     "onboarding_completed": true,
    /// ])
    /// ```
    public func updateTraits(_ traits: [String: AnyCodable]) {
        queue.async { [self] in
            guard anonymousId != nil else {
                logger.warn("User must be identified with identify() before updating traits.")
                return
            }

            let payload = IdentifyPayload(
                environment: config.environment,
                deviceId: deviceId,
                distinctId: distinctId,
                anonymousId: anonymousId,
                traits: traits
            )

            enqueue(.identify(payload))
        }
    }

    /// Resets session, user, and visitor IDs.
    ///
    /// - Parameters:
    ///   - resetDeviceId: Whether to also reset the device ID. Default is `false`.
    ///   - resetTrackingConsent: Whether to reset tracking consent to the default state. Default is `false`.
    ///
    /// - Example:
    /// ```swift
    /// // Reset session, user and visitor (default)
    /// altertable.reset()
    ///
    /// // Reset session, user, visitor and device
    /// altertable.reset(resetDeviceId: true)
    /// ```
    public func reset(resetDeviceId: Bool = false, resetTrackingConsent: Bool = false) {
        queue.async { [self] in
            resetLocked(resetDeviceId: resetDeviceId)

            if resetTrackingConsent {
                config.trackingConsent = SDKConstants.defaultTrackingConsent
                storage.set(SDKConstants.defaultTrackingConsent.rawValue, forKey: SDKConstants.StorageKeys.trackingConsent)
            }
        }
    }

    /// Updates the configuration after initialization.
    ///
    /// - Parameter newConfig: Configuration updates to apply.
    ///
    /// - Example:
    /// ```swift
    /// altertable.configure(PartialAltertableConfig(
    ///     trackingConsent: .granted
    /// ))
    /// ```
    public func configure(_ newConfig: PartialAltertableConfig) {
        queue.async { [self] in
            if let consent = newConfig.trackingConsent {
                config.trackingConsent = consent
                storage.set(consent.rawValue, forKey: SDKConstants.StorageKeys.trackingConsent)

                if consent == .granted {
                    flushLocked()
                } else if consent == .denied {
                    eventQueue.removeAll()
                    queueStorage.save(eventQueue)
                }
            }

            if let debug = newConfig.debug {
                config.debug = debug
                logger.setDebug(debug)
            }

            if let environment = newConfig.environment {
                config.environment = environment
            }
        }
    }

    /// Flushes the event queue, sending all pending events immediately.
    ///
    /// - Example:
    /// ```swift
    /// altertable.flush()
    /// ```
    public func flush() {
        queue.async { [self] in
            flushLocked()
        }
    }

    // MARK: - Internal accessors for testing

    func getDistinctId() -> String {
        queue.sync { distinctId }
    }

    func getAnonymousId() -> String? {
        queue.sync { anonymousId }
    }

    func setRetryBaseDelay(_ delay: Double) {
        requester.retryBaseDelay = delay
    }

    func setMaxQueueSize(_ size: Int) {
        queue.async { self.maxQueueSize = size }
    }

    // MARK: - Private — must only be called from within `queue`

    private func enqueue(_ request: QueuedRequest) {
        if config.trackingConsent == .denied {
            return
        }

        if eventQueue.count >= maxQueueSize {
            eventQueue.removeFirst()
            logger.warn("Event queue full — oldest event dropped.")
        }

        eventQueue.append(request)
        // Persist only when consent is pending (events may survive app restart before
        // consent is granted). When consent is granted, flushLocked() clears the queue
        // and persists the empty state immediately after, so per-enqueue writes are
        // redundant and expensive for high-frequency tracking.
        if config.trackingConsent != .granted {
            queueStorage.save(eventQueue)
        }
        flushLocked()
    }

    private func flushLocked() {
        guard !eventQueue.isEmpty else { return }
        guard config.trackingConsent == .granted else { return }

        let batch = eventQueue
        eventQueue.removeAll()
        queueStorage.save(eventQueue)

        for request in batch {
            sendRequest(request)
        }
    }

    private func sendRequest(_ request: QueuedRequest) {
        // Snapshot baseURL here, on the serial queue, before handing off to Requester
        // which may execute on arbitrary URLSession callback threads.
        let baseURL = config.baseURL

        let completion: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                break
            case let .failure(error):
                self.queue.async {
                    // Only re-enqueue transient failures (handled by Requester's retry
                    // logic for 5xx/429/network errors). By the time completion(.failure)
                    // is called here, Requester has already exhausted its retries, so we
                    // do not attempt to re-enqueue — doing so would cause an infinite loop
                    // for permanent client errors (4xx).
                    // Skip if consent was revoked while the request was in flight.
                    guard self.config.trackingConsent != .denied else { return }
                    self.config.onError?(error)
                }
            }
        }

        switch request {
        case let .track(payload):
            requester.send(payload, baseURL: baseURL, completion: completion)
        case let .identify(payload):
            requester.send(payload, baseURL: baseURL, completion: completion)
        case let .alias(payload):
            requester.send(payload, baseURL: baseURL, completion: completion)
        }
    }

    /// Must be called from within `queue`.
    private func resetLocked(resetDeviceId: Bool = false) {
        sessionManager.renewSession()
        let newDistinct = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
        distinctId = newDistinct
        anonymousId = nil

        storage.set(newDistinct, forKey: SDKConstants.StorageKeys.distinctId)
        storage.removeObject(forKey: SDKConstants.StorageKeys.anonymousId)

        if resetDeviceId {
            let newDevice = SDKConstants.prefixDeviceId + "-" + UUID().uuidString
            deviceId = newDevice
            storage.set(newDevice, forKey: SDKConstants.StorageKeys.deviceId)
        }

        eventQueue.removeAll()
        queueStorage.save(eventQueue)
    }

    private func setupLifecycleHooks() {
        #if canImport(UIKit)
            if config.flushOnBackground {
                backgroundObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.flush()
                }
            }
        #endif
    }
}

#if canImport(Combine)
    extension Altertable: ObservableObject {}
#endif
