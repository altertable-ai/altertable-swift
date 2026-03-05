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
    
    // Identity state
    private var distinctId: String
    private var anonymousId: String?
    private var deviceId: String
    
    // Queue
    // We use Any to store different payload types in the queue for now
    // Ideally we would use an enum or protocol, but JSON serialization of mixed types in a queue array 
    // is simpler if we treat flush as generic.
    // However, to keep it strongly typed as per spec "Typed models ... are first-class",
    // let's define an enum for QueuedItem if we want to mix them.
    // BUT the spec Phase 8 says "Event Queue ... Buffer as fully-built payloads".
    // Let's use a wrapper enum.
    
    private var queue: [QueuedRequest] = []
    
    enum QueuedRequest {
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
        
        queue.append(.track(payload))
        flush()
    }
    
    public func identify(userId: String, traits: [String: AnyCodable] = [:]) {
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
        
        queue.append(.identify(payload))
        flush()
    }
    
    public func alias(newUserId: String) {
        let payload = AliasPayload(
            environment: config.environment,
            deviceId: deviceId,
            distinctId: distinctId,
            anonymousId: anonymousId,
            newUserId: newUserId
        )
        
        queue.append(.alias(payload))
        flush()
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
