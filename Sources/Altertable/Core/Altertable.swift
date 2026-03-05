//
//  Altertable.swift
//  Altertable
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public class Altertable {
    private var config: AltertableConfig
    private let sessionManager: SessionManager
    private let storage: Storage
    private let requester: Requester
    
    // Identity state
    private var distinctId: String
    private var anonymousId: String?
    private var deviceId: String
    
    // Queue
    private var queue: [TrackPayload] = []
    
    public init(apiKey: String, config: AltertableConfig? = nil) {
        let defaultConfig = AltertableConfig(apiKey: apiKey)
        self.config = config ?? defaultConfig
        
        let keychain = SecureStorage()
        let defaults = UserDefaultsStorage()
        self.storage = FallbackStorage(primary: keychain, fallback: defaults)
        
        self.sessionManager = SessionManager(storage: self.storage)
        self.requester = Requester(config: self.config)
        
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
        
        self.anonymousId = storage.string(forKey: "atbl.anonymous_id")
        
        setupLifecycleHooks()
    }
    
    public func track(event: String, properties: [String: AnyCodable] = [:]) {
        let timestamp = Date().ISO8601Format()
        let sessionId = sessionManager.getSessionId()
        
        let payload = TrackPayload(
            timestamp: timestamp,
            event: event,
            environment: config.environment,
            deviceId: deviceId,
            distinctId: distinctId,
            anonymousId: anonymousId,
            sessionId: sessionId,
            properties: properties
        )
        
        // Add default properties (lib version etc)
        // TODO: Merge lib properties
        
        queue.append(payload)
        flush()
    }
    
    public func identify(userId: String, traits: [String: AnyCodable] = [:]) {
        if distinctId != userId {
            anonymousId = distinctId
            distinctId = userId
            storage.set(userId, forKey: "atbl.distinct_id")
            storage.set(anonymousId!, forKey: "atbl.anonymous_id")
        }
        
        // Send identify event (TODO: IdentifyPayload)
    }
    
    public func alias(newUserId: String) {
        // Send alias event (TODO: AliasPayload)
    }
    
    public func reset() {
        sessionManager.renewSession()
        let newDistinct = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
        self.distinctId = newDistinct
        self.anonymousId = nil
        
        storage.set(newDistinct, forKey: "atbl.distinct_id")
        storage.removeObject(forKey: "atbl.anonymous_id")
    }
    
    public func flush() {
        guard !queue.isEmpty else { return }
        
        let batch = queue // Capture current queue
        queue.removeAll() // Clear queue (optimistic)
        
        // For now simple one-by-one send, Phase 11 will optimize
        for event in batch {
            requester.send(event) { [weak self] result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    self?.config.onError?(error)
                    // TODO: Re-queue on recoverable error
                }
            }
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
