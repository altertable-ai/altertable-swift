//
//  QueueStorage.swift
//  Altertable
//

import Foundation

class QueueStorage {
    private let fileURL: URL
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let directory = paths[0]

        // Ensure directory exists (important for Linux/CI where caches dir may not exist)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        fileURL = directory.appendingPathComponent("altertable_queue.json")
    }

    func save(_ queue: [Altertable.QueuedRequest]) {
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: fileURL)
        } catch {
            logger.error("Failed to save queue", error: error)
        }
    }

    func load() -> [Altertable.QueuedRequest] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Altertable.QueuedRequest].self, from: data)
        } catch {
            return []
        }
    }
}
