//
//  QueueStorage.swift
//  Altertable
//

import Foundation

final class QueueStorage {
    private let fileURL: URL?
    private let logger: Logger
    let legacyMigrationSucceeded: Bool

    static func persistentQueueExists(apiKey: String) -> Bool {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: queueURL(apiKey: apiKey, directory: directory).path)
    }

    init(
        apiKey: String? = nil,
        logger: Logger,
        persistent: Bool = true,
        migrateLegacy: Bool = false,
        directory: URL? = nil,
        legacyMigrationWriter: ((Data, URL) throws -> Void)? = nil,
        overwriteLegacyMigrationDestination: Bool = false
    ) {
        self.logger = logger
        guard persistent else {
            fileURL = nil
            legacyMigrationSucceeded = true
            return
        }
        let directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        // Ensure directory exists (important for Linux/CI where caches dir may not exist)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        let resolvedURL = Self.queueURL(apiKey: apiKey, directory: directory)
        var migrated = true
        if migrateLegacy, overwriteLegacyMigrationDestination || !FileManager.default.fileExists(atPath: resolvedURL.path) {
            let legacyURL = directory.appendingPathComponent("altertable_queue.json")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                do {
                    let legacyData = try Data(contentsOf: legacyURL)
                    if let legacyMigrationWriter {
                        try legacyMigrationWriter(legacyData, resolvedURL)
                    } else {
                        try legacyData.write(to: resolvedURL, options: .atomic)
                    }
                    migrated = try Data(contentsOf: resolvedURL) == legacyData
                } catch {
                    logger.error("Failed to migrate legacy queue", error: error)
                    migrated = false
                }
            }
        }
        fileURL = resolvedURL
        legacyMigrationSucceeded = migrated
    }

    func save(_ queue: [Altertable.QueuedRequest]) {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: fileURL)
        } catch {
            logger.error("Failed to save queue", error: error)
        }
    }

    func load() -> [Altertable.QueuedRequest] {
        guard let fileURL else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Altertable.QueuedRequest].self, from: data)
        } catch {
            return []
        }
    }

    private static func queueURL(apiKey: String?, directory: URL) -> URL {
        guard let apiKey else { return directory.appendingPathComponent("altertable_queue.json") }
        let encodedKey = Data(apiKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent("altertable_queue.\(encodedKey).json")
    }
}
