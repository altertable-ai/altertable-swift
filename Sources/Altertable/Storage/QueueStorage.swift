//
//  QueueStorage.swift
//  Altertable
//

import Foundation

class QueueStorage {
    private let fileURL: URL
    
    init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let directory = paths[0]
        
        // Ensure directory exists (important for Linux/CI where Documents may not exist)
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
            print("[Altertable] Failed to save queue: \(error)")
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
