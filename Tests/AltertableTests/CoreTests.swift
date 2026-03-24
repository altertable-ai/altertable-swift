//
//  CoreTests.swift
//  AltertableTests
//

import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import Altertable

final class CoreTests: XCTestCase {
    var client: Altertable!
    var session: URLSession!

    override func setUp() {
        super.setUp()

        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        #if canImport(FoundationNetworking)
            let config = URLSessionConfiguration.default
        #else
            let config = URLSessionConfiguration.ephemeral
        #endif
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequest = nil
    }

    private func makeClient(apiKey: String = "pk_test_123", trackingConsent: TrackingConsentState = .granted) -> Altertable {
        let config = AltertableConfig(
            trackingConsent: trackingConsent,
            flushAt: 1,
            flushInterval: 3600
        )
        return Altertable(apiKey: apiKey, config: config, session: session)
    }

    override func tearDown() {
        client = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func successResponse(url: URL) -> (HTTPURLResponse, Data?) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, nil)
    }

    private func extractFirstPayload(from body: Data?) -> [String: Any]? {
        guard let body = body,
              let json = try? JSONSerialization.jsonObject(with: body)
        else { return nil }
        if let single = json as? [String: Any] {
            return single
        }
        if let array = json as? [[String: Any]], let first = array.first {
            return first
        }
        return nil
    }

    // MARK: - Initialization

    func testInitialization() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        XCTAssertNotNil(client)
    }

    // MARK: - track()

    func testTrackRequest() {
        client = makeClient()

        let expectation = expectation(description: "Request Sent")

        MockURLProtocol.requestHandler = { [self] request in
            guard let url = request.url else { throw URLError(.badURL) }

            XCTAssertEqual(url.host, "api.altertable.ai")
            XCTAssertEqual(url.path, "/track")
            XCTAssertEqual(request.httpMethod, "POST")

            // API key must be in header, not query string
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "pk_test_123")
            XCTAssertNil(url.query, "API key must not appear as a query parameter")

            if let json = extractFirstPayload(from: request.httpBody) {
                XCTAssertEqual(json["event"] as? String, "test_event")
                XCTAssertEqual(json["environment"] as? String, "production")
                XCTAssertNotNil(json["session_id"])
                XCTAssertNotNil(json["device_id"])
                XCTAssertNotNil(json["distinct_id"])

                let properties = json["properties"] as? [String: Any]
                XCTAssertEqual(properties?["foo"] as? String, "bar")
            } else {
                XCTFail("Missing http body")
            }

            expectation.fulfill()
            return successResponse(url: url)
        }

        client.track(event: "test_event", properties: ["foo": JSONValue("bar")])

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - identify()

    func testIdentify() {
        client = makeClient()

        let expectation = expectation(description: "Identify Request")

        MockURLProtocol.requestHandler = { [self] request in
            guard let url = request.url else { throw URLError(.badURL) }

            XCTAssertEqual(url.path, "/identify")
            XCTAssertEqual(request.httpMethod, "POST")

            if let json = extractFirstPayload(from: request.httpBody) {
                XCTAssertEqual(json["distinct_id"] as? String, "user_123")
                XCTAssertNotNil(json["anonymous_id"], "Should have anonymous_id linked")

                let traits = json["traits"] as? [String: Any]
                XCTAssertEqual(traits?["email"] as? String, "user@example.com")
            }

            expectation.fulfill()
            return successResponse(url: url)
        }

        client.identify(userId: "user_123", traits: ["email": JSONValue("user@example.com")])
        waitForExpectations(timeout: 1.0)
    }

    // MARK: - alias()

    func testAlias() {
        client = makeClient()

        let expectation = expectation(description: "Alias Request")

        MockURLProtocol.requestHandler = { [self] request in
            guard let url = request.url else { throw URLError(.badURL) }

            XCTAssertEqual(url.path, "/alias")
            XCTAssertEqual(request.httpMethod, "POST")

            if let json = extractFirstPayload(from: request.httpBody) {
                XCTAssertEqual(json["new_user_id"] as? String, "new_user_456")
                XCTAssertNotNil(json["distinct_id"])
            }

            expectation.fulfill()
            return successResponse(url: url)
        }

        client.alias(newUserId: "new_user_456")
        waitForExpectations(timeout: 1.0)
    }

    // MARK: - reset()

    func testReset() {
        client = makeClient()

        // Drain the identify request before asserting reset state.
        let identifyExp = expectation(description: "Identify before reset")
        MockURLProtocol.requestHandler = { [self] request in
            identifyExp.fulfill()
            return successResponse(url: request.url!)
        }
        client.identify(userId: "user_123")
        wait(for: [identifyExp], timeout: 1.0)

        client.reset()

        // Allow the async reset to settle before asserting internal state.
        let postResetExp = expectation(description: "Track after reset")

        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                let distinctId = json["distinct_id"] as? String
                XCTAssertNotEqual(distinctId, "user_123")
                XCTAssertTrue(distinctId?.starts(with: "anonymous-") ?? false)

                if let anonymousId = json["anonymous_id"] {
                    XCTAssertTrue(anonymousId is NSNull, "anonymous_id should be null after reset")
                }
            }
            postResetExp.fulfill()
            return successResponse(url: request.url!)
        }

        client.track(event: "post_reset")
        wait(for: [postResetExp], timeout: 1.0)

        XCTAssertNotEqual(client.currentDistinctId(), "user_123")
        XCTAssertNil(client.currentAnonymousId())
    }

    func testResetDeviceId() {
        client = makeClient()

        var firstDeviceId: String?
        let exp1 = expectation(description: "First track")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                firstDeviceId = json["device_id"] as? String
            }
            exp1.fulfill()
            return successResponse(url: request.url!)
        }
        client.track(event: "before_reset")
        wait(for: [exp1], timeout: 1.0)
        XCTAssertNotNil(firstDeviceId)

        client.reset(resetDeviceId: true)

        let exp2 = expectation(description: "Track after device reset")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                let newDeviceId = json["device_id"] as? String
                XCTAssertNotEqual(newDeviceId, firstDeviceId, "Device ID should change after resetDeviceId:true")
                XCTAssertTrue(newDeviceId?.starts(with: "device-") ?? false)
            }
            exp2.fulfill()
            return successResponse(url: request.url!)
        }
        client.track(event: "after_device_reset")
        wait(for: [exp2], timeout: 1.0)
    }

    // MARK: - updateTraits()

    func testUpdateTraits() {
        client = makeClient()

        // Must identify first
        let identifyExp = expectation(description: "Identify")
        MockURLProtocol.requestHandler = { [self] request in
            identifyExp.fulfill()
            return successResponse(url: request.url!)
        }
        client.identify(userId: "user_traits")
        wait(for: [identifyExp], timeout: 1.0)

        let updateExp = expectation(description: "UpdateTraits sends identify")
        MockURLProtocol.requestHandler = { [self] request in
            guard let url = request.url else { throw URLError(.badURL) }
            XCTAssertEqual(url.path, "/identify")

            if let json = extractFirstPayload(from: request.httpBody) {
                let traits = json["traits"] as? [String: Any]
                XCTAssertEqual(traits?["plan"] as? String, "premium")
            }

            updateExp.fulfill()
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        client.updateTraits(["plan": JSONValue("premium")])
        wait(for: [updateExp], timeout: 1.0)
    }

    func testUpdateTraitsWithoutIdentifyIsDropped() {
        client = makeClient()

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Should not send request when not identified")
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        client.updateTraits(["plan": JSONValue("premium")])

        let noRequestExp = expectation(description: "No request sent")
        noRequestExp.isInverted = true
        wait(for: [noRequestExp], timeout: 0.2)
    }

    // MARK: - Session renewal

    func testSessionContinuity() {
        client = makeClient()

        var firstSessionId: String?

        let exp1 = expectation(description: "First Request")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                firstSessionId = json["session_id"] as? String
            }
            exp1.fulfill()
            return successResponse(url: request.url!)
        }
        client.track(event: "first")
        wait(for: [exp1], timeout: 1.0)
        XCTAssertNotNil(firstSessionId)

        let exp2 = expectation(description: "Second Request")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                XCTAssertEqual(
                    json["session_id"] as? String,
                    firstSessionId,
                    "Immediate second event should share session"
                )
            }
            exp2.fulfill()
            return successResponse(url: request.url!)
        }
        client.track(event: "second")
        wait(for: [exp2], timeout: 1.0)
    }

    // MARK: - Consent

    func testConsentPendingQueuesEvents() {
        client = makeClient(trackingConsent: TrackingConsentState.pending)
        client.track(event: "pending_event")
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Should not send while consent is pending")
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        let noSendExp = expectation(description: "No request while pending")
        noSendExp.isInverted = true
        wait(for: [noSendExp], timeout: 0.1)
        let flushExp = expectation(description: "Flush after consent granted")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                XCTAssertEqual(json["event"] as? String, "pending_event")
            }
            flushExp.fulfill()
            return successResponse(url: request.url!)
        }
        client.configure { $0.trackingConsent = .granted }
        wait(for: [flushExp], timeout: 1.0)
    }

    func testConsentDeniedClearsQueue() {
        client = makeClient(trackingConsent: TrackingConsentState.pending)
        client.track(event: "will_be_dropped")
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Should not send after consent denied")
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        client.configure { $0.trackingConsent = .denied }
        let noSendExp = expectation(description: "No request after denied")
        noSendExp.isInverted = true
        wait(for: [noSendExp], timeout: 0.2)
    }

    // MARK: - User switching

    func testIdentifySwitchingUser() {
        client = makeClient()
        let expIdentifyA = expectation(description: "Identify user_A")
        MockURLProtocol.requestHandler = { [self] request in
            expIdentifyA.fulfill()
            return successResponse(url: request.url!)
        }
        client.identify(userId: "user_A")
        wait(for: [expIdentifyA], timeout: 1.0)

        var originalSessionId: String?
        let exp1 = expectation(description: "Capture session")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                originalSessionId = json["session_id"] as? String
            }
            exp1.fulfill()
            return successResponse(url: request.url!)
        }
        client.track(event: "pre_switch")
        wait(for: [exp1], timeout: 1.0)
        // identify(user_B) auto-resets then sends identify + we track — 2 requests
        let exp2 = expectation(description: "Requests after switch")
        exp2.expectedFulfillmentCount = 2
        var trackRequestSeen = false
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                if json["event"] as? String == "post_switch" {
                    trackRequestSeen = true
                    XCTAssertNotEqual(
                        json["session_id"] as? String,
                        originalSessionId,
                        "Session should reset on user switch"
                    )
                    XCTAssertEqual(json["distinct_id"] as? String, "user_B")
                }
            }
            exp2.fulfill()
            return successResponse(url: request.url!)
        }
        client.identify(userId: "user_B")
        client.track(event: "post_switch")
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(trackRequestSeen, "Track request after switch should have been sent")
    }

    // MARK: - configure() fields

    func testConfigureEnvironment() {
        let config = AltertableConfig(environment: "staging", flushAt: 1, flushInterval: 3600)
        client = Altertable(apiKey: "pk_test_123", config: config, session: session)
        let exp = expectation(description: "Track in new environment")
        MockURLProtocol.requestHandler = { [self] request in
            if let json = extractFirstPayload(from: request.httpBody) {
                XCTAssertEqual(json["environment"] as? String, "development")
            }
            exp.fulfill()
            return successResponse(url: request.url!)
        }
        client.configure { $0.environment = "development" }
        client.track(event: "env_test")
        wait(for: [exp], timeout: 1.0)
    }

}
