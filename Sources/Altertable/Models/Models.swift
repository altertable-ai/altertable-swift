//
//  Models.swift
//  Altertable
//

import Foundation

protocol APIPayload: Encodable {
    static var endpoint: String { get }
}

struct TrackPayload: Codable, Sendable {
    let timestamp: String
    let event: String
    let environment: String
    let deviceId: String
    let distinctId: String
    let anonymousId: String?
    let sessionId: String
    let properties: [String: JSONValue]
}

struct IdentifyPayload: Codable, Sendable {
    let environment: String
    let deviceId: String
    let distinctId: String
    let anonymousId: String?
    let traits: [String: JSONValue]
}

struct AliasPayload: Codable, Sendable {
    let environment: String
    let deviceId: String
    let distinctId: String
    let anonymousId: String?
    let newUserId: String
}

extension TrackPayload: APIPayload {
    static let endpoint = "track"
}

extension IdentifyPayload: APIPayload {
    static let endpoint = "identify"
}

extension AliasPayload: APIPayload {
    static let endpoint = "alias"
}

/// Type-safe JSON value representation
public enum JSONValue: Codable, Equatable, Sendable,
    ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral,
    ExpressibleByDictionaryLiteral,
    ExpressibleByArrayLiteral
{
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    // MARK: - ExpressibleByLiteral Conformances

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }

    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }

    // MARK: - Typed Initializers

    /// Creates a JSONValue from a String
    public init(_ value: String) {
        self = .string(value)
    }

    /// Creates a JSONValue from an Int
    public init(_ value: Int) {
        self = .int(value)
    }

    /// Creates a JSONValue from a Double
    public init(_ value: Double) {
        self = .double(value)
    }

    /// Creates a JSONValue from a Bool
    public init(_ value: Bool) {
        self = .bool(value)
    }

    /// Creates a JSONValue from a dictionary
    public init(_ value: [String: JSONValue]) {
        self = .object(value)
    }

    /// Creates a JSONValue from an array
    public init(_ value: [JSONValue]) {
        self = .array(value)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool must be decoded before Int/Double — on some platforms true/false
        // can successfully decode as Int (1/0), losing the Bool type.
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let dictValue = try? container.decode([String: JSONValue].self) {
            self = .object(dictValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSONValue cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
