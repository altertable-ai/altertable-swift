//
//  RequesterBatchTests.swift
//  AltertableTests
//

import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import Altertable

final class RequesterBatchTests: XCTestCase {
    func testSendBatchEncodesJsonArrayBody() {
        #if canImport(FoundationNetworking)
            let sessionConfig = URLSessionConfiguration.default
        #else
            let sessionConfig = URLSessionConfiguration.ephemeral
        #endif
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let expectation = expectation(description: "batch request")

        MockURLProtocol.requestHandler = { request in
            guard let body = request.httpBody else {
                XCTFail("missing body")
                throw URLError(.badURL)
            }
            let parsed = try JSONSerialization.jsonObject(with: body, options: [])
            guard let array = parsed as? [[String: Any]] else {
                XCTFail("expected JSON array root")
                throw URLError(.badURL)
            }
            XCTAssertEqual(array.count, 2)
            XCTAssertEqual(array[0]["event"] as? String, "a")
            XCTAssertEqual(array[1]["event"] as? String, "b")

            expectation.fulfill()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        let requester = Requester(apiKey: "pk_batch", requestTimeout: 5, session: session)
        let payloads = [
            TrackPayload(
                timestamp: "t",
                event: "a",
                environment: "e",
                deviceId: "d",
                distinctId: "u",
                anonymousId: nil,
                sessionId: "s",
                properties: [:]
            ),
            TrackPayload(
                timestamp: "t",
                event: "b",
                environment: "e",
                deviceId: "d",
                distinctId: "u",
                anonymousId: nil,
                sessionId: "s",
                properties: [:]
            ),
        ]

        let baseURL = URL(string: "https://api.example.com")!
        requester.sendBatch(payloads, baseURL: baseURL) { _ in }

        waitForExpectations(timeout: 1.0)
    }
}
