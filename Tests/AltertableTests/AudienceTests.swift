@testable import Altertable
import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class AudienceTests: XCTestCase {
    private var session: URLSession!
    private var clients: [Altertable] = []
    private var requests: [URLRequest] = []
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        TestSupport.removeDefaultPersistedEventQueue()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.requestHandler = { [self] request in
            lock.lock()
            requests.append(request)
            lock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
    }

    override func tearDown() {
        for client in clients {
            client.configure { $0.trackingConsent = .denied }
            _ = client.currentDistinctId() // Drain the serial queue before removing the handler.
        }
        clients.removeAll()
        session.invalidateAndCancel()
        MockURLProtocol.requestHandler = nil
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        TestSupport.removeDefaultPersistedEventQueue()
        super.tearDown()
    }

    private func start(
        mode: TrackingMode = .audience,
        consent: TrackingConsentState = .granted,
        maxBatchSize: Int = 20,
        onError: ((Error) -> Void)? = nil
    ) -> Altertable {
        let config = AltertableConfig(
            mode: mode,
            trackingConsent: consent,
            release: "test-release",
            onError: onError,
            captureScreenViews: false,
            flushEventThreshold: 100,
            flushIntervalMs: 86_400_000,
            maxBatchSize: maxBatchSize
        )
        let client = Altertable(apiKey: "key", config: config, session: session)
        clients.append(client)
        return client
    }

    private func flush(_ client: Altertable) {
        let finished = expectation(description: "Flush completed")
        client.flush { finished.fulfill() }
        wait(for: [finished], timeout: 5)
    }

    private func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    private func events() throws -> [[String: Any]] {
        try capturedRequests().flatMap { try TestJSON.objectArray(from: XCTUnwrap($0.httpBody)) }
    }

    private func assertAudience(_ payload: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(payload.keys), Set(["mode", "event", "timestamp", "properties"]), file: file, line: line)
        XCTAssertEqual(payload["mode"] as? String, "audience", file: file, line: line)
    }

    func testWireOmissionAndIdentityCallsAreIgnoredBeforeValidation() throws {
        let client = start(onError: { error in XCTFail("Identity calls must be ignored: \(error)") })
        let identity = client.currentDistinctId()
        client.identify(userId: "", traits: ["email": "private@example.com"])
        client.alias(newUserId: "")
        client.updateTraits(["name": "Private"])
        client.track(event: "Opened", properties: ["section": "intro", "mode": "custom-value"])
        flush(client)
        XCTAssertEqual(client.currentDistinctId(), identity)
        XCTAssertNil(client.currentAnonymousId())
        let payloads = try events()
        XCTAssertEqual(payloads.count, 1)
        try assertAudience(XCTUnwrap(payloads.first))
        let properties = try XCTUnwrap(payloads.first?["properties"] as? [String: Any])
        XCTAssertEqual(properties["section"] as? String, "intro")
        XCTAssertEqual(properties["mode"] as? String, "custom-value")
        XCTAssertEqual(properties["$release"] as? String, "test-release")
        XCTAssertEqual(properties["$lib"] as? String, "altertable-swift")
        for key in ["$device", "$device_model", "$os_version", "$app_namespace", "$viewport"] {
            XCTAssertNil(properties[key])
        }
        XCTAssertTrue(capturedRequests().allSatisfy { $0.url?.lastPathComponent == "track" })
        XCTAssertTrue(capturedRequests().allSatisfy { !$0.httpShouldHandleCookies })
    }

    func testScreenPropertiesCannotBypassAudiencePolicy() throws {
        let client = start()
        client.screen(name: "Docs", properties: [
            "$url": "https://user:password@SITE.example:443/docs%2Fintro?token=secret#hash",
            "$referer": "https://search.example/private?token=secret",
            "$viewport": "1234x987",
            "section": "installation",
        ])
        flush(client)
        let payload = try XCTUnwrap(events().first)
        assertAudience(payload)
        XCTAssertEqual(payload["event"] as? String, "$screen")
        let properties = try XCTUnwrap(payload["properties"] as? [String: Any])
        XCTAssertEqual(properties["$url"] as? String, "https://site.example/docs%2Fintro")
        XCTAssertEqual(properties["$referer"] as? String, "https://search.example")
        XCTAssertEqual(properties["$screen_name"] as? String, "Docs")
        XCTAssertEqual(properties["section"] as? String, "installation")
        XCTAssertNil(properties["$viewport"])
        XCTAssertNil(properties["token"])
        XCTAssertFalse(try XCTUnwrap(try String(data: XCTUnwrap(capturedRequests().first?.httpBody), encoding: .utf8)?
                .contains("secret")))
    }

    func testInvalidURLsBecomeNullAndCallerPropertiesRemainCallerOwned() throws {
        let client = start()
        for url in ["not a URL?token=secret", "javascript:secret", "/relative?token=secret"] {
            client.track(
                event: "Invalid URL",
                properties: ["$url": JSONValue(url), "$referer": 42, "email": "caller@example.com"]
            )
        }
        flush(client)
        for payload in try events() {
            let properties = try XCTUnwrap(payload["properties"] as? [String: Any])
            XCTAssertTrue(properties["$url"] is NSNull)
            XCTAssertTrue(properties["$referer"] is NSNull)
            XCTAssertEqual(properties["email"] as? String, "caller@example.com")
        }
    }

    func testAudienceDoesNotRestoreOrModifyProductStorage() throws {
        let product = start(mode: .product, consent: .pending)
        product.identify(userId: "signed-in")
        product.track(event: "Product Offline")
        _ = product.currentDistinctId()
        let queueURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("altertable_queue.json")
        let previousQueue = try Data(contentsOf: queueURL)
        // Stored denied consent must not override audience's explicit consent.
        UserDefaults.standard.set("denied", forKey: SDKConstants.StorageKeys.trackingConsent)
        let previousState = SDKConstants.StorageKeys.all.map { UserDefaults.standard.string(forKey: $0) }
        let audience = start()
        audience.track(event: "Audience Fresh")
        flush(audience)
        audience.configure { $0.trackingConsent = .pending }
        audience.track(event: "Audience Waiting")
        audience.reset(resetDeviceId: true, resetTrackingConsent: true)
        _ = audience.currentDistinctId()
        XCTAssertEqual(try Data(contentsOf: queueURL), previousQueue)
        XCTAssertEqual(SDKConstants.StorageKeys.all.map { UserDefaults.standard.string(forKey: $0) }, previousState)
        XCTAssertEqual(try events().compactMap { $0["event"] as? String }, ["Audience Fresh"])
        // Product can still restore its original queue after audience collection.
        UserDefaults.standard.set("pending", forKey: SDKConstants.StorageKeys.trackingConsent)
        let restoredProduct = start(mode: .product, consent: .pending)
        restoredProduct.configure { $0.trackingConsent = .granted }
        flush(restoredProduct)
        XCTAssertTrue(try events().contains { $0["event"] as? String == "Product Offline" })
    }

    func testPendingAndDismissedConsentQueueInMemoryThenGrantFlushes() throws {
        for consent: TrackingConsentState in [.pending, .dismissed] {
            let client = start(consent: consent)
            client.track(event: consent.rawValue)
            flush(client)
            XCTAssertFalse(capturedRequests()
                .contains { String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains(consent.rawValue) == true })
            client.configure { $0.trackingConsent = .granted }
            flush(client)
        }
        XCTAssertEqual(try events().compactMap { $0["event"] as? String }, ["pending", "dismissed"])
        try events().forEach { assertAudience($0) }
        XCTAssertTrue(QueueStorage(logger: Logger()).load().isEmpty)
    }

    func testDeniedClearsBufferedEventsAndRegrantResumes() throws {
        let client = start()
        client.track(event: "Buffered")
        client.configure { $0.trackingConsent = .denied }
        client.track(event: "Denied")
        flush(client)
        XCTAssertTrue(capturedRequests().isEmpty)
        client.configure { $0.trackingConsent = .granted }
        client.track(event: "Regranted")
        flush(client)
        XCTAssertEqual(try events().compactMap { $0["event"] as? String }, ["Regranted"])
    }

    func testNewAudienceClientDoesNotReplayPendingEventsOrConsent() throws {
        let first = start(consent: .pending)
        first.track(event: "Previous Client")
        flush(first)
        let second = start()
        second.track(event: "New Client")
        flush(second)
        XCTAssertEqual(try events().compactMap { $0["event"] as? String }, ["New Client"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("altertable_queue.json").path))
        XCTAssertTrue(SDKConstants.StorageKeys.all.allSatisfy { UserDefaults.standard.object(forKey: $0) == nil })
    }

    func testModeChangesRejectEntireUpdateInBothDirections() throws {
        for mode: TrackingMode in [.audience, .product] {
            let rejected = expectation(description: "Mode rejected")
            let client = start(mode: mode, onError: { _ in rejected.fulfill() })
            client.configure {
                $0.mode = mode == .audience ? .product : .audience
                $0.trackingConsent = .denied
                $0.environment = "changed"
            }
            client.track(event: mode.rawValue)
            flush(client)
            wait(for: [rejected], timeout: 1)
        }
        let payloads = try events()
        assertAudience(payloads[0])
        XCTAssertNil(payloads[1]["mode"])
        XCTAssertEqual(payloads[1]["environment"] as? String, "production")
        XCTAssertNotNil(payloads[1]["distinct_id"])
        XCTAssertNotNil(payloads[1]["session_id"])
    }

    func testBatchingAndHTTPRetryPreserveAudiencePolicy() throws {
        let client = start(consent: .pending, maxBatchSize: 2)
        client.setRetryBaseDelay(0.001)
        var attempts = 0
        MockURLProtocol.requestHandler = { [self] request in
            lock.lock()
            requests.append(request)
            attempts += 1
            let status = attempts == 1 ? 503 : 200
            lock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, nil)
        }
        for index in 0 ..< 3 {
            client.track(event: "Event \(index)")
        }
        client.configure { $0.trackingConsent = .granted }
        flush(client)
        XCTAssertEqual(capturedRequests().count, 3)
        for request in capturedRequests() {
            let payloads = try TestJSON.objectArray(from: XCTUnwrap(request.httpBody))
            XCTAssertLessThanOrEqual(payloads.count, 2)
            XCTAssertFalse(request.httpShouldHandleCookies)
            payloads.forEach { assertAudience($0) }
        }
        XCTAssertTrue(QueueStorage(logger: Logger()).load().isEmpty)
    }

    func testExhaustedHTTPRetriesRequeueAudienceBatchInMemory() throws {
        let client = start()
        client.setRetryBaseDelay(0.001)
        var attempts = 0
        MockURLProtocol.requestHandler = { [self] request in
            lock.lock()
            requests.append(request)
            attempts += 1
            let status = attempts <= SDKConstants.httpRetryMaxAttempts ? 503 : 200
            lock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, nil)
        }
        client.track(event: "Requeued")
        flush(client)
        XCTAssertEqual(capturedRequests().count, SDKConstants.httpRetryMaxAttempts + 1)
        let normalizedBodies = try events().map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        XCTAssertEqual(Set(normalizedBodies).count, 1)
        try events().forEach { assertAudience($0) }
        let queueURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("altertable_queue.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueURL.path))
    }

    func testOldPersistedProductPayloadDecodesWithoutMode() throws {
        XCTAssertEqual(AltertableConfig().mode, .product)
        let data = Data("""
        {"timestamp":"2026-11-04T00:00:00Z","event":"Old Product","environment":"production",
        "deviceId":"device-old","distinctId":"user-old","sessionId":"session-old","properties":{}}
        """.utf8)
        let payload = try JSONDecoder().decode(TrackPayload.self, from: data)
        XCTAssertNil(payload.mode)
        XCTAssertEqual(payload.distinctId, "user-old")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encoded = try TestJSON.firstObject(from: encoder.encode(payload))
        XCTAssertNil(encoded["mode"])
        XCTAssertEqual(encoded["device_id"] as? String, "device-old")
    }
}
