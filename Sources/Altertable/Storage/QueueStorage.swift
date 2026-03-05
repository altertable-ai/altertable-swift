//
//  QueueStorage.swift
//  Altertable
//

import Foundation

class QueueStorage {
    private let fileURL: URL
    
    init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        fileURL = paths[0].appendingPathComponent("altertable_queue.json")
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
