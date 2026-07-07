# Beta Builds — JetSetter Pro

Tracking log for TestFlight beta builds. Marketing version is `MARKETING_VERSION`;
build number is `CURRENT_PROJECT_VERSION` (both live in the target's build settings).
Bump the **build number** for every upload; bump the **marketing version** for a new
public-facing release.

| Build | Version | Date       | Status              | Notes |
|-------|---------|------------|---------------------|-------|
| 2     | 1.0     | 2026-07-05 | Pending upload      | `@Observable` migration (25 classes) + Duration-based `Task.sleep` sweep; Translator camera cancel-button fix; app icon / styling work. |
| 1     | 1.0     | —          | Initial project version | Baseline (never uploaded). |

## How to cut a build

1. In Xcode: **JetSetter Pro** target → **General** → set **Build** (this writes `CURRENT_PROJECT_VERSION`). Each TestFlight upload needs a build number higher than the last one for the same version.
2. **Product → Archive**, then distribute via the Organizer to **App Store Connect / TestFlight**.
3. Add a row above with the new build number, date, and what changed.
