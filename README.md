# Altertable Swift SDK

You can use this SDK to send Product Analytics events to Altertable from Swift applications.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/altertable-ai/altertable-swift.git", from: "0.1.0")
]
```

## Quick start

```swift
import Altertable

let client = Altertable(apiKey: "your-api-key")
client.track(event: "Button Clicked", properties: ["button_id": "signup"])
```

## API reference

### `track(event:properties:)`

Sends an event with optional properties.

```swift
client.track(event: "Purchase", properties: ["amount": 29.99])
```

### `identify(userId:traits:)`

Associates a user identifier and traits.

```swift
client.identify(userId: "user_123", traits: ["plan": "pro"])
```

### `alias(newUserId:)`

Merges identity from the current user into `newUserId`.

```swift
client.alias(newUserId: "user_456")
```

### `updateTraits(_:)`

Updates traits for the current identified user.

```swift
client.updateTraits(["email": "new@example.com"])
```

### `reset()`

Clears identity and session state.

```swift
client.reset()
```

### `flush()`

Forces queued events to be sent immediately.

```swift
client.flush()
```

### `configure(_:)`

Updates mutable runtime configuration.

```swift
client.configure { config in
    config.environment = "staging"
    config.debug = true
}
```

### `screen(name:properties:)`

Tracks a screen view with optional properties.

```swift
client.screen(name: "HomeScreen", properties: ["section": "main"])
```

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `apiKey` | `String` | (required) | Project API key. |
| `baseURL` | `URL` | `https://api.altertable.ai` | API endpoint URL. |
| `environment` | `String` | `"production"` | Environment name tag. |
| `trackingConsent` | `TrackingConsentState` | `.granted` | Tracking consent mode. |
| `debug` | `Bool` | `false` | Enables verbose logging. |
| `requestTimeout` | `TimeInterval` | `10.0` | Request timeout in seconds. |
| `flushOnBackground` | `Bool` | `true` | Flushes events when app backgrounds. |
| `captureScreenViews` | `Bool` | `true` | Auto-captures UIKit screen views when supported. |

## Development

Prerequisites: Swift 5.9+ and Xcode or Swift CLI.

```bash
swift package resolve
swift test
swiftlint
```

## License

See [LICENSE](LICENSE).