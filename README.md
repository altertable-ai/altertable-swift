# Altertable Swift SDK

The official Swift SDK for Altertable Product Analytics.

## Installation

Add `altertable-swift` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/altertable-ai/altertable-swift.git", from: "0.1.0")
]
```

## Usage

```swift
import Altertable

// Initialize the SDK
let client = Altertable.init(apiKey: "your-api-key")

// Track an event
client.track(event: "Button Clicked", properties: ["button_id": "signup"])
```

## License

MIT
