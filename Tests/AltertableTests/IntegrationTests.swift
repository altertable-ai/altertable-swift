//
//  IntegrationTests.swift
//  AltertableTests
//

import XCTest
@testable import Altertable

// Integration tests run against the altertable-mock server (ghcr.io/altertable-ai/altertable-mock).
// In CI the mock is started automatically via the GitHub Actions service defined in test.yml.
// To run locally: docker run -p 15001:15001 \
//   -e ALTERTABLE_MOCK_API_KEYS="test_pk_abc123" \
//   -e ALTERTABLE_MOCK_ENVIRONMENTS="production,integration-test" \
//   ghcr.io/altertable-ai/altertable-mock

final class IntegrationTests: XCTestCase {
    private static let mockBaseURL = "http://localhost:15001"
    private static let apiKey = "test_pk_abc123"
    private static let environment = "integration-test"

    override func setUp() {
        super.setUp()
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - Helpers

    /// Returns a client pre-configured for the mock plus an inverted expectation that
    /// fails the test if `onError` is ever called.
    private func makeClient(environment: String = IntegrationTests.environment) -> (Altertable, XCTestExpectation) {
        let noErrorExp = expectation(description: "No error (\(environment))")
        noErrorExp.isInverted = true

        let config = AltertableConfig(
            baseURL: IntegrationTests.mockBaseURL,
            environment: environment,
            onError: { error in
                XCTFail("Unexpected SDK error: \(error)")
                noErrorExp.fulfill()
            }
        )
        let client = Altertable(apiKey: IntegrationTests.apiKey, config: config)
        // Speed up retries so a genuine error surfaces quickly in tests.
        client.setRetryBaseDelay(0.1)
        return (client, noErrorExp)
    }

    // MARK: - track

    func testTrackSucceeds() {
        let (client, noError) = makeClient()

        client.track(event: "Button Clicked", properties: [
            "button": AnyCodable("signup"),
            "page": AnyCodable("home"),
        ])

        wait(for: [noError], timeout: 3.0)
    }

    // MARK: - identify

    func testIdentifySucceeds() {
        let (client, noError) = makeClient()

        client.identify(userId: "user_integration_123", traits: [
            "plan": AnyCodable("premium"),
            "email": AnyCodable("test@example.com"),
        ])

        wait(for: [noError], timeout: 3.0)
    }

    // MARK: - alias

    func testAliasSucceeds() {
        let (client, noError) = makeClient()

        client.identify(userId: "user_pre_alias")
        client.alias(newUserId: "user_post_alias")

        wait(for: [noError], timeout: 3.0)
    }

    // MARK: - updateTraits

    func testUpdateTraitsSucceeds() {
        let (client, noError) = makeClient()

        client.identify(userId: "user_traits_123")
        client.updateTraits([
            "plan": AnyCodable("enterprise"),
            "onboarded": AnyCodable(true),
        ])

        wait(for: [noError], timeout: 3.0)
    }

    // MARK: - Error cases

    func testUnknownEnvironmentErrors() {
        let errorExp = expectation(description: "Error for unknown environment")

        let config = AltertableConfig(
            baseURL: IntegrationTests.mockBaseURL,
            environment: "nonexistent-env",
            onError: { _ in errorExp.fulfill() }
        )
        let client = Altertable(apiKey: IntegrationTests.apiKey, config: config)
        client.setRetryBaseDelay(0.1)

        client.track(event: "should_fail")

        wait(for: [errorExp], timeout: 5.0)
    }

    func testInvalidApiKeyErrors() {
        let errorExp = expectation(description: "Error for invalid API key")

        let config = AltertableConfig(
            baseURL: IntegrationTests.mockBaseURL,
            environment: IntegrationTests.environment,
            onError: { _ in errorExp.fulfill() }
        )
        let client = Altertable(apiKey: "invalid_key_xyz", config: config)
        client.setRetryBaseDelay(0.1)

        client.track(event: "should_fail")

        wait(for: [errorExp], timeout: 5.0)
    }

    // MARK: - Full funnel

    func testFullAnonymousToIdentifiedFunnel() {
        let (client, noError) = makeClient()

        // Anonymous phase
        client.track(event: "Page Viewed", properties: ["page": AnyCodable("landing")])

        // Identification
        client.identify(userId: "user_funnel_789", traits: [
            "email": AnyCodable("funnel@example.com"),
            "source": AnyCodable("organic"),
        ])

        // Authenticated events
        client.track(event: "Signup Completed")
        client.track(event: "Plan Selected", properties: ["plan": AnyCodable("pro"), "price": AnyCodable(29)])
        client.updateTraits(["onboarded": AnyCodable(true)])

        wait(for: [noError], timeout: 5.0)
    }

    // MARK: - Consent

    func testConsentPendingQueuesThenFlushesOnGrant() {
        let noError = expectation(description: "No error after consent granted")
        noError.isInverted = true

        let config = AltertableConfig(
            baseURL: IntegrationTests.mockBaseURL,
            environment: IntegrationTests.environment,
            trackingConsent: .pending,
            onError: { error in
                XCTFail("Unexpected SDK error: \(error)")
                noError.fulfill()
            }
        )
        let client = Altertable(apiKey: IntegrationTests.apiKey, config: config)
        client.setRetryBaseDelay(0.1)

        // Queued while consent is pending — must not be sent yet
        client.track(event: "queued_event", properties: ["source": AnyCodable("pre-consent")])
        client.identify(userId: "user_pending_consent")

        // Granting consent flushes the queue
        client.configure(PartialAltertableConfig(trackingConsent: .granted))

        wait(for: [noError], timeout: 5.0)
    }

    // MARK: - Batch

    func testMultipleSequentialEventsSucceed() {
        let (client, noError) = makeClient()

        client.identify(userId: "user_batch_456")
        for step in 1 ... 5 {
            client.track(event: "Step Completed", properties: ["step": AnyCodable(step)])
        }

        wait(for: [noError], timeout: 5.0)
    }
}
