//
//  Validator.swift
//  Altertable
//

import Foundation

enum ValidationError: LocalizedError, Equatable, Sendable {
    case emptyUserId
    case reservedUserId(String)
    case userIdTooLong

    var errorDescription: String? {
        switch self {
        case .emptyUserId:
            return "Enter a user ID"
        case let .reservedUserId(id):
            return "The user ID \"\(id)\" is reserved. Choose a different ID."
        case .userIdTooLong:
            return "User ID must be 1024 characters or less. Shorten your ID."
        }
    }
}

enum Validator {
    /// Case-insensitive reserved IDs
    static let reservedIds: Set<String> = [
        "anonymous_id", "anonymous", "distinct_id", "distinctid", "false", "guest",
        "id", "not_authenticated", "true", "undefined", "user_id", "user",
        "visitor_id", "visitor",
    ]

    /// Case-sensitive reserved IDs
    static let reservedIdsExact: Set<String> = [
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
