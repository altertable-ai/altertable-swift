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
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case event
        case environment
        case deviceId = "device_id"
        case distinctId = "distinct_id"
        case anonymousId = "anonymous_id"
        case sessionId = "session_id"
        case properties
    }
}

public struct IdentifyPayload: Codable {
    public let environment: String
    public let deviceId: String
    public let distinctId: String
    public let anonymousId: String?
    public let traits: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case environment
        case deviceId = "device_id"
        case distinctId = "distinct_id"
        case anonymousId = "anonymous_id"
        case traits
    }
}

public struct AliasPayload: Codable {
    public let environment: String
    public let deviceId: String
    public let distinctId: String
    public let anonymousId: String?
    public let newUserId: String
    
    enum CodingKeys: String, CodingKey {
        case environment
        case deviceId = "device_id"
        case distinctId = "distinct_id"
        case anonymousId = "anonymous_id"
        case newUserId = "new_user_id"
    }
}

// AnyCodable helper to handle mixed types in JSON
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            value = x
        } else if let x = try? container.decode(Int.self) {
            value = x
        } else if let x = try? container.decode(Double.self) {
            value = x
        } else if let x = try? container.decode(Bool.self) {
            value = x
        } else if let x = try? container.decode([String: AnyCodable].self) {
            value = x.mapValues { $0.value }
        } else if let x = try? container.decode([AnyCodable].self) {
            value = x.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let x as String:
            try container.encode(x)
        case let x as Int:
            try container.encode(x)
        case let x as Double:
            try container.encode(x)
        case let x as Bool:
            try container.encode(x)
        case let x as [String: Any]:
             try container.encode(x.mapValues { AnyCodable($0) })
        case let x as [Any]:
             try container.encode(x.map { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
