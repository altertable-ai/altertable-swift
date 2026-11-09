//
//  LegacyStorageMigration.swift
//  Altertable
//

import Foundation

/// Adopts the identity, consent, and queue that earlier SDK versions stored without an API key.
///
/// That state has no owner, so the first product key to start claims it with a durable marker and no other
/// key ever imports it. Existing API-key-scoped state wins over the legacy state as a whole. The legacy
/// state is left in place; the marker keeps a drained queue from being imported again.
enum LegacyStorageMigration {
    private static let ownerKey = "atbl.v2.legacy_owner"
    private static let pendingPrefix = "pending:"
    private static let completePrefix = "complete:"
    private static let lock = NSLock()

    /// Returns `false` when the claimed copy failed. The caller must then leave the destination untouched
    /// so the same key retries on the next launch.
    static func run(apiKey: String, legacy: Storage, destination: Storage, destinationQueueURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let legacyQueueURL = QueueStorage.legacyFileURL
        let keys = SDKConstants.StorageKeys.all

        if legacy.string(forKey: ownerKey) == nil {
            let hasLegacyState = fileManager.fileExists(atPath: legacyQueueURL.path)
                || keys.contains { legacy.string(forKey: $0) != nil }
            guard hasLegacyState else { return true }
            let hasDestinationState = fileManager.fileExists(atPath: destinationQueueURL.path)
                || keys.contains { destination.string(forKey: $0) != nil }
            legacy.set((hasDestinationState ? completePrefix : pendingPrefix) + apiKey, forKey: ownerKey)
        }
        guard legacy.string(forKey: ownerKey) == pendingPrefix + apiKey else { return true }

        do {
            if fileManager.fileExists(atPath: legacyQueueURL.path) {
                try Data(contentsOf: legacyQueueURL).write(to: destinationQueueURL, options: .atomic)
            }
        } catch {
            return false
        }
        for key in keys {
            if let value = legacy.string(forKey: key) {
                destination.set(value, forKey: key)
            }
        }
        legacy.set(completePrefix + apiKey, forKey: ownerKey)
        return true
    }
}
