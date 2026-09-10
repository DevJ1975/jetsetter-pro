# JetSetter Pro — Setup

JetSetter Pro has **no backend**. Everything runs on the device or on Apple's frameworks. This page covers the few one-time steps that need Xcode or the developer portal.

## 1. Capabilities on the App ID

In the developer portal (Identifiers → App IDs → JetSetter Pro) enable:

- **WeatherKit** — required for `com.apple.developer.weatherkit` in `JetSetter Pro/JetSetter Pro.entitlements`. Without it the app silently uses Open-Meteo.
- **App Groups** (`group.DevJ.JetSetter-Pro`) — on both the app ID and the widget ID `DevJ.JetSetter-Pro.Widgets`.
- **Time Sensitive Notifications**, **Background Modes** (fetch, processing), **In-App Purchase**.

Then in Xcode → Signing & Capabilities, add the same capabilities to the app target so the provisioning profile includes them.

## 2. Optional: FlightAware

Live flight status and disruption polling use FlightAware AeroAPI. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`, set `API_FLIGHTAWARE`, then in Xcode: File → Add Files (uncheck copy, no target) → Project → Info → Configurations → set both Debug and Release to **Secrets**. The value reaches the app through `JetSetter-Pro-Info.plist` (`$(API_FLIGHTAWARE)`), not through `INFOPLIST_KEY_*` settings — Xcode silently drops custom ones. Without a key the Flight Tracker and Disruption screens show a clear "add a key" state.

## 3. Widget Extension and tests

Both targets exist in the project: `JetSetter Pro Widgets` (Live Activity + Next Trip widget, embedded in the app) and `JetSetter ProTests` (Swift Testing). The shared `JetSetter Pro` scheme builds all three and `xcodebuild … test` runs the suite; CI does the same on every PR. `Shared/FlightActivityAttributes.swift` is the one file compiled into both the app and the widget.

## 4. StoreKit

`Config/Products.storekit` defines Pro Monthly and Pro Annual and is already attached to the shared scheme's Run action, so the paywall works in the simulator. The bundle ID is `DevJ.JetSetter-Pro` (decided 2026-09-09), so create the products in App Store Connect as `DevJ.JetSetter-Pro.subscription.pro.monthly` and `DevJ.JetSetter-Pro.subscription.pro.annual`. TestFlight builds unlock Pro automatically for testers (`SubscriptionManager.isBetaBuild`).

## 5. Siri

App Shortcuts are declared in `Core/Intents/AppIntents.swift` and appear automatically after install. Try "What's my next flight in JetSetter Pro" or open the Siri tab for the full list. Intents that open a screen route through `AppRouter`.

## 6. Verify

1. Build Debug and Release (see `docs/HANDOFF.md`).
2. Run on a device with Apple Intelligence for packing lists, place ranking and receipt reading; the simulator shows the fallbacks.
3. Add a trip with a flight → the notification permission prompt appears then (not at launch).
