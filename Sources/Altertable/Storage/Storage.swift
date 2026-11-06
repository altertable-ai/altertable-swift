//
//  Storage.swift
//  Altertable
//

import Foundation

protocol Storage {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeObject(forKey key: String)
}

final class UserDefaultsStorage: Storage {
    private let defaults = UserDefaults.standard

    init() {}

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// Keeps product identities and consent isolated by API key now that environment is not a client namespace.
final class NamespacedStorage: Storage {
    private let storage: Storage
    private let prefix: String
    let shouldMigrateLegacy: Bool
    let legacyMigrationSucceeded: Bool

    private static let legacyOwnerKey = "atbl.v2.legacy_owner"
    private static let legacyDecisionKey = "atbl.v2.legacy_adoption_decision"
    private static let legacyAdoptionCompleteKey = "atbl.v2.legacy_adoption_complete"
    private static let legacyLock = NSLock()

    init(storage: Storage, apiKey: String, hasProductQueueDestination: Bool = false) {
        self.storage = storage
        let storagePrefix = "atbl.v2.\(apiKey)."
        prefix = storagePrefix
        let scopedKey: (String) -> String = { storagePrefix + $0 }
        let legacyValues = SDKConstants.StorageKeys.all.compactMap { storage.string(forKey: $0) }
        let legacyQueueURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("altertable_queue.json")
        let hasLegacyState = !legacyValues.isEmpty || FileManager.default.fileExists(atPath: legacyQueueURL.path)
        Self.legacyLock.lock()
        defer { Self.legacyLock.unlock() }
        let owner = storage.string(forKey: Self.legacyOwnerKey)
        let decision = storage.string(forKey: Self.legacyDecisionKey)
        // A prior launch may have written the owner but failed before it wrote the decision.
        // Only that owner may finish the durable decision; another key must never adopt it.
        if decision == nil, (owner == nil || owner == apiKey), hasLegacyState {
            // Claim and durably record the choice before copying any legacy value. This makes
            // retries deterministic even if a process is interrupted half way through a copy.
            if owner == nil {
                storage.set(apiKey, forKey: Self.legacyOwnerKey)
                guard storage.string(forKey: Self.legacyOwnerKey) == apiKey else {
                    shouldMigrateLegacy = false
                    legacyMigrationSucceeded = false
                    return
                }
            }
            let hasDestination = hasProductQueueDestination || SDKConstants.StorageKeys.all.contains {
                storage.string(forKey: scopedKey($0)) != nil
            }
            let recordedDecision = hasDestination ? "destination" : "adopt"
            storage.set(recordedDecision, forKey: Self.legacyDecisionKey)
            guard storage.string(forKey: Self.legacyDecisionKey) == recordedDecision else {
                shouldMigrateLegacy = false
                legacyMigrationSucceeded = false
                return
            }
        }
        let recordedOwner = storage.string(forKey: Self.legacyOwnerKey)
        let recordedDecision = storage.string(forKey: Self.legacyDecisionKey)
        let ownsLegacyState = recordedOwner == apiKey
        shouldMigrateLegacy = recordedDecision == "adopt" && ownsLegacyState && storage.string(forKey: Self.legacyAdoptionCompleteKey) != "complete"

        guard shouldMigrateLegacy else {
            legacyMigrationSucceeded = true
            return
        }
        var copiedSuccessfully = true
        for key in SDKConstants.StorageKeys.all {
            if let value = storage.string(forKey: key) {
                storage.set(value, forKey: scopedKey(key))
                copiedSuccessfully = copiedSuccessfully && storage.string(forKey: scopedKey(key)) == value
            }
        }
        legacyMigrationSucceeded = copiedSuccessfully
    }

    func string(forKey key: String) -> String? { storage.string(forKey: scoped(key)) }
    func set(_ value: String, forKey key: String) { storage.set(value, forKey: scoped(key)) }
    func removeObject(forKey key: String) { storage.removeObject(forKey: scoped(key)) }

    /// Marks the identity and queue copy complete only after both succeeded. A readback failure
    /// deliberately leaves the adoption incomplete so the same owner retries on the next launch.
    func completeLegacyAdoption(queueMigrationSucceeded: Bool) -> Bool {
        guard shouldMigrateLegacy, legacyMigrationSucceeded, queueMigrationSucceeded else {
            return legacyMigrationSucceeded && !shouldMigrateLegacy
        }
        storage.set("complete", forKey: Self.legacyAdoptionCompleteKey)
        return storage.string(forKey: Self.legacyAdoptionCompleteKey) == "complete"
    }

    private func scoped(_ key: String) -> String { prefix + key }
}

/// Per-client state that never touches persistent storage.
final class MemoryStorage: Storage {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) {
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }
}
