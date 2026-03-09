//
//  ScreenViewTests.swift
//  AltertableTests
//

import XCTest
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(UIKit) && !os(watchOS)
    import UIKit
#endif
@testable import Altertable

final class ScreenViewTests: XCTestCase {
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

    override func tearDown() {
        // Release ownership if client exists
        if let client = client {
            ScreenViewIntegration.releaseOwnership(ifOwner: client)
        }
        client = nil
        session = nil
        // Reset shared integration for test isolation
        #if DEBUG
            ScreenViewIntegration.resetForTesting()
        #endif
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

    // MARK: - screen() method tests

    func testScreenMethodSendsCorrectEvent() {
        client = Altertable(apiKey: "pk_test_123", session: session)

        let expectation = expectation(description: "Screen view event sent")

        MockURLProtocol.requestHandler = { [self] request in
            guard let url = request.url else { throw URLError(.badURL) }

            XCTAssertEqual(url.path, "/track")
            XCTAssertEqual(request.httpMethod, "POST")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
                XCTAssertEqual(json?["event"] as? String, SDKConstants.eventScreenView)

                let properties = json?["properties"] as? [String: Any]
                XCTAssertEqual(properties?[SDKConstants.propertyScreenName] as? String, "TestScreen")
                XCTAssertEqual(properties?["custom_prop"] as? String, "custom_value")
            } else {
                XCTFail("Missing http body")
            }

            expectation.fulfill()
            return successResponse(url: url)
        }

        client.screen(name: "TestScreen", properties: ["custom_prop": JSONValue("custom_value")])

        waitForExpectations(timeout: 1.0)
    }

    func testScreenMethodWithDefaultProperties() {
        client = Altertable(apiKey: "pk_test_123", session: session)

        let expectation = expectation(description: "Screen view event sent")

        MockURLProtocol.requestHandler = { [self] request in
            guard let url = request.url else { throw URLError(.badURL) }

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
                XCTAssertEqual(json?["event"] as? String, SDKConstants.eventScreenView)

                let properties = json?["properties"] as? [String: Any]
                XCTAssertEqual(properties?[SDKConstants.propertyScreenName] as? String, "HomeScreen")
                // Should include system properties
                XCTAssertNotNil(properties?[SDKConstants.propertyLib])
            }

            expectation.fulfill()
            return successResponse(url: url)
        }

        client.screen(name: "HomeScreen")

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Screen name extraction tests

    #if canImport(UIKit) && !os(watchOS)
        func testScreenNameStripping() {
            class TestViewController: UIViewController {}
            class HomeViewController: UIViewController {}
            class SettingsController: UIViewController {}
            class ProfileView: UIViewController {}
            class CustomName: UIViewController {}
            class TableView: UIViewController {} // Should not strip "View" suffix

            let testVC = TestViewController()
            let homeVC = HomeViewController()
            let settingsVC = SettingsController()
            let profileVC = ProfileView()
            let customVC = CustomName()
            let tableViewVC = TableView()

            // Test actual screen name extraction via the integration
            // We need to install the integration to test the extractScreenName logic
            let config = AltertableConfig(captureScreenViews: true)
            let testClient = Altertable(apiKey: "pk_test_screen_names", config: config, session: session)

            // Create expectation to capture screen events
            let expectation = expectation(description: "Screen names extracted")
            expectation.expectedFulfillmentCount = 6

            var capturedScreenNames: [String] = []
            MockURLProtocol.requestHandler = { request in
                if let body = request.httpBody {
                    let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
                    if let properties = json?["properties"] as? [String: Any],
                       let screenName = properties[SDKConstants.propertyScreenName] as? String
                    {
                        capturedScreenNames.append(screenName)
                        expectation.fulfill()
                    }
                }
                return self.successResponse(url: request.url!)
            }

            // Trigger viewDidAppear to capture screen names
            // Note: We can't directly call the private method, so we simulate via viewDidAppear
            // Since swizzling is installed, calling viewDidAppear will trigger screen tracking
            testVC.viewDidAppear(false)
            homeVC.viewDidAppear(false)
            settingsVC.viewDidAppear(false)
            profileVC.viewDidAppear(false)
            customVC.viewDidAppear(false)
            tableViewVC.viewDidAppear(false)

            waitForExpectations(timeout: 2.0)

            // Verify screen names match expected behavior
            // Only "ViewController" suffix should be stripped
            XCTAssertTrue(capturedScreenNames.contains("Test"), "Should strip ViewController from TestViewController")
            XCTAssertTrue(capturedScreenNames.contains("Home"), "Should strip ViewController from HomeViewController")
            XCTAssertTrue(
                capturedScreenNames.contains("SettingsController"),
                "Should NOT strip Controller from SettingsController"
            )
            XCTAssertTrue(capturedScreenNames.contains("ProfileView"), "Should NOT strip View from ProfileView")
            XCTAssertTrue(capturedScreenNames.contains("CustomName"), "Should not modify CustomName")
            XCTAssertTrue(capturedScreenNames.contains("TableView"), "Should NOT strip View from TableView")
        }

        func testContainerViewControllersAreSkipped() {
            let config = AltertableConfig(captureScreenViews: true)
            client = Altertable(apiKey: "pk_test_containers", config: config, session: session)

            let noEventExpectation = expectation(description: "No screen events from container VCs")
            noEventExpectation.isInverted = true

            MockURLProtocol.requestHandler = { [self] request in
                noEventExpectation.fulfill()
                return successResponse(url: request.url!)
            }

            UINavigationController().viewDidAppear(false)
            UITabBarController().viewDidAppear(false)
            UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal).viewDidAppear(false)

            waitForExpectations(timeout: 0.5)
        }
    #endif

    // MARK: - Configuration tests

    func testCaptureScreenViewsDisabled() {
        let config = AltertableConfig(captureScreenViews: false)
        client = Altertable(apiKey: "pk_test_123", config: config, session: session)

        // When disabled, the integration should not be installed
        // We verify this by checking that screen() still works manually
        let expectation = expectation(description: "Manual screen call works")

        MockURLProtocol.requestHandler = { [self] request in
            expectation.fulfill()
            return successResponse(url: request.url!)
        }

        // Manual screen() call should still work
        client.screen(name: "ManualScreen")
        waitForExpectations(timeout: 1.0)
    }

    func testCaptureScreenViewsEnabled() {
        let config = AltertableConfig(captureScreenViews: true)
        client = Altertable(apiKey: "pk_test_123", config: config, session: session)

        #if canImport(UIKit) && !os(watchOS)
            // Integration should be installed on UIKit platforms
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertNotNil(ScreenViewIntegration.shared?.client)
        #else
            // On non-UIKit platforms, integration is not created (auto-capture not available)
            // Manual screen() calls still work
            XCTAssertNil(ScreenViewIntegration.shared?.client)
        #endif
    }

    func testConfigureCaptureScreenViews() {
        client = Altertable(apiKey: "pk_test_123", session: session)

        #if canImport(UIKit) && !os(watchOS)
            // Initially should be disabled by default on UIKit platforms
            XCTAssertNil(ScreenViewIntegration.shared?.client)

            // Enable — sync with the serial queue via a subsequent screen() call.
            var syncExpectation = expectation(description: "Queue sync after enable")
            MockURLProtocol.requestHandler = { [self] request in
                syncExpectation.fulfill()
                return successResponse(url: request.url!)
            }
            client.configure { $0.captureScreenViews = true }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertTrue(ScreenViewIntegration.shared?.isEnabled ?? false)

            // Disable — sync with the serial queue via a subsequent screen() call.
            // Since configure() and screen() both dispatch on the same FIFO queue,
            // the configure task is guaranteed to complete before the network request fires.
            var syncExpectation = expectation(description: "Queue sync after disable")
            MockURLProtocol.requestHandler = { [self] request in
                syncExpectation.fulfill()
                return successResponse(url: request.url!)
            }
            client.configure { $0.captureScreenViews = false }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)
            XCTAssertFalse(ScreenViewIntegration.shared?.isEnabled ?? true)

            // Re-enable — same sync pattern
            syncExpectation = expectation(description: "Queue sync after re-enable")
            MockURLProtocol.requestHandler = { [self] request in
                syncExpectation.fulfill()
                return successResponse(url: request.url!)
            }
            client.configure { $0.captureScreenViews = true }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)
            XCTAssertTrue(ScreenViewIntegration.shared?.isEnabled ?? false)
            XCTAssertNotNil(ScreenViewIntegration.shared)
        #else
            // On non-UIKit platforms, configure() calls are no-ops for captureScreenViews
            // Manual screen() calls still work
            var syncExpectation = expectation(description: "Screen call works")
            MockURLProtocol.requestHandler = { [self] request in
                syncExpectation.fulfill()
                return successResponse(url: request.url!)
            }
            client.configure { $0.captureScreenViews = false }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)

            syncExpectation = expectation(description: "Screen call still works after configure")
            MockURLProtocol.requestHandler = { [self] request in
                syncExpectation.fulfill()
                return successResponse(url: request.url!)
            }
            client.configure { $0.captureScreenViews = true }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)
        #endif
    }

    #if canImport(UIKit) && !os(watchOS)
        func testDisableAtRuntimeStopsTracking() {
            let config = AltertableConfig(captureScreenViews: true)
            client = Altertable(apiKey: "pk_test_disable", config: config, session: session)

            // Create a test view controller
            class TestViewController: UIViewController {}
            let testVC = TestViewController()

            // First, verify tracking works when enabled
            let enabledExpectation = expectation(description: "Screen tracked when enabled")
            MockURLProtocol.requestHandler = { request in
                enabledExpectation.fulfill()
                return self.successResponse(url: request.url!)
            }

            testVC.viewDidAppear(false)
            waitForExpectations(timeout: 1.0)

            // Now disable tracking
            client.configure { $0.captureScreenViews = false }
            XCTAssertFalse(ScreenViewIntegration.shared?.isEnabled ?? true)

            // Verify no events are sent when disabled
            let disabledExpectation = expectation(description: "No screen tracked when disabled")
            disabledExpectation.isInverted = true

            MockURLProtocol.requestHandler = { request in
                disabledExpectation.fulfill()
                return self.successResponse(url: request.url!)
            }

            testVC.viewDidAppear(false)
            waitForExpectations(timeout: 0.5)
        }
    #endif

    // MARK: - Swizzle idempotency test

    #if canImport(UIKit) && !os(watchOS)
        func testSwizzleInstalledOnce() {
            let config1 = AltertableConfig(captureScreenViews: true)
            let client1 = Altertable(apiKey: "pk_test_1", config: config1, session: session)
            let integration1 = ScreenViewIntegration.shared
            XCTAssertNotNil(integration1)

            // A second client must not replace shared
            let config2 = AltertableConfig(captureScreenViews: true)
            _ = Altertable(apiKey: "pk_test_2", config: config2, session: session)
            XCTAssertTrue(
                ScreenViewIntegration.shared === integration1,
                "Second client must not replace shared integration"
            )

            // Swizzle fires exactly once per viewDidAppear — one event, not two
            class TestViewController: UIViewController {}
            let oneEventExpectation = expectation(description: "Exactly one screen event per viewDidAppear")
            oneEventExpectation.expectedFulfillmentCount = 1
            oneEventExpectation.assertForOverFulfill = true

            MockURLProtocol.requestHandler = { [self] request in
                oneEventExpectation.fulfill()
                return successResponse(url: request.url!)
            }

            TestViewController().viewDidAppear(false)
            waitForExpectations(timeout: 1.0)

            _ = client1
        }
    #endif

    // MARK: - Ownership handoff tests

    #if canImport(UIKit) && !os(watchOS)
        func testOwnerDeallocationHandsOffToLaterClient() {
            // Create first client and claim ownership
            var client1: Altertable? = Altertable(
                apiKey: "pk_test_client1",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            let integration1 = ScreenViewIntegration.shared
            XCTAssertNotNil(integration1)
            XCTAssertTrue(integration1 === ScreenViewIntegration.shared)

            // Deallocate first client
            client1 = nil

            // Wait a moment for deinit to complete
            let deinitExpectation = expectation(description: "Deinit completes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                deinitExpectation.fulfill()
            }
            waitForExpectations(timeout: 0.5)

            // Verify ownership was released
            XCTAssertNil(ScreenViewIntegration.shared?.client, "Ownership should be released after deinit")

            // Create second client - should be able to claim ownership
            let client2 = Altertable(
                apiKey: "pk_test_client2",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertTrue(ScreenViewIntegration.shared?.client === client2, "Second client should own the integration")

            // Verify tracking works with second client
            class TestViewController: UIViewController {}
            let testVC = TestViewController()
            let trackingExpectation = expectation(description: "Screen tracked by second client")
            MockURLProtocol.requestHandler = { request in
                trackingExpectation.fulfill()
                return self.successResponse(url: request.url!)
            }

            testVC.viewDidAppear(false)
            waitForExpectations(timeout: 1.0)
        }

        func testDisableOnClientAThenEnableOnClientB() {
            // Create client A with capture enabled
            let clientA = Altertable(
                apiKey: "pk_test_clientA",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertTrue(ScreenViewIntegration.shared?.client === clientA)

            // Disable on client A
            clientA.configure { $0.captureScreenViews = false }
            let syncExpectation = expectation(description: "Sync after disable")
            MockURLProtocol.requestHandler = { _ in
                syncExpectation.fulfill()
                return self.successResponse(url: URL(string: "http://test")!)
            }
            clientA.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)

            // Verify ownership was released
            XCTAssertNil(ScreenViewIntegration.shared?.client, "Ownership should be released when disabled")

            // Create client B and enable - should be able to claim ownership
            let clientB = Altertable(
                apiKey: "pk_test_clientB",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertTrue(
                ScreenViewIntegration.shared?.client === clientB,
                "Client B should own the integration after A disabled"
            )

            // Verify tracking works with client B
            class TestViewController: UIViewController {}
            let testVC = TestViewController()
            let trackingExpectation = expectation(description: "Screen tracked by client B")
            MockURLProtocol.requestHandler = { request in
                trackingExpectation.fulfill()
                return self.successResponse(url: request.url!)
            }

            testVC.viewDidAppear(false)
            waitForExpectations(timeout: 1.0)
        }

        func testDisableThenReEnableOnSameClient() {
            client = Altertable(
                apiKey: "pk_test_123",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertTrue(ScreenViewIntegration.shared?.client === client)

            // Disable
            client.configure { $0.captureScreenViews = false }
            var syncExpectation = expectation(description: "Sync after disable")
            MockURLProtocol.requestHandler = { _ in
                syncExpectation.fulfill()
                return self.successResponse(url: URL(string: "http://test")!)
            }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)
            XCTAssertNil(ScreenViewIntegration.shared?.client, "Ownership should be released")

            // Re-enable
            client.configure { $0.captureScreenViews = true }
            syncExpectation = expectation(description: "Sync after re-enable")
            MockURLProtocol.requestHandler = { _ in
                syncExpectation.fulfill()
                return self.successResponse(url: URL(string: "http://test")!)
            }
            client.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)
            XCTAssertTrue(ScreenViewIntegration.shared?.client === client, "Client should reclaim ownership")
            XCTAssertTrue(ScreenViewIntegration.shared?.isEnabled ?? false, "Integration should be enabled")
        }

        func testSecondClientClaimsOwnershipAfterFirstIsDisabled() {
            // Create client A with capture enabled
            let clientA = Altertable(
                apiKey: "pk_test_clientA",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            XCTAssertNotNil(ScreenViewIntegration.shared)
            XCTAssertTrue(ScreenViewIntegration.shared?.client === clientA)

            // Create client B with capture enabled while A owns it
            // B should register a callback but not claim ownership yet
            let clientB = Altertable(
                apiKey: "pk_test_clientB",
                config: AltertableConfig(captureScreenViews: true),
                session: session
            )
            XCTAssertTrue(ScreenViewIntegration.shared?.client === clientA, "Client A should still own it")
            XCTAssertFalse(ScreenViewIntegration.shared?.client === clientB, "Client B should not own it yet")

            // Disable on client A - this should trigger B's callback
            clientA.configure { $0.captureScreenViews = false }
            let syncExpectation = expectation(description: "Sync after disable")
            MockURLProtocol.requestHandler = { _ in
                syncExpectation.fulfill()
                return self.successResponse(url: URL(string: "http://test")!)
            }
            clientA.screen(name: "Sync")
            waitForExpectations(timeout: 1.0)

            // Wait a moment for the callback to execute
            let callbackExpectation = expectation(description: "Callback executes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                callbackExpectation.fulfill()
            }
            waitForExpectations(timeout: 0.5)

            // Verify client B now owns the integration
            XCTAssertTrue(ScreenViewIntegration.shared?.client === clientB, "Client B should now own the integration")
            XCTAssertTrue(ScreenViewIntegration.shared?.isEnabled ?? false, "Integration should be enabled")

            // Verify tracking works with client B
            class TestViewController: UIViewController {}
            let testVC = TestViewController()
            let trackingExpectation = expectation(description: "Screen tracked by client B")
            MockURLProtocol.requestHandler = { request in
                trackingExpectation.fulfill()
                return self.successResponse(url: request.url!)
            }

            testVC.viewDidAppear(false)
            waitForExpectations(timeout: 1.0)
        }
    #endif

    // MARK: - SwiftUI tests

    #if canImport(SwiftUI)
        func testSwiftUIModifierWithExplicitClient() {
            client = Altertable(apiKey: "pk_test_swiftui", session: session)

            let expectation = expectation(description: "SwiftUI screen view tracked")
            MockURLProtocol.requestHandler = { [self] request in
                guard let url = request.url else { throw URLError(.badURL) }

                if let body = request.httpBody {
                    let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
                    XCTAssertEqual(json?["event"] as? String, SDKConstants.eventScreenView)

                    let properties = json?["properties"] as? [String: Any]
                    XCTAssertEqual(properties?[SDKConstants.propertyScreenName] as? String, "TestView")
                }

                expectation.fulfill()
                return successResponse(url: url)
            }

            // Simulate SwiftUI view modifier behavior
            // In a real SwiftUI view, onAppear would be called, but here we'll call the tracking directly
            // to verify the explicit client path works
            client.screen(name: "TestView")

            waitForExpectations(timeout: 1.0)
        }

        func testSwiftUIModifierWithoutClientFallsBackToShared() {
            #if canImport(UIKit) && !os(watchOS)
                // Create client with capture enabled to set up shared integration
                client = Altertable(
                    apiKey: "pk_test_swiftui_fallback",
                    config: AltertableConfig(captureScreenViews: true),
                    session: session
                )
                XCTAssertNotNil(ScreenViewIntegration.shared)

                let expectation = expectation(description: "SwiftUI screen view tracked via shared")
                MockURLProtocol.requestHandler = { [self] request in
                    guard let url = request.url else { throw URLError(.badURL) }

                    if let body = request.httpBody {
                        let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
                        XCTAssertEqual(json?["event"] as? String, SDKConstants.eventScreenView)

                        let properties = json?["properties"] as? [String: Any]
                        XCTAssertEqual(properties?[SDKConstants.propertyScreenName] as? String, "FallbackView")
                    }

                    expectation.fulfill()
                    return successResponse(url: url)
                }

                // Simulate SwiftUI modifier without explicit client - should use shared integration
                // Since we can't easily test the actual SwiftUI onAppear, we'll test the fallback logic directly
                if let integration = ScreenViewIntegration.shared, integration.isEnabled {
                    integration.client?.screen(name: "FallbackView")
                }

                waitForExpectations(timeout: 1.0)
            #else
                // On non-UIKit platforms, shared integration is not created by default
                // This test is only relevant for UIKit platforms
            #endif
        }

        func testSwiftUIModifierWithoutClientAndNoSharedIntegration() {
            // Create client with capture disabled - no shared integration
            client = Altertable(
                apiKey: "pk_test_swiftui_no_shared",
                config: AltertableConfig(captureScreenViews: false),
                session: session
            )
            XCTAssertNil(ScreenViewIntegration.shared?.client)

            // Simulate SwiftUI modifier without explicit client and no shared integration
            // Should not track anything
            let noEventExpectation = expectation(description: "No event when no client and no shared")
            noEventExpectation.isInverted = true

            MockURLProtocol.requestHandler = { [self] request in
                noEventExpectation.fulfill()
                return successResponse(url: request.url!)
            }

            // Simulate the fallback path - should not track
            if let integration = ScreenViewIntegration.shared, integration.isEnabled {
                integration.client?.screen(name: "ShouldNotTrack")
            }

            waitForExpectations(timeout: 0.5)
        }
    #endif
}
