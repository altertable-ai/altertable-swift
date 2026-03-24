//
//  BatchingTests.swift
//  AltertableTests
//

import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import Altertable

final class BatchingTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)

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
        MockURLProtocol.requestHandler = nil
        session = nil

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)

        super.tearDown()
    }

    // MARK: - Threshold-Triggered Flush (flushAt)

    func testThresholdFlushTriggersAtCount() {
        let config = AltertableConfig(trackingConsent: .granted, flushAt: 3)
        let client = Altertable(apiKey: "pk_test_flush", config: config, session: session)

        var batchRequestCount = 0
        var totalEvents = 0
        let exp = expectation(description: "Batch flush at threshold")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
                {
                    batchRequestCount += 1
                    totalEvents += payloads.count
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: URL(string: "http://test")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.track(event: "event_0")
        client.track(event: "event_1")
        client.track(event: "event_2")

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(batchRequestCount, 1, "One batch request should be sent when threshold reached")
        XCTAssertEqual(totalEvents, 3, "Batch should contain all 3 events")
    }

    func testThresholdFlushWithMixedEventTypes() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 3)
        let client = Altertable(apiKey: "pk_test_mixed", config: config, session: session)

        var trackBatchCount = 0
        var identifyBatchCount = 0
        let trackExp = expectation(description: "Track batch")
        trackExp.expectedFulfillmentCount = 1
        let identifyExp = expectation(description: "Identify batch")
        identifyExp.expectedFulfillmentCount = 1

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                trackBatchCount += 1
                trackExp.fulfill()
            } else if request.url?.path.contains("identify") == true {
                identifyBatchCount += 1
                identifyExp.fulfill()
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.track(event: "track_0")
        client.identify(userId: "user_0")
        client.track(event: "track_1")

        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [trackExp, identifyExp], timeout: 2.0)
        XCTAssertEqual(trackBatchCount, 1, "One track batch should be sent")
        XCTAssertEqual(identifyBatchCount, 1, "One identify batch should be sent")
    }

    // MARK: - maxBatchSize Chunking

    func testMaxBatchSizeChunksEvents() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100, maxBatchSize: 3)
        let client = Altertable(apiKey: "pk_test_chunk", config: config, session: session)

        var batchRequests = 0
        var batchSizes: [Int] = []
        let exp = expectation(description: "Batches sent")
        exp.expectedFulfillmentCount = 4

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
                {
                    batchRequests += 1
                    batchSizes.append(payloads.count)
                    XCTAssertLessThanOrEqual(payloads.count, 3, "Batch size should not exceed maxBatchSize")
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        for i in 0 ..< 10 {
            client.track(event: "event_\(i)")
        }
        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(batchRequests, 4, "10 events with maxBatchSize=3 should create 4 batches (3+3+3+1)")
        XCTAssertEqual(batchSizes.sorted(), [1, 3, 3, 3], "Batch sizes should sum to 10 with max 3 each")
    }

    func testMaxBatchSizeLargerThanFlushAt() {
        let config = AltertableConfig(trackingConsent: .granted, flushAt: 5, maxBatchSize: 100)
        let client = Altertable(apiKey: "pk_test_large", config: config, session: session)

        var batchRequests = 0
        var totalEvents = 0
        let exp = expectation(description: "Single batch")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
                {
                    batchRequests += 1
                    totalEvents += payloads.count
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        for i in 0 ..< 5 {
            client.track(event: "event_\(i)")
        }

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(batchRequests, 1, "Should send single batch")
        XCTAssertEqual(totalEvents, 5, "Should contain all 5 events")
    }

    // MARK: - Event Type Separation and Ordering

    func testEventsSeparatedByTypeInBatches() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)

        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100, maxBatchSize: 100)
        let client = Altertable(apiKey: "pk_test_separate_\(UUID().uuidString)", config: config, session: session)

        var trackExpCount = 0
        var identifyExpCount = 0
        let trackExp = expectation(description: "Track batch")
        let identifyExp = expectation(description: "Identify batch")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                trackExpCount += 1
                trackExp.fulfill()
            } else if request.url?.path.contains("identify") == true {
                identifyExpCount += 1
                identifyExp.fulfill()
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.track(event: "first_track")
        client.identify(userId: "user_first")
        client.track(event: "second_track")
        client.identify(userId: "user_second")
        client.track(event: "third_track")

        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [trackExp, identifyExp], timeout: 2.0)

        XCTAssertEqual(trackExpCount, 1, "Should have one track batch")
        XCTAssertEqual(identifyExpCount, 1, "Should have one identify batch")
    }

    func testOrderPreservedWithinEventType() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100, maxBatchSize: 100)
        let client = Altertable(apiKey: "pk_test_order", config: config, session: session)

        var receivedEvents: [String] = []

        let exp = expectation(description: "Batch received")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
                {
                    receivedEvents = payloads.compactMap { $0["event"] as? String }
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        let eventOrder = ["A", "B", "C", "D", "E"]
        for event in eventOrder {
            client.track(event: event)
        }
        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(receivedEvents, eventOrder, "Event order should be preserved")
    }

    // MARK: - Timestamp Invariance

    func testTimestampsSetAtCaptureNotFlush() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let config = AltertableConfig(trackingConsent: .pending, flushAt: 3)
        let client = Altertable(apiKey: "pk_test_timestamp", config: config, session: session)

        let preCaptureTime = Date().iso8601String()
        client.track(event: "timestamp_test")
        let postCaptureTime = Date().iso8601String()

        Thread.sleep(forTimeInterval: 0.1)

        var capturedTimestamp: String?
        let queueStorage = QueueStorage(logger: Logger(isDebug: false))
        let queue = queueStorage.load()
        if case let .track(payload) = queue.first {
            capturedTimestamp = payload.timestamp
        }

        XCTAssertNotNil(capturedTimestamp, "Timestamp should be captured")
        if let ts = capturedTimestamp {
            XCTAssertGreaterThanOrEqual(ts, preCaptureTime, "Timestamp should not be before capture")
            XCTAssertLessThanOrEqual(ts, postCaptureTime, "Timestamp should not be after capture")
        }

        var flushedTimestamp: String?
        let exp = expectation(description: "Flush received")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]],
                   let first = payloads.first
                {
                    flushedTimestamp = first["timestamp"] as? String
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.configure { $0.trackingConsent = .granted }

        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(capturedTimestamp, flushedTimestamp, "Timestamp should be same at capture and flush")
    }

    func testIdentifyTimestampsPreserved() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100)
        let client = Altertable(apiKey: "pk_test_identify_ts", config: config, session: session)

        var flushedTimestamp: String?
        var identifyReceived = false
        let exp = expectation(description: "Identify batch received")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("identify") == true {
                identifyReceived = true
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]],
                   let first = payloads.first
                {
                    flushedTimestamp = first["timestamp"] as? String
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.identify(userId: "user_ts_test")
        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(identifyReceived, "Identify request should be received")
        XCTAssertNotNil(flushedTimestamp, "Identify should have timestamp")
        XCTAssertFalse(flushedTimestamp?.isEmpty ?? true, "Timestamp should not be empty")
    }

    func testAliasTimestampsPreserved() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100)
        let client = Altertable(apiKey: "pk_test_alias_ts", config: config, session: session)

        var flushedTimestamp: String?
        var aliasReceived = false
        let exp = expectation(description: "Alias batch received")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("alias") == true {
                aliasReceived = true
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]],
                   let first = payloads.first
                {
                    flushedTimestamp = first["timestamp"] as? String
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.alias(newUserId: "user_alias_ts")
        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(aliasReceived, "Alias request should be received")
        XCTAssertNotNil(flushedTimestamp, "Alias should have timestamp")
        XCTAssertFalse(flushedTimestamp?.isEmpty ?? true, "Timestamp should not be empty")
    }

    // MARK: - Retry and Persistence on Failure

    func testFailedBatchRetryAndPersistence() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100)
        let client = Altertable(apiKey: "pk_test_retry_persist", config: config, session: session)
        client.setRetryBaseDelay(0.05)

        var callCount = 0
        let successExp = expectation(description: "Event eventually succeeds")

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return (HTTPURLResponse(url: URL(string: "http://test")!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
            }
            successExp.fulfill()
            return (HTTPURLResponse(url: URL(string: "http://test")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.track(event: "retry_persist_event")
        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [successExp], timeout: 5.0)
        XCTAssertGreaterThanOrEqual(callCount, 2, "Should retry after initial failure")
    }

    func testPartialBatchFailureRetries() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100, maxBatchSize: 100)
        let client = Altertable(apiKey: "pk_test_partial", config: config, session: session)
        client.setRetryBaseDelay(0.05)

        var callCount = 0
        let successExp = expectation(description: "Batches eventually succeed")

        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if request.url?.path.contains("track") == true && callCount == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
            }
            successExp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        for i in 0 ..< 3 {
            client.track(event: "partial_event_\(i)")
        }
        Thread.sleep(forTimeInterval: 0.1)
        client.configure { $0.trackingConsent = .granted }

        wait(for: [successExp], timeout: 5.0)
        XCTAssertGreaterThanOrEqual(callCount, 2, "Should retry on failure")
    }

    // MARK: - Empty Batch Handling

    func testEmptyBatchNotSent() {
        let config = AltertableConfig(trackingConsent: .granted, flushAt: 100)
        let client = Altertable(apiKey: "pk_test_empty", config: config, session: session)

        var requestCount = 0
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (HTTPURLResponse(url: URL(string: "http://test")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.flush()

        XCTAssertEqual(requestCount, 0, "Empty flush should not send any requests")
    }

    // MARK: - Manual Flush

    func testManualFlushSendsQueuedEvents() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100)
        let client = Altertable(apiKey: "pk_test_manual", config: config, session: session)

        var eventReceived = false
        let exp = expectation(description: "Manual flush sends events")

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("track") == true {
                if let body = request.httpBody,
                   let payloads = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]],
                   let event = payloads.first?["event"] as? String,
                   event == "manual_flush_test"
                {
                    eventReceived = true
                }
            }
            exp.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        client.track(event: "manual_flush_test")
        Thread.sleep(forTimeInterval: 0.1)

        client.configure { $0.trackingConsent = .granted }
        client.flush()

        wait(for: [exp], timeout: 2.0)
        XCTAssertTrue(eventReceived, "Manual flush should send queued events")
    }

    // MARK: - Queue Overflow with Batching

    func testQueueOverflowDropsOldestEventsWithBatching() {
        let config = AltertableConfig(trackingConsent: .pending, flushAt: 100, maxBatchSize: 100)
        let client = Altertable(apiKey: "pk_test_overflow_batch", config: config, session: session)
        client.maxQueueSize = 5

        let totalEvents = 10
        for i in 0 ..< totalEvents {
            client.track(event: "overflow_event_\(i)")
        }

        Thread.sleep(forTimeInterval: 0.1)

        let queueStorage = QueueStorage(logger: Logger(isDebug: false))
        let queue = queueStorage.load()
        let trackEvents = queue.compactMap { request -> String? in
            if case let .track(payload) = request { return payload.event }
            return nil
        }

        XCTAssertEqual(trackEvents.count, 5, "Queue should be capped at maxQueueSize")
        XCTAssertEqual(trackEvents.first, "overflow_event_5", "Oldest events should be dropped")
        XCTAssertEqual(trackEvents.last, "overflow_event_9", "Newest events should be kept")
    }
}
