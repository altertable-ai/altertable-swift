# ExampleSignup

A multi-step signup funnel demonstrating how to integrate Altertable analytics into a SwiftUI macOS app.

## What it demonstrates

- Initializing `Altertable` as a SwiftUI `@StateObject` and injecting it via `.environmentObject`
- Tracking funnel progression with `track(event:properties:)`
- Identifying a user on form submission with `identify(userId:traits:)`
- Tracking user interactions (plan selection, terms agreement) with event properties

## Running the example

1. Set your Altertable API key as an environment variable:
   ```bash
   ALTERTABLE_API_KEY=pk_... swift run ExampleSignup
   ```
2. Or in Xcode: open the workspace, edit the **ExampleSignup** scheme, add `ALTERTABLE_API_KEY` under **Run → Arguments → Environment Variables**, then run (`⌘R`).

## Analytics events

| Event | Trigger | Properties |
| :--- | :--- | :--- |
| `Step Viewed` | Every step navigation | `step: Int` |
| `Personal Info Completed` | Step 1 → Continue | `step: 1` |
| `Account Setup Completed` | Step 2 → Continue | `step: 2` |
| `Plan Selected` | Tapping a plan card | `plan: String` |
| `Terms Agreement Changed` | Toggling the terms checkbox | `agreed: Bool`, `step: 3` |
| `Plan Selection Completed` | Step 3 → Complete Signup | `step: 3` |
| `Form Submitted` | On final submission | — |
| `Get Started Clicked` | Welcome screen CTA | — |
| `Form Restarted` | Restart button | — |

## Project structure

```
ExampleSignup/
├── ExampleSignupApp.swift   # App entry point, Altertable initialization
└── SignupFunnelView.swift   # 4-step funnel UI and analytics calls
```
