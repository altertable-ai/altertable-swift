//
//  SessionManagerTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

/// In-memory storage for isolated SessionManager tests.
private final class InMemoryStorage: Storage {
    private var store: [String: String] = [:]

    func string(forKey key: String) -> String? {
        store[key]
    }

    func set(_ value: String, forKey key: String) {
        store[key] = value
    }

    func removeObject(forKey key: String) {
        store.removeValue(forKey: key)
    }
}

final class SessionManagerTests: XCTestCase {
    private var storage: InMemoryStorage!
    private var manager: SessionManager!

    override func setUp() {
        super.setUp()
        storage = InMemoryStorage()
        manager = SessionManager(storage: storage)
    }

    override func tearDown() {
        manager = nil
        storage = nil
        super.tearDown()
    }

    func testGetSessionIdReturnsConsistentId() {
        let id1 = manager.getSessionId()
        let id2 = manager.getSessionId()
        XCTAssertEqual(id1, id2, "Session ID should not change between rapid calls")
    }

    func testSessionIdHasCorrectPrefix() {
        let id = manager.getSessionId()
        let expectedPrefix = SDKConstants.prefixSessionId + "-"
        XCTAssertTrue(
            id.hasPrefix(expectedPrefix),
            "Session ID should start with '\(expectedPrefix)'"
        )
    }

    func testRenewSessionChangesId() {
        let original = manager.getSessionId()
        manager.renewSession()
        let renewed = manager.getSessionId()
        XCTAssertNotEqual(original, renewed, "Session ID should change after renewSession()")
    }

    func testSessionIdIsPersistedToStorage() {
        let id = manager.getSessionId()
        XCTAssertEqual(storage.string(forKey: SDKConstants.StorageKeys.sessionId), id)
    }

    func testSessionRestoredFromStorage() {
        let id = manager.getSessionId()
        // Create a new manager with the same storage — it should restore the session.
        let manager2 = SessionManager(storage: storage)
        // The stored session should not have expired (just created), so the ID is the same.
        let restored = manager2.getSessionId()
        XCTAssertEqual(id, restored, "New manager should restore session from storage")
    }

    func testExpiredSessionIsRenewed() {
        // Simulate a last-event timestamp far in the past.
        let pastTimestamp = Date().timeIntervalSince1970 - SDKConstants.sessionExpirationTime - 1
        storage.set(String(pastTimestamp), forKey: SDKConstants.StorageKeys.lastEventAt)

        let originalId = manager.getSessionId()
        // Force expiry by writing an old timestamp then creating a fresh manager.
        let freshStorage = InMemoryStorage()
        freshStorage.set(originalId, forKey: SDKConstants.StorageKeys.sessionId)
        freshStorage.set(String(pastTimestamp), forKey: SDKConstants.StorageKeys.lastEventAt)

        let expiredManager = SessionManager(storage: freshStorage)
        let newId = expiredManager.getSessionId()
        XCTAssertNotEqual(originalId, newId, "Session should be renewed after expiration")
    }
}
