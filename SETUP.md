# JetSetter Pro — Setup

Almost everything in JetSetter Pro runs on the device or on Apple's frameworks. The one server-side piece is the **booking backend** (`backend/`, Django on Railway) that books flights through Duffel, takes payment through Stripe and lets the app retrieve every booking. This page covers the one-time steps that need Xcode, the developer portal or Railway.

## 1. Capabilities on the App ID

In the developer portal (Identifiers → App IDs → JetSetter Pro) enable:

- **WeatherKit** — required for `com.apple.developer.weatherkit` in `JetSetter Pro/JetSetter Pro.entitlements`. Without it the app silently uses Open-Meteo.
- **App Groups** (`group.DevJ.JetSetter-Pro`) — on both the app ID and the widget ID `DevJ.JetSetter-Pro.Widgets`.
- **Time Sensitive Notifications**, **Background Modes** (fetch, processing), **In-App Purchase**.

Then in Xcode → Signing & Capabilities, add the same capabilities to the app target so the provisioning profile includes them.

## 2. Booking backend (Railway)

Deploy `backend/` following `backend/README.md` (about 10 minutes, works immediately on a Duffel *test* token with no Stripe). Then point the app at it: in `Config/Secrets.xcconfig` set

```
API_BACKEND_URL = https:/$()/your-service.up.railway.app
```

(`https:/$()/` is deliberate: xcconfig treats a bare `//` as a comment.) Without this key the app falls back to opening the airline or Kayak site and saving the confirmation from a screenshot or pasted email. Nothing else breaks.

## 3. Optional: FlightAware

Live flight status and disruption polling use FlightAware AeroAPI. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`, set `API_FLIGHTAWARE`, then in Xcode: File → Add Files (uncheck copy, no target) → Project → Info → Configurations → set both Debug and Release to **Secrets**. The value reaches the app through `JetSetter-Pro-Info.plist` (`$(API_FLIGHTAWARE)`), not through `INFOPLIST_KEY_*` settings — Xcode silently drops custom ones. Without a key the Flight Tracker and Disruption screens show a clear "add a key" state.

## 4. Widget Extension and tests

Both targets exist in the project: `JetSetter Pro Widgets` (Live Activity + Next Trip widget, embedded in the app) and `JetSetter ProTests` (Swift Testing). The shared `JetSetter Pro` scheme builds all three and `xcodebuild … test` runs the suite; CI does the same on every PR. `Shared/FlightActivityAttributes.swift` is the one file compiled into both the app and the widget.

## 5. StoreKit

`Config/Products.storekit` defines Pro Monthly and Pro Annual and is already attached to the shared scheme's Run action, so the paywall works in the simulator. The bundle ID is `DevJ.JetSetter-Pro` (decided 2026-09-09), so create the products in App Store Connect as `DevJ.JetSetter-Pro.subscription.pro.monthly` and `DevJ.JetSetter-Pro.subscription.pro.annual`. TestFlight builds unlock Pro automatically for testers (`SubscriptionManager.isBetaBuild`).

## 6. Siri

App Shortcuts are declared in `Core/Intents/AppIntents.swift` and appear automatically after install. Try "What's my next flight in JetSetter Pro" or open the Siri tab for the full list. Intents that open a screen route through `AppRouter`.

## 7. Verify

1. Build Debug and Release (see `docs/HANDOFF.md`).
2. Run on a device with Apple Intelligence for packing lists, place ranking and receipt reading; the simulator shows the fallbacks.
3. Add a trip with a flight → the notification permission prompt appears then (not at launch).
