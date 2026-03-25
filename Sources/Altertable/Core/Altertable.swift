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

    private let queueStorage: QueueStorage

    /// Lazy so the send closure can capture `[weak self]` after initialization completes.
    private lazy var batcher: Batcher = makeBatcher()
    internal var maxQueueSize: Int = SDKConstants.maxQueueSize

    /// NotificationCenter token for lifecycle hooks
    private var backgroundObserver: AnyObject?

    private var screenViewIntegration: ScreenViewIntegration?

    enum QueuedRequest: Codable {
        case track(TrackPayload)
        case identify(IdentifyPayload)
        case alias(AliasPayload)
    }

    private enum AltertableSendError: Error {
        case clientDeallocated
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

        // Persisted consent must drive runtime `config` before any public API checks `config.trackingConsent`.
        self.config = internalConfig

        let consentAtLaunch = internalConfig.trackingConsent
        queue.async { [self] in
            _ = batcher
            applyTrackingConsentToBatcherAndPersistQueue(consentAtLaunch)
        }

        setupLifecycleHooks()
        setupScreenViews(enabled: internalConfig.captureScreenViews)
    }

    deinit {
        if let token = backgroundObserver {
            NotificationCenter.default.removeObserver(token)
        }
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
    public func updateTraits(_ traits: [String: JSONValue]) {
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
            _reset(resetDeviceId: resetDeviceId)

            if resetTrackingConsent {
                config.trackingConsent = AltertableConfig.defaultTrackingConsent
                storage.set(
                    AltertableConfig.defaultTrackingConsent.rawValue,
                    forKey: SDKConstants.StorageKeys.trackingConsent
                )
                applyTrackingConsentToBatcherAndPersistQueue(config.trackingConsent)
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
            let frozenFlushThreshold = config.flushEventThreshold
            let frozenFlushIntervalMs = config.flushIntervalMs
            let frozenMaxBatchSize = config.maxBatchSize

            updates(&config)

            // Restore init-only fields (they are only read at init time)
            config.requestTimeout = frozenTimeout
            config.flushOnBackground = frozenFlush
            config.flushEventThreshold = frozenFlushThreshold
            config.flushIntervalMs = frozenFlushIntervalMs
            config.maxBatchSize = frozenMaxBatchSize

            batcher.updateFlushConfig(
                flushEventThreshold: frozenFlushThreshold,
                flushIntervalMs: frozenFlushIntervalMs,
                maxBatchSize: frozenMaxBatchSize
            )

            // Handle tracking consent changes
            if config.trackingConsent != previousConsent {
                storage.set(config.trackingConsent.rawValue, forKey: SDKConstants.StorageKeys.trackingConsent)
                applyTrackingConsentToBatcherAndPersistQueue(config.trackingConsent)
            }

            // Handle debug changes
            logger.setDebug(config.debug)

            // Handle screen view capture changes
            if config.captureScreenViews != (screenViewIntegration?.isEnabled ?? false) {
                updateScreenViewCapture(enabled: config.captureScreenViews)
            }
        }
    }

    /// Flushes buffered events as soon as possible when tracking consent is `.granted`.
    ///
    /// When consent is not granted, this is a no-op (no network); `completion` is still invoked on the SDK serial queue.
    ///
    /// - Parameter completion: Called on the SDK serial queue when the buffer is empty and all
    ///   in-flight batches for this flush have finished (or failed without requeue), or immediately
    ///   when consent is not granted.
    ///
    /// - Example:
    /// ```swift
    /// altertable.flush()
    /// altertable.flush {
    ///   // done
    /// }
    /// ```
    public func flush(completion: (() -> Void)? = nil) {
        queue.async { [self] in
            guard config.trackingConsent == .granted else {
                completion?()
                return
            }
            batcher.flush(completion: completion)
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

    /// Applies batching/timer behavior for `consent` and persists the queue snapshot.
    /// Callers must persist `SDKConstants.StorageKeys.trackingConsent` when the consent value itself changes.
    private func applyTrackingConsentToBatcherAndPersistQueue(_ consent: TrackingConsentState) {
        switch consent {
        case .granted:
            batcher.setSendingEnabled(true)
            batcher.startTimer()
            batcher.flush { [self] in
                queueStorage.save(batcher.snapshotForPersistence())
            }
        case .denied:
            batcher.setSendingEnabled(false)
            batcher.clear()
            queueStorage.save(batcher.snapshotForPersistence())
        case .pending, .dismissed:
            batcher.setSendingEnabled(false)
            batcher.stopTimer()
            queueStorage.save(batcher.snapshotForPersistence())
        }
    }

    private func enqueue(_ request: QueuedRequest) {
        if config.trackingConsent == .denied {
            return
        }

        if batcher.totalCount >= maxQueueSize {
            batcher.dropOldest()
            logger.warn("Event queue full — oldest event dropped.")
        }

        batcher.add(request, autoFlush: config.trackingConsent == .granted)
        // Persist only when consent is pending (events may survive app restart before
        // consent is granted). When consent is granted, successful sends empty the buffer
        // without per-enqueue disk writes.
        if config.trackingConsent != .granted {
            queueStorage.save(batcher.snapshotForPersistence())
        }
    }

    private func makeBatcher() -> Batcher {
        Batcher(
            initialQueue: queueStorage.load(),
            flushEventThreshold: config.flushEventThreshold,
            flushIntervalMs: config.flushIntervalMs,
            maxBatchSize: config.maxBatchSize,
            altertableQueue: queue,
            sendChunk: { [weak self] chunk, completion in
                guard let self else {
                    completion(.failure(AltertableSendError.clientDeallocated))
                    return
                }
                self.sendBatchedChunk(chunk: chunk, completion: completion)
            }
        )
    }

    private func sendBatchedChunk(
        chunk: Batcher.HomogeneousChunk,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let baseURL = config.baseURL

        let finish: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            self.queue.async {
                if case let .failure(error) = result {
                    if !Requester.isRetryableDeliveryError(error), self.config.trackingConsent != .denied {
                        self.config.onError?(error)
                    }
                }
                completion(result)
            }
        }

        switch chunk {
        case let .track(payloads):
            requester.sendBatch(payloads, baseURL: baseURL, completion: finish)
        case let .identify(payloads):
            requester.sendBatch(payloads, baseURL: baseURL, completion: finish)
        case let .alias(payloads):
            requester.sendBatch(payloads, baseURL: baseURL, completion: finish)
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

        batcher.clear()
        applyTrackingConsentToBatcherAndPersistQueue(config.trackingConsent)
    }

    private func setupLifecycleHooks() {
        #if canImport(UIKit)
            if config.flushOnBackground {
                backgroundObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    let backgroundTask = ExclusiveBackgroundTask()
                    backgroundTask.begin()
                    // `flush` only drains when consent is granted.
                    self.flush {
                        backgroundTask.end()
                    }
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

#if canImport(UIKit)
    /// Ensures `UIApplication.endBackgroundTask` runs at most once whether the task expires or `flush` completes first.
    private final class ExclusiveBackgroundTask {
        private var taskId: UIBackgroundTaskIdentifier = .invalid
        private let lock = NSLock()

        func begin() {
            lock.lock()
            taskId = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.end()
            }
            lock.unlock()
        }

        func end() {
            lock.lock()
            let id = taskId
            taskId = .invalid
            lock.unlock()
            guard id != .invalid else { return }
            if Thread.isMainThread {
                UIApplication.shared.endBackgroundTask(id)
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(id)
                }
            }
        }
    }
#endif

#if canImport(Combine)
    // Conformance to ObservableObject enables SwiftUI dependency injection via @StateObject/@EnvironmentObject.
    // Note: This class does not use @Published properties, so it won't trigger view updates.
    extension Altertable: ObservableObject {}
#endif
