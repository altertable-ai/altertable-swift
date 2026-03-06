import SwiftUI
import Altertable

@main
struct ExampleSignupApp: App {
    init() {
        Altertable.initSDK(
            apiKey: "your_api_key", // Replace with your actual key
            config: AltertableConfig(
                baseUrl: "https://api.altertable.ai",
                environment: "production",
                debug: true
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            SignupFunnelView()
        }
    }
}
