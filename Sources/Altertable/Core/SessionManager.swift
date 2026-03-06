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
        sessionId = storage.string(forKey: SDKConstants.StorageKeys.sessionId)

        if let lastEvent = storage.string(forKey: SDKConstants.StorageKeys.lastEventAt),
           let interval = TimeInterval(lastEvent)
        {
            lastEventTime = Date(timeIntervalSince1970: interval)
        }
    }

    func getSessionId() -> String {
        if let last = lastEventTime, Date().timeIntervalSince(last) > SDKConstants.sessionExpirationTime {
            renewSession()
        }

        if sessionId == nil {
            renewSession()
        }

        let now = Date()
        lastEventTime = now
        storage.set(String(now.timeIntervalSince1970), forKey: SDKConstants.StorageKeys.lastEventAt)

        guard let id = sessionId else {
            // renewSession() always sets sessionId; this branch is unreachable.
            let fallback = SDKConstants.prefixSessionId + "-" + UUID().uuidString
            sessionId = fallback
            return fallback
        }
        return id
    }

    func renewSession() {
        let newId = SDKConstants.prefixSessionId + "-" + UUID().uuidString
        sessionId = newId
        storage.set(newId, forKey: SDKConstants.StorageKeys.sessionId)

        let now = Date()
        lastEventTime = now
        storage.set(String(now.timeIntervalSince1970), forKey: SDKConstants.StorageKeys.lastEventAt)
    }
}
