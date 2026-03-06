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
    func testQueuePersistence() {
        // Clear queue file before test
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("altertable_queue.json")
        try? FileManager.default.removeItem(at: fileURL)
        
        let config1 = AltertableConfig(apiKey: "pk_test_1", trackingConsent: .pending)
        
        // Setup mock for first client (to prevent actual networking if it tries)
        #if canImport(FoundationNetworking)
        let sessionConfig = URLSessionConfiguration.default
        #else
        let sessionConfig = URLSessionConfiguration.ephemeral
        #endif
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        MockURLProtocol.requestHandler = { _ in 
            // Should not be called because consent is pending
            return (HTTPURLResponse(url: URL(string: "http://test")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        
        let client1 = Altertable(apiKey: "pk_test_1", config: config1, session: session)
        client1.track(event: "persisted_event")
        
        // Wait for async write? It's synchronous in our implementation.
        
        // Create new client - should load queue
        let config2 = AltertableConfig(apiKey: "pk_test_1", trackingConsent: .pending)
        let client2 = Altertable(apiKey: "pk_test_1", config: config2, session: session)
        
        // We can't access private queue directly.
        // But we can flush and see if it sends.
        
        let expectation = self.expectation(description: "Flush loaded event")
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if (json["event"] as? String) == "persisted_event" {
                    expectation.fulfill()
                }
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        
        client2.configure(PartialAltertableConfig(trackingConsent: .granted))
        
        waitForExpectations(timeout: 1.0)
    }
}
