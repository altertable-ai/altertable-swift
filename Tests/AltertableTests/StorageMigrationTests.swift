//
//  StorageMigrationTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class StorageMigrationTests: XCTestCase {
    private var session: URLSession!
    private var events: [[String: Any]] = []
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        TestSupport.removeDefaultPersistedEventQueue()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.requestHandler = { [self] request in
            let body = try XCTUnwrap(request.httpBody)
            lock.lock()
            events += try TestJSON.objectArray(from: body)
            lock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session.invalidateAndCancel()
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        TestSupport.removeDefaultPersistedEventQueue()
        super.tearDown()
    }

    /// Seeds state as written by SDK versions that stored it without an API key.
    private func seedLegacyState() throws {
        UserDefaults.standard.set("legacy-user", forKey: SDKConstants.StorageKeys.distinctId)
        let queue = """
        [{"track":{"_0":{"timestamp":"2026-01-01T00:00:00Z","event":"Legacy Event","environment":"staging",
        "deviceId":"legacy-device","distinctId":"legacy-user","sessionId":"legacy-session","properties":{}}}}]
        """
        try Data(queue.utf8).write(to: QueueStorage.legacyFileURL)
    }

    private func start(apiKey: String, mode: TrackingMode = .product, onError: ((Error) -> Void)? = nil) -> Altertable {
        var config = AltertableConfig(mode: mode, onError: onError, captureScreenViews: false)
        config.applyUnitTestImmediateFlush()
        return Altertable(apiKey: apiKey, config: config, session: session)
    }

    private func flush(_ client: Altertable) {
        let finished = expectation(description: "Flush completed")
        client.flush { finished.fulfill() }
        wait(for: [finished], timeout: 2)
    }

    private func deliveredEvents() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func testProductStateAndQueueAreIsolatedByAPIKey() {
        var pending = AltertableConfig(trackingConsent: .pending, captureScreenViews: false)
        pending.applyUnitTestImmediateFlush()
        let first = Altertable(apiKey: "pk_first", config: pending, session: session)
        first.track(event: "First")
        let second = Altertable(apiKey: "pk_second", config: pending, session: session)
        second.track(event: "Second")
        XCTAssertNotEqual(first.currentDistinctId(), second.currentDistinctId())

        let restarted = start(apiKey: "pk_first")
        restarted.configure { $0.trackingConsent = .granted }
        flush(restarted)

        XCTAssertEqual(restarted.currentDistinctId(), first.currentDistinctId())
        XCTAssertEqual(deliveredEvents().compactMap { $0["event"] as? String }, ["First"])
    }

    func testFirstProductKeyAdoptsLegacyStateOnce() throws {
        try seedLegacyState()

        let audience = start(apiKey: "pk_audience", mode: .audience)
        flush(audience)
        let owner = start(apiKey: "pk_owner")
        flush(owner)

        XCTAssertEqual(owner.currentDistinctId(), "legacy-user")
        let legacyEvent = try XCTUnwrap(deliveredEvents().first)
        XCTAssertEqual(deliveredEvents().count, 1)
        XCTAssertEqual(legacyEvent["event"] as? String, "Legacy Event")
        XCTAssertEqual(legacyEvent["distinct_id"] as? String, "legacy-user")
        XCTAssertNil(legacyEvent["environment"])

        let other = start(apiKey: "pk_other")
        flush(other)
        XCTAssertNotEqual(other.currentDistinctId(), "legacy-user")

        let restartedOwner = start(apiKey: "pk_owner")
        flush(restartedOwner)
        XCTAssertEqual(restartedOwner.currentDistinctId(), "legacy-user")
        restartedOwner.reset()
        _ = restartedOwner.currentDistinctId()
        XCTAssertNotEqual(start(apiKey: "pk_owner").currentDistinctId(), "legacy-user")
        XCTAssertEqual(deliveredEvents().count, 1, "The drained legacy queue must not replay")
    }

    func testExistingScopedStateWinsOverLegacyState() throws {
        try seedLegacyState()
        UserDefaults.standard.set(
            "scoped-user",
            forKey: TestSupport.productStorageKey(SDKConstants.StorageKeys.distinctId, apiKey: "pk_owner")
        )

        let owner = start(apiKey: "pk_owner")
        flush(owner)
        let other = start(apiKey: "pk_other")
        flush(other)

        XCTAssertEqual(owner.currentDistinctId(), "scoped-user")
        XCTAssertNotEqual(other.currentDistinctId(), "legacy-user")
        XCTAssertTrue(deliveredEvents().isEmpty)
    }

    func testFailedLegacyCopyCollectsNothingAndRetriesForTheSameKeyOnly() throws {
        try seedLegacyState()
        // An unreadable legacy queue makes the copy fail.
        let legacyQueuePath = QueueStorage.legacyFileURL.path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacyQueuePath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyQueuePath) }

        let reported = expectation(description: "Migration failure reported")
        let failed = start(apiKey: "pk_owner", onError: { error in
            XCTAssertEqual(error.localizedDescription, ConfigurationError.storageMigration.localizedDescription)
            reported.fulfill()
        })
        failed.identify(userId: "user-during-failure")
        failed.track(event: "Dropped")
        flush(failed)
        wait(for: [reported], timeout: 1)
        XCTAssertTrue(deliveredEvents().isEmpty)

        let other = start(apiKey: "pk_other")
        flush(other)
        XCTAssertNotEqual(other.currentDistinctId(), "legacy-user")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyQueuePath)
        let retried = start(apiKey: "pk_owner")
        flush(retried)
        XCTAssertEqual(retried.currentDistinctId(), "legacy-user")
        XCTAssertEqual(deliveredEvents().compactMap { $0["event"] as? String }, ["Legacy Event"])
    }
}
