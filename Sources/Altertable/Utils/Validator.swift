//
//  Validator.swift
//  Altertable
//

import Foundation

class Validator {
    // Case-insensitive reserved IDs
    static let reservedIds = [
        "anonymous_id", "anonymous", "distinct_id", "distinctid", "false", "guest",
        "id", "not_authenticated", "true", "undefined", "user_id", "user",
        "visitor_id", "visitor"
    ]
    
    // Case-sensitive reserved IDs
    static let reservedIdsExact = [
        "[object Object]", "0", "NaN", "none", "None", "null"
    ]
    
    static func validateUserId(_ userId: String) throws {
        if userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(domain: "Altertable", code: 1001, userInfo: [NSLocalizedDescriptionKey: "User ID cannot be empty or contain only whitespace."])
        }
        
        if reservedIdsExact.contains(userId) {
            throw NSError(domain: "Altertable", code: 1002, userInfo: [NSLocalizedDescriptionKey: "User ID \"\(userId)\" is a reserved identifier and cannot be used."])
        }
        
        if reservedIds.contains(userId.lowercased()) {
            throw NSError(domain: "Altertable", code: 1002, userInfo: [NSLocalizedDescriptionKey: "User ID \"\(userId)\" is a reserved identifier and cannot be used."])
        }
        
        // Spec says "MAX_USER_ID_LENGTH = 1024" in JS constants (not in SDK constants md but good practice)
        if userId.count > 1024 {
             throw NSError(domain: "Altertable", code: 1003, userInfo: [NSLocalizedDescriptionKey: "User ID is too long (max 1024 characters)."])
        }
    }
}
