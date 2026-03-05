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

## Configuration

Initialize with an `AltertableConfig` object for advanced options.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `apiKey` | `String` | (Required) | Your project API key. |
| `baseURL` | `String` | `https://api.altertable.com` | The API endpoint URL. |
| `environment` | `String` | `production` | Environment name (e.g. `staging`). |
| `trackingConsent` | `TrackingConsentState` | `.granted` | Controls if tracking is enabled. |
| `debug` | `Bool` | `false` | Enables verbose logging. |
| `requestTimeout` | `TimeInterval` | `30.0` | Network request timeout in seconds. |
| `flushOnBackground` | `Bool` | `true` | Automatically flush events when app backgrounds. |

## License

[MIT](LICENSE)
