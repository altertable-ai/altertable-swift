# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1](https://github.com/altertable-ai/altertable-swift/compare/altertable-swift-v0.1.0...altertable-swift-v0.1.1) (2026-03-17)


### Bug Fixes

* send prefixed built-in properties ([#28](https://github.com/altertable-ai/altertable-swift/issues/28)) ([2a5761a](https://github.com/altertable-ai/altertable-swift/commit/2a5761a6cd0f9c03db9759519a97e31575151333))

## [0.1.0](https://github.com/altertable-ai/altertable-swift/releases/tag/v0.1.0) (2026-03-10)

Initial release of the official Swift SDK for Altertable Product Analytics! 🚀

### Added

* **Core Analytics**: Complete SDK implementation supporting `track()`, `identify()`, `alias()`, `updateTraits()`, and `screen()` events.
* **SwiftUI Integration**: Seamless `.screenView(name:)` modifier to easily track screens in the view hierarchy via `@Environment`.
* **UIKit Auto-Capture**: Automatically tracks screen views on iOS and tvOS when ViewControllers appear.
* **Storage & Transport**: Robust event queue with background flushing, batching, retry logic, and offline support.
* **Tracking Consent**: Built-in management for tracking consent states.
* **Full Configuration**: Setup your project with customizable options for environments, debug logging, and queue limits.
