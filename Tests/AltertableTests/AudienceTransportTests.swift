@testable import Altertable
import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import XCTest

final class AudienceTransportTests: XCTestCase {
    func testAudienceDeliveryNeverSendsOrPersistsCookiesAcrossRedirects() throws {
        let cookieName = "altertable_audience_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let server = try LoopbackHTTPServer(expectedRequestCount: 3) { index, _ in
            switch index {
            case 0:
                return .init(status: 307, headers: [
                    "Location": "/redirect",
                    "Set-Cookie": "\(cookieName)=first; Path=/",
                ])
            case 1:
                return .init(status: 200, headers: ["Set-Cookie": "\(cookieName)=second; Path=/"])
            default:
                return .init(status: 200, headers: [:])
            }
        }
        let noError = expectation(description: "No audience transport error")
        noError.isInverted = true
        let client = Altertable(apiKey: "key", config: .init(
            mode: .audience,
            baseURL: server.baseURL,
            onError: { _ in noError.fulfill() },
            captureScreenViews: false,
            flushEventThreshold: 1,
            flushIntervalMs: 86_400_000
        ))

        flush(client)
        client.track(event: "First")
        flush(client)
        client.track(event: "Second")
        flush(client)

        let requests = server.requests()
        XCTAssertEqual(requests.map(\.path), ["/track", "/redirect", "/track"])
        XCTAssertTrue(requests.allSatisfy { $0.headers["cookie"] == nil })
        let payload = try TestJSON.firstObject(from: requests[0].body)
        XCTAssertEqual(payload["mode"] as? String, "audience")
        XCTAssertEqual(Set(payload.keys), Set(["mode", "event", "timestamp", "properties"]))
        XCTAssertNil(HTTPCookieStorage.shared.cookies(for: server.baseURL)?.first { $0.name == cookieName })
        wait(for: [noError], timeout: 0.1)
    }

    func testProductDeliveryStillAcceptsCookies() throws {
        let cookieName = "altertable_product_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let server = try LoopbackHTTPServer(expectedRequestCount: 2) { index, _ in
            index == 0
                ? .init(status: 200, headers: ["Set-Cookie": "\(cookieName)=saved; Path=/"])
                : .init(status: 200, headers: [:])
        }
        defer { HTTPCookieStorage.shared.cookies(for: server.baseURL)?.filter { $0.name == cookieName }.forEach(HTTPCookieStorage.shared.deleteCookie) }
        let noError = expectation(description: "No product transport error")
        noError.isInverted = true
        let client = Altertable(apiKey: "key", config: .init(
            baseURL: server.baseURL,
            onError: { _ in noError.fulfill() },
            captureScreenViews: false,
            flushEventThreshold: 1,
            flushIntervalMs: 86_400_000
        ))

        client.track(event: "First")
        flush(client)
        client.track(event: "Second")
        flush(client)

        let requests = server.requests()
        XCTAssertEqual(requests.map(\.path), ["/track", "/track"])
        XCTAssertEqual(requests[1].headers["cookie"], "\(cookieName)=saved")
        XCTAssertNotNil(HTTPCookieStorage.shared.cookies(for: server.baseURL)?.first { $0.name == cookieName })
        wait(for: [noError], timeout: 0.1)
    }

    private func flush(_ client: Altertable) {
        let delivered = expectation(description: "Event delivered")
        client.flush { delivered.fulfill() }
        wait(for: [delivered], timeout: 3)
    }
}
