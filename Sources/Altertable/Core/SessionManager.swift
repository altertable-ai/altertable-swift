//
//  SessionManager.swift
//  Altertable
//

import Foundation

class SessionManager {
    private let storage: Storage
    private var lastEventTime: Date?
    private var sessionId: String?
    
    init(storage: Storage) {
        self.storage = storage
        self.sessionId = storage.string(forKey: "atbl.session_id")
        
        if let lastEvent = storage.string(forKey: "atbl.last_event_at"),
           let interval = TimeInterval(lastEvent) {
            self.lastEventTime = Date(timeIntervalSince1970: interval)
        }
    }
    
    func getSessionId() -> String {
        if let last = lastEventTime, Date().timeIntervalSince(last) > SDKConstants.sessionExpirationTime {
            renewSession()
        }
        
        if sessionId == nil {
            renewSession()
        }
        
        // Update last event time
        let now = Date()
        lastEventTime = now
        storage.set(String(now.timeIntervalSince1970), forKey: "atbl.last_event_at")
        
        return sessionId!
    }
    
    func renewSession() {
        let newId = SDKConstants.prefixSessionId + "-" + UUID().uuidString
        self.sessionId = newId
        storage.set(newId, forKey: "atbl.session_id")
        
        let now = Date()
        self.lastEventTime = now
        storage.set(String(now.timeIntervalSince1970), forKey: "atbl.last_event_at")
    }
}
