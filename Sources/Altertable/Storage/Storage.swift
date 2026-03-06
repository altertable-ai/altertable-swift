//
//  Storage.swift
//  Altertable
//

import Foundation

public protocol Storage {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeObject(forKey key: String)
}

public class UserDefaultsStorage: Storage {
    private let defaults = UserDefaults.standard

    public init() {}

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
