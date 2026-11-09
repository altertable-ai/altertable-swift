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

/// Isolates product identity and consent by API key.
final class ScopedStorage: Storage {
    private let storage: Storage
    private let prefix: String

    init(storage: Storage, apiKey: String) {
        self.storage = storage
        prefix = "atbl.v2.\(apiKey)."
    }

    func string(forKey key: String) -> String? {
        storage.string(forKey: prefix + key)
    }

    func set(_ value: String, forKey key: String) {
        storage.set(value, forKey: prefix + key)
    }

    func removeObject(forKey key: String) {
        storage.removeObject(forKey: prefix + key)
    }
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
