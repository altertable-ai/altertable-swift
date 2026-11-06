//
//  StorageTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

final class StorageTests: XCTestCase {
    private final class InMemoryStorage: Storage {
        var values: [String: String] = [:]
        var failWrites = false
        var failedKeys: Set<String> = []
        var failWriteNumber: Int?
        private var writeCount = 0
        func string(forKey key: String) -> String? { values[key] }
        func set(_ value: String, forKey key: String) {
            writeCount += 1
            if !failWrites, !failedKeys.contains(key), failWriteNumber != writeCount {
                values[key] = value
            }
        }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }
    private var storage: UserDefaultsStorage!
    private let testKey = "atbl.test.storage_key"

    override func setUp() {
        super.setUp()
        storage = UserDefaultsStorage()
        UserDefaults.standard.removeObject(forKey: testKey)
        TestSupport.removeDefaultPersistedEventQueue()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        TestSupport.removeDefaultPersistedEventQueue()
        storage = nil
        super.tearDown()
    }

    func testSetAndGet() {
        storage.set("hello", forKey: testKey)
        XCTAssertEqual(storage.string(forKey: testKey), "hello")
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(storage.string(forKey: testKey))
    }

    func testRemoveObject() {
        storage.set("value", forKey: testKey)
        storage.removeObject(forKey: testKey)
        XCTAssertNil(storage.string(forKey: testKey))
    }

    func testOverwriteValue() {
        storage.set("first", forKey: testKey)
        storage.set("second", forKey: testKey)
        XCTAssertEqual(storage.string(forKey: testKey), "second")
    }

    func testLegacyMigrationRetriesFailedWritesWithoutMixingDestination() {
        let backing = InMemoryStorage()
        backing.values[SDKConstants.StorageKeys.distinctId] = "legacy-user"
        backing.failWrites = true
        let failed = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertFalse(failed.shouldMigrateLegacy)
        XCTAssertFalse(failed.legacyMigrationSucceeded)

        backing.failWrites = false
        let recovered = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertTrue(recovered.legacyMigrationSucceeded)
        XCTAssertEqual(recovered.string(forKey: SDKConstants.StorageKeys.distinctId), "legacy-user")

        let other = NamespacedStorage(storage: backing, apiKey: "other")
        XCTAssertNil(other.string(forKey: SDKConstants.StorageKeys.distinctId))
    }

    func testExistingDestinationWinsOverLegacyState() {
        let backing = InMemoryStorage()
        backing.values[SDKConstants.StorageKeys.distinctId] = "legacy-user"
        backing.values["atbl.v2.owner.\(SDKConstants.StorageKeys.deviceId)"] = "existing-device"
        let destination = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertFalse(destination.shouldMigrateLegacy)
        XCTAssertEqual(destination.string(forKey: SDKConstants.StorageKeys.deviceId), "existing-device")
        XCTAssertNil(destination.string(forKey: SDKConstants.StorageKeys.distinctId))
    }

    func testPartialCopyRetriesSameOwnerAndDoesNotLeakToSecondKey() {
        let backing = InMemoryStorage()
        backing.values[SDKConstants.StorageKeys.deviceId] = "legacy-device"
        backing.values[SDKConstants.StorageKeys.distinctId] = "legacy-user"
        backing.failedKeys.insert("atbl.v2.owner.\(SDKConstants.StorageKeys.distinctId)")

        let failed = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertFalse(failed.legacyMigrationSucceeded)
        XCTAssertEqual(backing.string(forKey: "atbl.v2.legacy_owner"), "owner")
        XCTAssertEqual(backing.string(forKey: "atbl.v2.legacy_adoption_decision"), "adopt")
        XCTAssertEqual(failed.string(forKey: SDKConstants.StorageKeys.deviceId), "legacy-device")
        XCTAssertNil(failed.string(forKey: SDKConstants.StorageKeys.distinctId))

        let second = NamespacedStorage(storage: backing, apiKey: "second")
        XCTAssertTrue(second.legacyMigrationSucceeded)
        XCTAssertNil(second.string(forKey: SDKConstants.StorageKeys.deviceId))

        backing.failedKeys.removeAll()
        let retried = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertTrue(retried.legacyMigrationSucceeded)
        XCTAssertEqual(retried.string(forKey: SDKConstants.StorageKeys.deviceId), "legacy-device")
        XCTAssertEqual(retried.string(forKey: SDKConstants.StorageKeys.distinctId), "legacy-user")
    }

    func testCompletionReadbackFailureLeavesAdoptionRetryable() {
        let backing = InMemoryStorage()
        backing.values[SDKConstants.StorageKeys.distinctId] = "legacy-user"
        let migration = NamespacedStorage(storage: backing, apiKey: "owner")
        backing.failedKeys.insert("atbl.v2.legacy_adoption_complete")
        XCTAssertFalse(migration.completeLegacyAdoption(queueMigrationSucceeded: true))

        backing.failedKeys.removeAll()
        let retry = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertTrue(retry.shouldMigrateLegacy)
        XCTAssertTrue(retry.completeLegacyAdoption(queueMigrationSucceeded: true))
    }

    func testDecisionWriteFailureCanOnlyBeCompletedByRecordedOwner() {
        let backing = InMemoryStorage()
        backing.values[SDKConstants.StorageKeys.distinctId] = "legacy-user"
        backing.failedKeys.insert("atbl.v2.legacy_adoption_decision")
        let failed = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertFalse(failed.legacyMigrationSucceeded)
        XCTAssertEqual(backing.string(forKey: "atbl.v2.legacy_owner"), "owner")
        XCTAssertNil(backing.string(forKey: "atbl.v2.legacy_adoption_decision"))

        backing.failedKeys.removeAll()
        let other = NamespacedStorage(storage: backing, apiKey: "other")
        XCTAssertNil(other.string(forKey: SDKConstants.StorageKeys.distinctId))
        let retry = NamespacedStorage(storage: backing, apiKey: "owner")
        XCTAssertTrue(retry.legacyMigrationSucceeded)
        XCTAssertEqual(retry.string(forKey: SDKConstants.StorageKeys.distinctId), "legacy-user")
    }

    func testExistingProductQueueWinsOverLegacyState() {
        let backing = InMemoryStorage()
        backing.values[SDKConstants.StorageKeys.distinctId] = "legacy-user"
        let destination = NamespacedStorage(storage: backing, apiKey: "owner", hasProductQueueDestination: true)
        XCTAssertFalse(destination.shouldMigrateLegacy)
        XCTAssertNil(destination.string(forKey: SDKConstants.StorageKeys.distinctId))
        XCTAssertEqual(backing.string(forKey: "atbl.v2.legacy_adoption_decision"), "destination")
    }
}
