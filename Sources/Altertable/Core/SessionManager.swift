//
//  SessionManager.swift
//  Altertable
//

import Foundation

class SessionManager {
    private var lastEventTime: Date?
    private var sessionId: String?
    
    init() {
        // Load from storage if needed
    }
    
    func getSessionId() -> String {
        if let last = lastEventTime, Date().timeIntervalSince(last) > SDKConstants.sessionExpirationTime {
            renewSession()
        }
        
        if sessionId == nil {
            renewSession()
        }
        
        lastEventTime = Date()
        return sessionId!
    }
    
    func renewSession() {
        sessionId = SDKConstants.prefixSessionId + "-" + UUID().uuidString
        lastEventTime = Date()
    }
}
