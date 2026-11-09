//
//  QueueStorage.swift
//  Altertable
//

import Foundation

final class QueueStorage {
    /// Queue file written by SDK versions that did not scope state by API key.
    static var legacyFileURL: URL {
        directory.appendingPathComponent("altertable_queue.json")
    }

    static func fileURL(apiKey: String) -> URL {
        let encodedKey = Data(apiKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent("altertable_queue.v2.\(encodedKey).json")
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private let fileURL: URL?
    private let logger: Logger

    /// - Parameter fileURL: Where to persist the queue, or `nil` to keep it in memory only.
    init(logger: Logger, fileURL: URL?) {
        self.logger = logger
        self.fileURL = fileURL

        // Ensure directory exists (important for Linux/CI where caches dir may not exist)
        if let directory = fileURL?.deletingLastPathComponent(),
           !FileManager.default.fileExists(atPath: directory.path)
        {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
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
}
