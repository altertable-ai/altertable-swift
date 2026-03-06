//
//  Models.swift
//  Altertable
//

import Foundation

public struct TrackPayload: Codable {
    public let timestamp: String
    public let event: String
    public let environment: String
    public let deviceId: String
    public let distinctId: String
    public let anonymousId: String?
    public let sessionId: String
    public let properties: [String: AnyCodable]
}

public struct IdentifyPayload: Codable {
    public let environment: String
    public let deviceId: String
    public let distinctId: String
    public let anonymousId: String?
    public let traits: [String: AnyCodable]
}

public struct AliasPayload: Codable {
    public let environment: String
    public let deviceId: String
    public let distinctId: String
    public let anonymousId: String?
    public let newUserId: String
}

/// AnyCodable helper to handle mixed types in JSON
public struct AnyCodable: Codable,
    ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral
{
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(integerLiteral value: Int) {
        self.init(value)
    }

    public init(booleanLiteral value: Bool) {
        self.init(value)
    }

    public init(floatLiteral value: Double) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool must be decoded before Int/Double — on some platforms true/false
        // can successfully decode as Int (1/0), losing the Bool type.
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map(\.value)
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable value cannot be encoded"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}
