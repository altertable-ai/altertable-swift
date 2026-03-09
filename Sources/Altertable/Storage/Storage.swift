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
