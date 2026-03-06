//
//  Storage.swift
//  Altertable
//

import Foundation
#if canImport(Security)
import Security
#endif

public protocol Storage {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeObject(forKey key: String)
}

public class SecureStorage: Storage {
    public init() {}
    
    public func string(forKey key: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
        #else
        // Fallback for Linux or platforms without Security framework (e.g. server-side Swift or Linux tests)
        // In a real app this would be Keychain, but for Linux compatibility we might need a file-based secret store
        // or just no-op/fail if secure storage is strictly required.
        // For this SDK, since Mobile Tier implies iOS/Android (via Kotlin), Linux is mostly for testing/server.
        // Let's degrade to in-memory or nil for now to pass compilation on Linux.
        return nil
        #endif
    }
    
    public func set(_ value: String, forKey key: String) {
        #if canImport(Security)
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
        #endif
    }
    
    public func removeObject(forKey key: String) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
        #endif
    }
}

public class UserDefaultsStorage: Storage {
    private let defaults = UserDefaults.standard
    
    public init() {}
    
    public func string(forKey key: String) -> String? {
        return defaults.string(forKey: key)
    }
    
    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
    
    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

public class FallbackStorage: Storage {
    private let primary: Storage
    private let fallback: Storage
    
    public init(primary: Storage, fallback: Storage) {
        self.primary = primary
        self.fallback = fallback
    }
    
    public func string(forKey key: String) -> String? {
        return primary.string(forKey: key) ?? fallback.string(forKey: key)
    }
    
    public func set(_ value: String, forKey key: String) {
        // Try setting on primary, fall back if needed (though set usually succeeds even if keychain fails silently in simulator sometimes)
        // For simplicity, we write to both to ensure migration/availability
        primary.set(value, forKey: key)
        fallback.set(value, forKey: key)
    }
    
    public func removeObject(forKey key: String) {
        primary.removeObject(forKey: key)
        fallback.removeObject(forKey: key)
    }
}
