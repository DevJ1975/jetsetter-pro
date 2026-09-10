# Beta Builds — JetSetter Pro

Tracking log for TestFlight beta builds. Marketing version is `MARKETING_VERSION`;
build number is `CURRENT_PROJECT_VERSION` (both live in the target's build settings).
Bump the **build number** for every upload; bump the **marketing version** for a new
public-facing release.

| Build | Version | Date       | Status              | Notes |
|-------|---------|------------|---------------------|-------|
| 4     | 1.0     | 2026-09-10 | Pending upload      | Beta build configuration; opt-in Demo Mode (LAS→ATL on DL1423, bags loading at LAS, live ATL weather); on-device booking capture from pasted text and screenshots. |
| 3     | 1.0     | 2026-09-09 | Superseded          | No-backend + Apple-first rewrite: Siri App Intents replace IRIS; WeatherKit; on-device packing, receipts, place ranking; MapKit rental cars/hotels; honest check-in and board. |
| 2     | 1.0     | 2026-07-05 | Superseded          | `@Observable` migration (25 classes) + Duration-based `Task.sleep` sweep; Translator camera cancel-button fix; app icon / styling work. |
| 1     | 1.0     | —          | Initial project version | Baseline (never uploaded). |

## How to cut a build

0. Pick the configuration. **Archive from `Beta`** for TestFlight and investor builds: it is Release plus the `DEMO_ENABLED` flag, so Settings gets the Demo Mode toggle. Archive from `Release` for App Store submission, which compiles the demo seeder out entirely. Set this in the scheme's Archive step, or duplicate the scheme.
1. In Xcode: **JetSetter Pro** target → **General** → set **Build** (this writes `CURRENT_PROJECT_VERSION`). Each TestFlight upload needs a build number higher than the last one for the same version.
2. **Product → Archive**, then distribute via the Organizer to **App Store Connect / TestFlight**.
3. Add a row above with the new build number, date, and what changed.
