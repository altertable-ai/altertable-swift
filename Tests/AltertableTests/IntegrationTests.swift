//
//  IntegrationTests.swift
//  AltertableTests
//

import XCTest
@testable import Altertable

final class IntegrationTests: XCTestCase {
    var client: Altertable!
    
    // The mock service container is running on localhost:15001
    // Defined in .github/workflows/test.yml
    let mockBaseURL = "http://localhost:15001"
    
    override func setUp() {
        super.setUp()
        // Clear storage to ensure fresh state
        SDKConstants.StorageKeys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
    
    override func tearDown() {
        client = nil
        super.tearDown()
    }
    
    func testEndToEndTracking() {
        // Only run if the mock is reachable or we are in CI to avoid local flakes
        // For now, we assume if you run this, you have the mock.
        
        let expectation = expectation(description: "Requests complete without error")
        
        let config = AltertableConfig(
            baseURL: mockBaseURL,
            environment: "integration-test",
            debug: true
        )
        
        // We use a latch to wait for async operations
        let latch = DispatchGroup()
        
        config.onError = { error in
            XCTFail("Integration test failed with error: \(error)")
        }
        
        client = Altertable(apiKey: "test_pk_abc123", config: config)
        
        latch.enter()
        client.identify(userId: "user_integration_123", traits: ["plan": AnyCodable("premium")])
        
        latch.enter()
        client.track(event: "integration_event_A", properties: ["foo": AnyCodable("bar")])
        
        // Wait a bit for requests to flush (since we don't have a completion callback for success)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            latch.leave()
            latch.leave()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}
