//
//  SessionManager.swift
//  Altertable
//

import Foundation

final class SessionManager {
    private let storage: Storage
    private var lastEventTime: Date?
    private var sessionId: String

    init(storage: Storage) {
        self.storage = storage
        if let stored = storage.string(forKey: SDKConstants.StorageKeys.sessionId) {
            sessionId = stored
        } else {
            let newId = SDKConstants.prefixSessionId + "-" + UUID().uuidString
            sessionId = newId
            storage.set(newId, forKey: SDKConstants.StorageKeys.sessionId)
        }

        if let lastEvent = storage.string(forKey: SDKConstants.StorageKeys.lastEventAt),
           let interval = TimeInterval(lastEvent)
        {
            lastEventTime = Date(timeIntervalSince1970: interval)
        }
    }

    func currentSessionId() -> String {
        if let last = lastEventTime, Date().timeIntervalSince(last) > SDKConstants.sessionExpirationTime {
            renewSession()
        }

        let now = Date()
        lastEventTime = now
        storage.set(String(now.timeIntervalSince1970), forKey: SDKConstants.StorageKeys.lastEventAt)

        return sessionId
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
