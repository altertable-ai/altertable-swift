//
//  Altertable.swift
//  Altertable
//

import Foundation

public class Altertable {
    private var config: AltertableConfig
    private let sessionManager: SessionManager
    
    // Identity state
    private var distinctId: String
    private var anonymousId: String?
    private var deviceId: String
    
    // Queue
    private var queue: [TrackPayload] = []
    
    public init(apiKey: String, config: AltertableConfig? = nil) {
        let defaultConfig = AltertableConfig(apiKey: apiKey)
        self.config = config ?? defaultConfig
        self.sessionManager = SessionManager()
        
        // Load identity from storage or generate new
        self.deviceId = SDKConstants.prefixDeviceId + "-" + UUID().uuidString
        self.distinctId = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
        self.anonymousId = nil
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
        
        queue.append(payload)
        flush()
    }
    
    public func identify(userId: String, traits: [String: AnyCodable] = [:]) {
        if distinctId != userId {
            anonymousId = distinctId
            distinctId = userId
        }
        
        // Send identify event
    }
    
    public func alias(newUserId: String) {
        // Send alias event
    }
    
    public func reset() {
        sessionManager.renewSession()
        distinctId = SDKConstants.prefixAnonymousId + "-" + UUID().uuidString
        anonymousId = nil
    }
    
    private func flush() {
        // Send to API
    }
}
