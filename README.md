# Altertable Swift SDK

The official Swift SDK for Altertable Product Analytics.

## Installation

Add `altertable-swift` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/altertable-ai/altertable-swift.git", from: "0.1.0")
]
```

## Quick Start

```swift
import Altertable

// Initialize
let client = Altertable(apiKey: "your-api-key")

// Track an event
client.track(event: "Button Clicked", properties: ["button_id": "signup"])
```

## Examples

Check out the [Examples](./Examples) directory for a complete runnable mini-app.

#### Signup Funnel (SwiftUI)
A complete 4-step signup funnel matching our web example journey:
1. **Personal Info**: Screen view tracked via `.screenView(name: "Personal Info")`
2. **Account Setup**: Screen view tracked via `.screenView(name: "Account Setup")`
3. **Choose Plan**: Screen view tracked via `.screenView(name: "Plan Selection")` and `track("Plan Selected")`
4. **Completion**: Screen view tracked via `.screenView(name: "Welcome")`, `identify(userId, traits)`, and `track("Form Submitted")`

## API Reference

### `track(event:properties:)`

Records an event with optional properties.

```swift
client.track(event: "Purchase", properties: ["amount": 29.99])
```

### `identify(userId:traits:)`

Identifies a user with a unique ID and optional traits.

```swift
client.identify(userId: "user_123", traits: ["plan": "pro"])
```

### `alias(newUserId:)`

Links a new ID to the current user (e.g. after sign up).

```swift
client.alias(newUserId: "user_456")
```

### `updateTraits(_ traits:)`

Updates traits for the currently identified user.

```swift
client.updateTraits(["email": "new@example.com"])
```

### `reset()`

Clears the current session and identity (e.g. on logout).

```swift
client.reset()
```

### `flush()`

Forces any queued events to be sent immediately.

```swift
client.flush()
```

### `configure(_:)`

Updates the configuration after initialization. Use a closure to modify configuration properties in place.

```swift
client.configure { config in
    config.trackingConsent = .granted
    config.environment = "staging"
    config.debug = true
}
```

**Note**: `requestTimeout` and `flushOnBackground` are init-only properties. Changes to these via `configure()` are ignored.

### `screen(name:properties:)`

Tracks a screen view with optional properties.

```swift
client.screen(name: "HomeScreen", properties: ["section": "main"])
```

## Screen Views

The SDK provides multiple ways to track screen views, with platform-specific capabilities:

- **`screen(name:properties:)`**: Works on all platforms that run Swift
- **UIKit auto-capture**: Available on UIKit platforms (iOS, tvOS) when `captureScreenViews` is enabled
- **SwiftUI `.screenView()` modifier**: Available on platforms that support SwiftUI

### Cross-Platform Manual Tracking

The `screen()` method works on all platforms:

```swift
client.screen(name: "HomeScreen", properties: ["section": "main"])
```

### UIKit Auto-Capture (iOS, tvOS only)

On UIKit platforms, screen views can be automatically tracked when view controllers appear. The SDK extracts screen names by removing the `ViewController` suffix from the class name (e.g., `HomeViewController` → `Home`).

```swift
// Automatically tracks "Home" when HomeViewController appears
class HomeViewController: UIViewController { }
```

Auto-capture is enabled by default. To disable:

```swift
let config = AltertableConfig(captureScreenViews: false)
let client = Altertable(apiKey: "your-api-key", config: config)
```

**Note**: Auto-capture is only available on UIKit platforms. On other platforms (macOS, Linux, watchOS), `captureScreenViews` has no effect and you should use manual tracking.

### SwiftUI (Platforms with SwiftUI support)

Inject the client once at the app level, then use `.screenView()` anywhere in the view hierarchy with no extra wiring:

```swift
import SwiftUI
import Altertable

@main
struct MyApp: App {
    let analytics = Altertable(apiKey: "your-api-key")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.altertable, analytics)
        }
    }
}

struct HomeView: View {
    var body: some View {
        Text("Welcome")
            .screenView(name: "Home")
    }
}
```

The client is resolved in order: explicit `client` parameter → `\.altertable` environment value → shared integration fallback. For most apps, the environment approach covers everything.

## Configuration

Initialize with an `AltertableConfig` object for advanced options.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `apiKey` | `String` | (Required) | Your project API key. |
| `baseURL` | `URL` | `https://api.altertable.ai` | The API endpoint URL. |
| `environment` | `String` | `production` | Environment name (e.g. `staging`). |
| `trackingConsent` | `TrackingConsentState` | `.granted` | Controls if tracking is enabled. |
| `debug` | `Bool` | `false` | Enables verbose logging. |
| `requestTimeout` | `TimeInterval` | `10.0` | Network request timeout in seconds. |
| `flushOnBackground` | `Bool` | `true` | Automatically flush events when app backgrounds. |
| `captureScreenViews` | `Bool` | `true` | Automatically track screen views on UIKit platforms (iOS, tvOS). On other platforms, use `screen()` or `.screenView()` for manual tracking. |

## License

[MIT](LICENSE)
