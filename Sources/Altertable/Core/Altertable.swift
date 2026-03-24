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

public final class Altertable: @unchecked Sendable {
    /// All mutable state is accessed exclusively on this queue.
    private let queue = DispatchQueue(label: "ai.altertable.sdk", qos: .utility)

    private var config: AltertableConfig

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
    internal var maxQueueSize: Int = SDKConstants.maxQueueSize

    /// NotificationCenter token for lifecycle hooks
    private var backgroundObserver: AnyObject?
    private var flushTimer: DispatchSourceTimer?

    private var screenViewIntegration: ScreenViewIntegration?

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
        var internalConfig = config ?? AltertableConfig()

        self.config = internalConfig
        logger = Logger(isDebug: internalConfig.debug)
        queueStorage = QueueStorage(logger: logger)
        storage = UserDefaultsStorage()
        sessionManager = SessionManager(storage: storage)
        requester = Requester(apiKey: apiKey, requestTimeout: internalConfig.requestTimeout, session: session)

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
        setupPeriodicFlush()
        setupScreenViews(enabled: internalConfig.captureScreenViews)
    }

    deinit {
        if let token = backgroundObserver {
            NotificationCenter.default.removeObserver(token)
        }
        flushTimer?.cancel()
        flushTimer = nil
        // Remove any waiting callbacks if we never held ownership
        ScreenViewIntegration.dequeueCallback(ifOwner: self)
        // Release screen view integration ownership
        ScreenViewIntegration.releaseOwnership(ifOwner: self)
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
    public func track(event: String, properties: [String: JSONValue] = [:]) {
        queue.async { [self] in
            let timestamp = Date().iso8601String()
            let sessionId = sessionManager.currentSessionId()

            var finalProperties = Context.getSystemProperties()

            if let release = config.release ??
                (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            {
                finalProperties[SDKConstants.propertyRelease] = JSONValue(release)
            }

            finalProperties.merge(properties) { _, new in new }

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
    public func identify(userId: String, traits: [String: JSONValue] = [:]) {
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
                _reset()
            }

            if distinctId != userId {
                anonymousId = distinctId
                distinctId = userId
                storage.set(userId, forKey: SDKConstants.StorageKeys.distinctId)
                storage.set(anonymousId!, forKey: SDKConstants.StorageKeys.anonymousId)
            }

            let payload = IdentifyPayload(
                timestamp: Date().iso8601String(),
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
                timestamp: Date().iso8601String(),
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
    public func updateTraits(_ traits: [String: JSONValue]) {
        queue.async { [self] in
            guard anonymousId != nil else {
                logger.warn("User must be identified with identify() before updating traits.")
                return
            }

            let payload = IdentifyPayload(
                timestamp: Date().iso8601String(),
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
            _reset(resetDeviceId: resetDeviceId)

            if resetTrackingConsent {
                config.trackingConsent = AltertableConfig.defaultTrackingConsent
                storage.set(
                    AltertableConfig.defaultTrackingConsent.rawValue,
                    forKey: SDKConstants.StorageKeys.trackingConsent
                )
            }
        }
    }

    /// Updates the configuration after initialization.
    ///
    /// - Parameter updates: A closure that modifies the configuration in place.
    ///
    /// - Example:
    /// ```swift
    /// altertable.configure { config in
    ///     config.trackingConsent = .granted
    ///     config.debug = true
    /// }
    /// ```
    public func configure(_ updates: @escaping (inout AltertableConfig) -> Void) {
        queue.async { [self] in
            let previousConsent = config.trackingConsent
            // Snapshot init-only fields that cannot be changed after initialization
            let frozenTimeout = config.requestTimeout
            let frozenFlush = config.flushOnBackground
            let previousFlushInterval = config.flushInterval

            updates(&config)

            // Restore init-only fields (they are only read at init time)
            config.requestTimeout = frozenTimeout
            config.flushOnBackground = frozenFlush

            // Handle tracking consent changes
            if config.trackingConsent != previousConsent {
                storage.set(config.trackingConsent.rawValue, forKey: SDKConstants.StorageKeys.trackingConsent)

                if config.trackingConsent == .granted {
                    _flush()
                } else if config.trackingConsent == .denied {
                    eventQueue.removeAll()
                    queueStorage.save(eventQueue)
                }
            }

            if config.flushInterval != previousFlushInterval {
                setupPeriodicFlush()
            }

            // Handle debug changes
            logger.setDebug(config.debug)

            // Handle screen view capture changes
            if config.captureScreenViews != (screenViewIntegration?.isEnabled ?? false) {
                updateScreenViewCapture(enabled: config.captureScreenViews)
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
            _flush()
        }
    }

    // MARK: - Internal accessors for testing

    func currentDistinctId() -> String {
        queue.sync { distinctId }
    }

    func currentAnonymousId() -> String? {
        queue.sync { anonymousId }
    }

    func setRetryBaseDelay(_ delay: Double) {
        requester.retryBaseDelay = delay
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
        if config.trackingConsent != .granted {
            queueStorage.save(eventQueue)
            return
        }

        if eventQueue.count >= config.flushAt {
            _flush()
        }
    }

    /// Queue-isolated flush implementation. Must only be called from within `queue`.
    private func _flush() {
        guard !eventQueue.isEmpty else { return }
        guard config.trackingConsent == .granted else { return }

        let batch = eventQueue
        eventQueue.removeAll()
        queueStorage.save(eventQueue)

        sendBatches(batch)
    }

    private func sendBatches(_ requests: [QueuedRequest]) {
        let tracks = requests.compactMap { request -> TrackPayload? in
            if case let .track(payload) = request { return payload }
            return nil
        }
        let identifies = requests.compactMap { request -> IdentifyPayload? in
            if case let .identify(payload) = request { return payload }
            return nil
        }
        let aliases = requests.compactMap { request -> AliasPayload? in
            if case let .alias(payload) = request { return payload }
            return nil
        }

        chunked(tracks, size: config.maxBatchSize).forEach { sendTrackBatch($0) }
        chunked(identifies, size: config.maxBatchSize).forEach { sendIdentifyBatch($0) }
        chunked(aliases, size: config.maxBatchSize).forEach { sendAliasBatch($0) }
    }

    private func sendRequest(_ request: QueuedRequest) {
        let baseURL = config.baseURL
        let completion = makeCompletion(requeue: [request])

        switch request {
        case let .track(payload):
            requester.send(payload, baseURL: baseURL, completion: completion)
        case let .identify(payload):
            requester.send(payload, baseURL: baseURL, completion: completion)
        case let .alias(payload):
            requester.send(payload, baseURL: baseURL, completion: completion)
        }
    }

    private func sendTrackBatch(_ payloads: [TrackPayload]) {
        guard !payloads.isEmpty else { return }
        let requests = payloads.map { QueuedRequest.track($0) }
        requester.sendBatch(payloads, baseURL: config.baseURL, completion: makeCompletion(requeue: requests))
    }

    private func sendIdentifyBatch(_ payloads: [IdentifyPayload]) {
        guard !payloads.isEmpty else { return }
        let requests = payloads.map { QueuedRequest.identify($0) }
        requester.sendBatch(payloads, baseURL: config.baseURL, completion: makeCompletion(requeue: requests))
    }

    private func sendAliasBatch(_ payloads: [AliasPayload]) {
        guard !payloads.isEmpty else { return }
        let requests = payloads.map { QueuedRequest.alias($0) }
        requester.sendBatch(payloads, baseURL: config.baseURL, completion: makeCompletion(requeue: requests))
    }

    private func makeCompletion(requeue requests: [QueuedRequest]) -> (Result<Void, Error>) -> Void {
        { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                break
            case let .failure(error):
                self.queue.async {
                    guard self.config.trackingConsent != .denied else { return }
                    self.config.onError?(error)
                    self.eventQueue.append(contentsOf: requests)
                    self.queueStorage.save(self.eventQueue)
                }
            }
        }
    }

    private func chunked<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0 ..< Swift.min($0 + size, array.count)])
        }
    }

    /// Queue-isolated reset implementation. Must only be called from within `queue`.
    private func _reset(resetDeviceId: Bool = false) {
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

    private func setupPeriodicFlush() {
        flushTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in
            self?._flush()
        }
        timer.resume()
        flushTimer = timer
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

    internal func setupScreenViews(enabled: Bool) {
        // Only set up auto-capture on platforms that support it
        #if canImport(UIKit) && !os(watchOS)
            guard enabled else { return }

            // Create a callback that will be invoked when ownership becomes available
            let callback: () -> Void = { [weak self] in
                guard let self = self else { return }
                self.queue.async { [self] in
                    // Retry claiming ownership
                    guard ScreenViewIntegration.claimOwnership(client: self, logger: self.logger) else {
                        return
                    }
                    guard let integration = ScreenViewIntegration.shared else {
                        self.logger.warn("Failed to get screen view integration instance.")
                        return
                    }
                    integration.installIfNeeded()
                    self.screenViewIntegration = integration
                }
            }

            guard ScreenViewIntegration.claimOwnership(client: self, logger: logger, onFailure: callback) else {
                logger.warn(
                    "Another Altertable instance already owns screen view auto-capture. "
                    + "Will claim when available."
                )
                return
            }

            guard let integration = ScreenViewIntegration.shared else {
                logger.warn("Failed to get screen view integration instance.")
                return
            }
            integration.installIfNeeded()
            screenViewIntegration = integration
        #else
            // On non-UIKit platforms, screen(name:) still works, but auto-capture is not available
            // SwiftUI .screenView() modifier can still be used with explicit client parameter
            if enabled {
                logger.log(
                    "Screen view auto-capture is only available on UIKit platforms. "
                    + "Use screen(name:) or .screenView(name:client:) for manual tracking."
                )
            }
        #endif
    }

    private func updateScreenViewCapture(enabled: Bool) {
        #if canImport(UIKit) && !os(watchOS)
            if enabled {
                if screenViewIntegration == nil {
                    // Create a callback that will be invoked when ownership becomes available
                    let callback: () -> Void = { [weak self] in
                        guard let self = self else { return }
                        self.queue.async { [self] in
                            // Retry claiming ownership
                            guard ScreenViewIntegration.claimOwnership(client: self, logger: self.logger) else {
                                return
                            }
                            guard let integration = ScreenViewIntegration.shared else {
                                self.logger.warn("Failed to get screen view integration instance.")
                                return
                            }
                            integration.installIfNeeded()
                            self.screenViewIntegration = integration
                        }
                    }

                    guard ScreenViewIntegration.claimOwnership(client: self, logger: logger, onFailure: callback) else {
                        logger.warn(
                            "Another Altertable instance already owns screen view auto-capture. "
                            + "Will claim when available."
                        )
                        return
                    }
                    guard let integration = ScreenViewIntegration.shared else {
                        logger.warn("Failed to get screen view integration instance.")
                        return
                    }
                    integration.installIfNeeded()
                    screenViewIntegration = integration
                } else {
                    // Re-enable if we already own it
                    ScreenViewIntegration.reEnable(ifOwner: self)
                    screenViewIntegration?.installIfNeeded()
                }
            } else {
                // Disable and release ownership
                ScreenViewIntegration.releaseOwnership(ifOwner: self)
                screenViewIntegration = nil
            }
        #else
            if enabled {
                logger.log(
                    "Screen view auto-capture is only available on UIKit platforms. "
                    + "Use screen(name:) or .screenView(name:client:) for manual tracking."
                )
            }
        #endif
    }
}

#if canImport(Combine)
    // Conformance to ObservableObject enables SwiftUI dependency injection via @StateObject/@EnvironmentObject.
    // Note: This class does not use @Published properties, so it won't trigger view updates.
    extension Altertable: ObservableObject {}
#endif
