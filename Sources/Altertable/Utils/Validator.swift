//
//  Validator.swift
//  Altertable
//

import Foundation

public enum ValidationError: LocalizedError, Equatable {
    case emptyUserId
    case reservedUserId(String)
    case userIdTooLong

    public var errorDescription: String? {
        switch self {
        case .emptyUserId:
            return "User ID cannot be empty or contain only whitespace."
        case let .reservedUserId(id):
            return "User ID \"\(id)\" is a reserved identifier and cannot be used."
        case .userIdTooLong:
            return "User ID is too long (max 1024 characters)."
        }
    }
}

class Validator {
    /// Case-insensitive reserved IDs
    static let reservedIds = [
        "anonymous_id", "anonymous", "distinct_id", "distinctid", "false", "guest",
        "id", "not_authenticated", "true", "undefined", "user_id", "user",
        "visitor_id", "visitor",
    ]

    /// Case-sensitive reserved IDs
    static let reservedIdsExact = [
        "[object Object]", "0", "NaN", "none", "None", "null",
    ]

    static func validateUserId(_ userId: String) throws {
        if userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyUserId
        }

        if reservedIdsExact.contains(userId) {
            throw ValidationError.reservedUserId(userId)
        }

        if reservedIds.contains(userId.lowercased()) {
            throw ValidationError.reservedUserId(userId)
        }

        if userId.count > 1024 {
            throw ValidationError.userIdTooLong
        }
    }
}
