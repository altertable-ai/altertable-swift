//
//  Altertable.swift
//  Altertable
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class Altertable {
    private var config: AltertableConfig
    private let sessionManager: SessionManager
    private let storage: Storage
    private let requester: Requester
    private let logger: Logger
    
    // Identity state
    private var distinctId: String
    private var anonymousId: String?
    private var deviceId: String
    
    // Queue
    private var queue: [QueuedRequest] = []
    private let queueStorage: QueueStorage
    
    enum QueuedRequest: Codable {
        case track(TrackPayload)
        case identify(IdentifyPayload)
        case alias(AliasPayload)
    }
    
    public convenience init(apiKey: String, config: AltertableConfig? = nil) {
        self.init(apiKey: apiKey, config: config, session: nil)
    }
    
    init(apiKey: String, config: AltertableConfig? = nil, session: URLSession? = nil) {
        let defaultConfig = AltertableConfig(apiKey: apiKey)
        self.config = config ?? defaultConfig
        self.logger = Logger(isDebug: self.config.debug)
        self.queueStorage = QueueStorage(logger: self.logger)
        
        let keychain = SecureStorage()
        let defaults = UserDefaultsStorage()
        self.storage = FallbackStorage(primary: keychain, fallback: defaults)
        
        self.sessionManager = SessionManager(storage: self.storage)
        self.requester = Requester(config: self.config, session: session)
        
        // Load identity from storage or generate new
        if let storedDevice = storage.string(forKey: "atbl.device_id") {
            self.deviceId = storedDevice
        } else {
            let newDevice = SDKConstants.prefixDeviceId + "-" + UUID().uuidString
            self.deviceId = newDevice
            storage.set(newDevice, forKey: "atbl.device_id")
        }
        
        if let storedDistinct = storage.string(forKey: "atbl.distinct_id") {
            self.distinctId = storedDistinct
        } else {
            let newDistinct = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
            self.distinctId = newDistinct
            storage.set(newDistinct, forKey: "atbl.distinct_id")
        }
        
        // Don't auto-read anonymousId if it's not set
        self.anonymousId = storage.string(forKey: "atbl.anonymous_id")
        
        // Load queue from disk
        self.queue = queueStorage.load()
        
        setupLifecycleHooks()
    }
    
    public func track(event: String, properties: [String: AnyCodable] = [:]) {
        let timestamp = Date().ISO8601Format()
        let sessionId = sessionManager.getSessionId()
        
        // Merge system properties
        var finalProperties = Context.getSystemProperties()
        
        // Add release if present
        if let release = config.release ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) {
            finalProperties[SDKConstants.propertyRelease] = AnyCodable(release)
        }
        
        // User properties overwrite system ones
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
    
    public func identify(userId: String, traits: [String: AnyCodable] = [:]) {
        do {
            try Validator.validateUserId(userId)
        } catch {
            logger.error(error.localizedDescription)
            return
        }
        
        // JS SDK Logic:
        // if (isIdentified() && userId !== getDistinctId()) { warn + reset }
        let isIdentified = anonymousId != nil // If anonymousId is set, we have identified previously
        
        if isIdentified && distinctId != userId {
            logger.warn("User \"\(userId)\" is already identified as \"\(distinctId)\". The session has been automatically reset. Use alias() to link the new ID to the existing one if intentional.")
            reset()
        }
        
        if distinctId != userId {
            anonymousId = distinctId
            distinctId = userId
            storage.set(userId, forKey: "atbl.distinct_id")
            storage.set(anonymousId!, forKey: "atbl.anonymous_id")
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
    
    public func alias(newUserId: String) {
        do {
            try Validator.validateUserId(newUserId)
        } catch {
            logger.error(error.localizedDescription)
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
    
    public func updateTraits(_ traits: [String: AnyCodable]) {
        if anonymousId == nil {
            logger.warn("User must be identified with identify() before updating traits.")
            return
        }
        
        // updateTraits is sent as an identify call with current IDs
        let payload = IdentifyPayload(
            environment: config.environment,
            deviceId: deviceId,
            distinctId: distinctId,
            anonymousId: anonymousId,
            traits: traits
        )
        
        enqueue(.identify(payload))
    }
    
    public func reset(resetDeviceId: Bool = false, resetTrackingConsent: Bool = false) {
        sessionManager.renewSession()
        let newDistinct = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
        self.distinctId = newDistinct
        self.anonymousId = nil
        
        storage.set(newDistinct, forKey: "atbl.distinct_id")
        storage.removeObject(forKey: "atbl.anonymous_id")
        
        if resetDeviceId {
            let newDevice = SDKConstants.prefixDeviceId + "-" + UUID().uuidString
            self.deviceId = newDevice
            storage.set(newDevice, forKey: "atbl.device_id")
        }
        
        // Spec Phase 10: "Clears the event queue."
        queue.removeAll()
        queueStorage.save(queue)
    }
    
    // Internal accessors for testing
    func getDistinctId() -> String {
        return distinctId
    }
    
    func getAnonymousId() -> String? {
        return anonymousId
    }
    
    public func configure(_ newConfig: PartialAltertableConfig) {
        if let consent = newConfig.trackingConsent {
            self.config.trackingConsent = consent
            // TODO: persist consent
            
            if consent == .granted {
                flush()
            } else if consent == .denied {
                queue.removeAll()
            }
        }
        // ... apply other config updates if needed
    }
    
    private func enqueue(_ request: QueuedRequest) {
        if config.trackingConsent == .denied {
            return
        }
        
        if queue.count >= SDKConstants.maxQueueSize {
            // Drop oldest
            queue.removeFirst()
            // TODO: Log warning
        }
        
        queue.append(request)
        queueStorage.save(queue)
        flush()
    }
    
    public func flush() {
        guard !queue.isEmpty else { return }
        
        // Check consent state
        guard config.trackingConsent == .granted else {
            return
        }
        
        let batch = queue // Capture current queue
        queue.removeAll() // Clear queue (optimistic)
        queueStorage.save(queue) // Persist cleared state
        
        // For now simple one-by-one send, Phase 11 will optimize
        for request in batch {
            switch request {
            case .track(let payload):
                requester.send(payload) { [weak self] result in self?.handleResult(result) }
            case .identify(let payload):
                requester.send(payload) { [weak self] result in self?.handleResult(result) }
            case .alias(let payload):
                requester.send(payload) { [weak self] result in self?.handleResult(result) }
            }
        }
    }
    
    private func handleResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            break
        case .failure(let error):
            self.config.onError?(error)
            // TODO: Re-queue on recoverable error
        }
    }
    
    private func setupLifecycleHooks() {
        #if canImport(UIKit)
        if config.flushOnBackground {
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.flush()
            }
        }
        #endif
    }
}
