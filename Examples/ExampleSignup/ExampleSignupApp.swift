#if canImport(SwiftUI)
    import Altertable
    import SwiftUI

    /// API key must be provided via the ALTERTABLE_API_KEY environment variable,
    /// e.g. `ALTERTABLE_API_KEY=pk_... swift run ExampleSignup`
    private func getRequiredAPIKey() -> String {
        guard let key = ProcessInfo.processInfo.environment["ALTERTABLE_API_KEY"], !key.isEmpty else {
            fatalError("ALTERTABLE_API_KEY environment variable is required. Set it before running the app.")
        }
        return key
    }

    @main
    struct ExampleSignupApp: App {
        @StateObject private var analytics = Altertable(
            apiKey: getRequiredAPIKey(),
            config: AltertableConfig(
                environment: "production",
                debug: true
            )
        )

        init() {
            #if os(macOS)
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            #endif
        }

        var body: some Scene {
            WindowGroup {
                SignupFunnelView()
                    .environmentObject(analytics)
            }
        }
    }
#else
    import Foundation

    /// Stub main for platforms without SwiftUI (e.g., Linux)
    @main
    enum ExampleSignupApp {
        static func main() {
            print("ExampleSignup requires SwiftUI, which is not available on this platform.")
            exit(1)
        }
    }
#endif
