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
        
        // Setup Mock URL Session
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
    
    override func tearDown() {
        client = nil
        session = nil
        super.tearDown()
    }
    
    func testInitialization() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        XCTAssertNotNil(client)
    }
    
    func testTrackRequest() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        
        let expectation = self.expectation(description: "Request Sent")
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            
            XCTAssertEqual(url.host, "api.altertable.ai")
            XCTAssertEqual(url.path, "/track")
            XCTAssertEqual(request.httpMethod, "POST")
            
            // Verify query param
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let apiKeyItem = components?.queryItems?.first(where: { $0.name == "apiKey" })
            XCTAssertEqual(apiKeyItem?.value, "pk_test_123")
            
            // Verify body
            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
                XCTAssertEqual(json?["event"] as? String, "test_event")
                XCTAssertEqual(json?["environment"] as? String, "production")
                XCTAssertNotNil(json?["session_id"])
                XCTAssertNotNil(json?["device_id"])
                XCTAssertNotNil(json?["distinct_id"])
                
                let properties = json?["properties"] as? [String: Any]
                XCTAssertEqual(properties?["foo"] as? String, "bar")
            } else {
                XCTFail("Missing http body")
            }
            
            expectation.fulfill()
            
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }
        
        client.track(event: "test_event", properties: ["foo": AnyCodable("bar")])
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    func testIdentify() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        
        let expectation = self.expectation(description: "Identify Request")
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            XCTAssertEqual(url.path, "/identify")
            XCTAssertEqual(request.httpMethod, "POST")
            
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["distinct_id"] as? String, "user_123")
                XCTAssertNotNil(json["anonymous_id"], "Should have anonymous_id linked")
                
                let traits = json["traits"] as? [String: Any]
                XCTAssertEqual(traits?["email"] as? String, "user@example.com")
            }
            
            expectation.fulfill()
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        
        client.identify(userId: "user_123", traits: ["email": AnyCodable("user@example.com")])
        waitForExpectations(timeout: 1.0)
    }
    
    func testAlias() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        
        let expectation = self.expectation(description: "Alias Request")
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            XCTAssertEqual(url.path, "/alias")
            XCTAssertEqual(request.httpMethod, "POST")
            
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["new_user_id"] as? String, "new_user_456")
                XCTAssertNotNil(json["distinct_id"])
            }
            
            expectation.fulfill()
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        
        client.alias(newUserId: "new_user_456")
        waitForExpectations(timeout: 1.0)
    }
    
    func testReset() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        client.identify(userId: "user_123")
        client.reset()
        
        let expectation = self.expectation(description: "Track after reset")
        
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                let distinctId = json["distinct_id"] as? String
                XCTAssertNotEqual(distinctId, "user_123")
                XCTAssertTrue(distinctId?.starts(with: "anonymous-") ?? false)
                
                // anonymous_id should be null/absent after reset
                let anonymousId = json["anonymous_id"]
                if let anonymousId = anonymousId {
                     XCTAssertTrue(anonymousId is NSNull, "anonymous_id should be null")
                }
            }
            expectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        
        client.track(event: "post_reset")
        waitForExpectations(timeout: 1.0)
    }
    
    // Test session renewal
    func testSessionRenewal() {
        client = Altertable(apiKey: "pk_test_123", session: session)
        
        var firstSessionId: String?
        
        let exp1 = self.expectation(description: "First Request")
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                firstSessionId = json["session_id"] as? String
            }
            exp1.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        client.track(event: "first")
        wait(for: [exp1], timeout: 1.0)
        
        XCTAssertNotNil(firstSessionId)
        
        // Immediate second request should have same session ID
        let exp2 = self.expectation(description: "Second Request")
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["session_id"] as? String, firstSessionId)
            }
            exp2.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        client.track(event: "second")
        wait(for: [exp2], timeout: 1.0)
    }
}
