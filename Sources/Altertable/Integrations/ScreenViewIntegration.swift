//
//  ScreenViewIntegration.swift
//  Altertable
//

import Foundation
#if canImport(UIKit) && !os(watchOS)
    import UIKit
#endif
#if canImport(SwiftUI)
    import SwiftUI
#endif

final class ScreenViewIntegration {
    private static let sharedLock = NSLock()
    private static var _shared: ScreenViewIntegration?
    private static var _waitingCallbacks: [(clientId: ObjectIdentifier, callback: () -> Void)] = []

    static var shared: ScreenViewIntegration? {
        sharedLock.lock(); defer { sharedLock.unlock() }
        return _shared
    }

    #if canImport(UIKit) && !os(watchOS)
        private static var isSwizzleInstalled = false
        private static let swizzleLock = NSLock()
    #endif

    weak var client: Altertable?
    var isEnabled: Bool = true
    private let logger: Logger

    init(logger: Logger = Logger()) {
        self.logger = logger
    }

    /// Atomically claims ownership of the shared screen view integration.
    /// Returns true if ownership was successfully claimed, false if another client already owns it.
    /// - Parameters:
    ///   - client: The Altertable client claiming ownership
    ///   - logger: Logger instance for warnings
    ///   - onFailure: Optional callback to register if ownership cannot be claimed immediately.
    ///                The callback will be invoked when ownership becomes available.
    /// - Returns: true if ownership was claimed, false otherwise
    static func claimOwnership(client: Altertable, logger: Logger, onFailure: (() -> Void)? = nil) -> Bool {
        sharedLock.lock()
        defer { sharedLock.unlock() }

        // If shared exists and has a valid client, someone else owns it
        if let existing = _shared, existing.client != nil {
            // Register callback for when ownership becomes available
            if let callback = onFailure {
                _waitingCallbacks.append((clientId: ObjectIdentifier(client), callback: callback))
            }
            return false
        }

        // If shared exists but client is nil (orphaned), we can take over
        // Otherwise create a new integration
        let integration: ScreenViewIntegration
        if let existing = _shared {
            integration = existing
        } else {
            integration = ScreenViewIntegration(logger: logger)
            _shared = integration
        }

        integration.client = client
        integration.isEnabled = true
        return true
    }

    /// Releases ownership if this client is the current owner.
    /// - Parameter client: The Altertable client releasing ownership
    static func releaseOwnership(ifOwner client: Altertable) {
        sharedLock.lock()
        defer { sharedLock.unlock() }

        guard let shared = _shared, shared.client === client else {
            return
        }

        // Clear the client reference but keep the integration instance
        // in case it's needed for SwiftUI fallback (though it won't track)
        shared.client = nil
        shared.isEnabled = false

        // Notify the next waiting client that ownership is available
        while !_waitingCallbacks.isEmpty {
            let entry = _waitingCallbacks.removeFirst()
            // Release lock temporarily to call callback (which may acquire other locks)
            sharedLock.unlock()
            entry.callback()
            sharedLock.lock()
            // If callback succeeded in claiming ownership, stop
            if let shared = _shared, shared.client != nil {
                break
            }
        }
    }

    /// Removes a callback from the waiting queue if the client never held ownership.
    /// Called when a client is deallocated without ever claiming ownership.
    /// - Parameter client: The Altertable client that is being deallocated
    static func dequeueCallback(ifOwner client: Altertable) {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        let clientId = ObjectIdentifier(client)
        _waitingCallbacks.removeAll { $0.clientId == clientId }
    }

    /// Atomically returns the client if the integration is enabled, nil otherwise.
    /// Thread-safe access to client and isEnabled state.
    static func clientIfEnabled() -> Altertable? {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        guard let shared = _shared, shared.isEnabled else { return nil }
        return shared.client
    }

    /// Re-enables the integration if the caller is the current owner.
    /// - Parameter client: The Altertable client attempting to re-enable
    static func reEnable(ifOwner client: Altertable) {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        guard let shared = _shared, shared.client === client else { return }
        shared.isEnabled = true
    }

    #if DEBUG
        /// Test helper to reset shared integration state. Only available in debug builds.
        static func resetForTesting() {
            sharedLock.lock()
            defer { sharedLock.unlock() }
            _shared = nil
            _waitingCallbacks.removeAll()
        }
    #endif

    #if canImport(UIKit) && !os(watchOS)
        private var isInstalled = false
        private let installLock = NSLock()
    #endif

    func installIfNeeded() {
        #if canImport(UIKit) && !os(watchOS)
            installLock.lock()
            defer { installLock.unlock() }

            guard !isInstalled else { return }

            // Check if swizzling was already installed by another instance
            ScreenViewIntegration.swizzleLock.lock()
            defer { ScreenViewIntegration.swizzleLock.unlock() }

            if ScreenViewIntegration.isSwizzleInstalled {
                logger.warn(
                    "Screen view integration already installed to another Altertable instance. " +
                        "Auto-capture may send events to the wrong client."
                )
            } else {
                swizzleViewDidAppear()
                ScreenViewIntegration.isSwizzleInstalled = true
            }

            isInstalled = true
        #endif
    }

    #if canImport(UIKit) && !os(watchOS)
        private func swizzleViewDidAppear() {
            let originalSelector = #selector(UIViewController.viewDidAppear(_:))
            let swizzledSelector = #selector(UIViewController.atbl_viewDidAppear(_:))

            guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
                  let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector)
            else {
                return
            }

            let didAddMethod = class_addMethod(
                UIViewController.self,
                originalSelector,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod)
            )

            if didAddMethod {
                class_replaceMethod(
                    UIViewController.self,
                    swizzledSelector,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod)
                )
            } else {
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }
    #endif
}

#if canImport(UIKit) && !os(watchOS)
    extension UIViewController {
        @objc private func atbl_viewDidAppear(_ animated: Bool) {
            // Call original implementation
            atbl_viewDidAppear(animated)

            // Skip container view controllers
            guard !shouldSkipScreenTracking() else { return }

            // Check if integration is enabled and get client atomically
            guard let client = ScreenViewIntegration.clientIfEnabled() else { return }

            let screenName = extractScreenName()
            client.screen(name: screenName)
        }

        private func shouldSkipScreenTracking() -> Bool {
            // Skip container view controllers and SwiftUI hosting controllers
            let className = String(describing: type(of: self))
            return self is UINavigationController ||
                self is UITabBarController ||
                self is UIPageViewController ||
                className.contains("UIHostingController")
        }

        private func extractScreenName() -> String {
            var name = String(describing: type(of: self))

            // Only strip "ViewController" suffix, matching standard Apple behavior
            if name.hasSuffix("ViewController") {
                name = String(name.dropLast("ViewController".count))
            }

            // Return original if stripping resulted in empty string
            return name.isEmpty ? String(describing: type(of: self)) : name
        }
    }
#endif

#if canImport(SwiftUI)
    private struct AltertableEnvironmentKey: EnvironmentKey {
        static let defaultValue: Altertable? = nil
    }

    public extension EnvironmentValues {
        /// The Altertable client injected into the SwiftUI environment.
        ///
        /// Set this in your app entry point so all child views can track events
        /// without passing the client explicitly.
        ///
        /// ```swift
        /// @main
        /// struct MyApp: App {
        ///     let analytics = Altertable(apiKey: "your-api-key")
        ///     var body: some Scene {
        ///         WindowGroup {
        ///             ContentView()
        ///                 .environment(\.altertable, analytics)
        ///         }
        ///     }
        /// }
        /// ```
        var altertable: Altertable? {
            get { self[AltertableEnvironmentKey.self] }
            set { self[AltertableEnvironmentKey.self] = newValue }
        }
    }

    /// A view modifier that tracks screen views when a SwiftUI view appears.
    ///
    /// Client resolution order:
    /// 1. Explicit `client` parameter (if provided)
    /// 2. `\.altertable` environment value
    /// 3. Shared integration instance fallback
    public struct ScreenViewModifier: ViewModifier {
        let screenName: String
        let client: Altertable?

        @Environment(\.altertable) private var environmentClient

        public init(name: String, client: Altertable? = nil) {
            screenName = name
            self.client = client
        }

        public func body(content: Content) -> some View {
            content.onAppear {
                let resolved = client
                    ?? environmentClient
                    ?? ScreenViewIntegration.clientIfEnabled()
                resolved?.screen(name: screenName)
            }
        }
    }

    public extension View {
        /// Tracks a screen view when this view appears.
        ///
        /// The client is resolved in this order: explicit `client` parameter →
        /// `\.altertable` environment value → shared integration instance.
        ///
        /// - Parameters:
        ///   - name: The screen name to track.
        ///   - client: Optional Altertable client. Prefer injecting via
        ///     `.environment(\.altertable, client)` at the app level instead.
        ///
        /// - Example:
        /// ```swift
        /// // App entry point
        /// ContentView()
        ///     .environment(\.altertable, analytics)
        ///
        /// // Any child view — no client parameter needed
        /// Text("Hello")
        ///     .screenView(name: "Home")
        /// ```
        func screenView(name: String, client: Altertable? = nil) -> some View {
            modifier(ScreenViewModifier(name: name, client: client))
        }
    }
#endif
