//
//  TestHelpers.swift
//  AltertableTests
//

import Foundation
@testable import Altertable

enum TestSupport {
    /// Matches QueueStorage’s default file path so tests do not replay stale events between runs.
    static func removeDefaultPersistedEventQueue() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let directory = paths.first else { return }
        let fileURL = directory.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension AltertableConfig {
    /// Single-event flushes and no periodic timer noise for unit tests.
    mutating func applyUnitTestImmediateFlush() {
        flushEventThreshold = 1
        flushIntervalMs = 0
    }

    static var unitTest: AltertableConfig {
        var configuration = AltertableConfig()
        configuration.applyUnitTestImmediateFlush()
        return configuration
    }

    /// Unit-test batching defaults with selected production options overridden.
    static func makeUnitTest(
        captureScreenViews: Bool? = nil,
        trackingConsent: TrackingConsentState? = nil,
        environment: String? = nil
    ) -> AltertableConfig {
        var configuration = AltertableConfig()
        if let captureScreenViews { configuration.captureScreenViews = captureScreenViews }
        if let trackingConsent { configuration.trackingConsent = trackingConsent }
        if let environment { configuration.environment = environment }
        configuration.applyUnitTestImmediateFlush()
        return configuration
    }
}

enum TestJSONError: Error {
    case emptyBatch
    case unexpectedRoot
}

enum TestJSON {
    /// Decodes the first object from a batched JSON array body (or a single object for backwards compatibility).
    static func firstObject(from body: Data) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: body, options: [])
        if let array = parsed as? [[String: Any]] {
            guard let first = array.first else { throw TestJSONError.emptyBatch }
            return first
        }
        if let dictionary = parsed as? [String: Any] {
            return dictionary
        }
        throw TestJSONError.unexpectedRoot
    }

    /// Decodes a JSON array body (batched track/identify/alias requests).
    static func objectArray(from body: Data) throws -> [[String: Any]] {
        let parsed = try JSONSerialization.jsonObject(with: body, options: [])
        guard let array = parsed as? [[String: Any]] else {
            throw TestJSONError.unexpectedRoot
        }
        return array
    }
}
