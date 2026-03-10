//
//  QueueTests.swift
//  AltertableTests
//

import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import Altertable

final class QueueTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()

        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        #if canImport(FoundationNetworking)
            let sessionConfig = URLSessionConfiguration.default
        #else
            let sessionConfig = URLSessionConfiguration.ephemeral
        #endif
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: sessionConfig)

        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        session = nil
        super.tearDown()
    }

    func testQueuePersistence() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let config1 = AltertableConfig(trackingConsent: .pending)

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        let client1 = Altertable(apiKey: "pk_test_1", config: config1, session: session)
        client1.track(event: "persisted_event")

        // track() dispatches async; give the serial queue a moment to write to disk.
        Thread.sleep(forTimeInterval: 0.1)

        let config2 = AltertableConfig(trackingConsent: .pending)
        let client2 = Altertable(apiKey: "pk_test_1", config: config2, session: session)

        let expectation = expectation(description: "Flush loaded event")
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               (json["event"] as? String) == "persisted_event"
            {
                expectation.fulfill()
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client2.configure { $0.trackingConsent = .granted }

        waitForExpectations(timeout: 1.0)
    }

    func testQueueDropsOldestWhenFull() {
        // Use a small maxQueueSize so we can verify the drop behavior without
        // enqueuing thousands of events.
        let maxSize = 3
        let config = AltertableConfig(trackingConsent: .pending)
        let client = Altertable(apiKey: "pk_test_drop", config: config, session: session)
        client.maxQueueSize = maxSize

        // Enqueue maxSize + 2 events; the two oldest should be dropped.
        let totalEnqueued = maxSize + 2
        for index in 0 ..< totalEnqueued {
            client.track(event: "event_\(index)")
        }
        Thread.sleep(forTimeInterval: 0.1)

        var flushedEvents: [String] = []
        let exp = expectation(description: "Flushed events after overflow")
        exp.expectedFulfillmentCount = maxSize

        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let event = json["event"] as? String
            {
                flushedEvents.append(event)
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.configure { $0.trackingConsent = .granted }
        waitForExpectations(timeout: 2.0)

        XCTAssertEqual(flushedEvents.count, maxSize, "Queue should be capped at maxQueueSize")
        // The two oldest events (event_0, event_1) should have been dropped.
        XCTAssertFalse(flushedEvents.contains("event_0"), "Oldest event should have been dropped")
        XCTAssertFalse(flushedEvents.contains("event_1"), "Second oldest event should have been dropped")
        XCTAssertTrue(flushedEvents.contains("event_\(totalEnqueued - 1)"), "Newest event should be present")
    }

    func testFailedRequestIsRequeued() {
        let config = AltertableConfig(trackingConsent: .granted)
        let client = Altertable(apiKey: "pk_test_retry", config: config, session: session)
        // Use a very short retry delay so the test doesn't take seconds.
        client.setRetryBaseDelay(0.05)

        var callCount = 0
        let successExp = expectation(description: "Request eventually succeeds")

        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
            }
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               json["event"] as? String == "retry_event"
            {
                successExp.fulfill()
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.track(event: "retry_event")
        wait(for: [successExp], timeout: 2.0)
        XCTAssertGreaterThan(callCount, 1, "Request should have been retried")
    }
}
