# JetSetter Pro — Android

**Your executive travel companion, rebuilt natively for Android.** A from-scratch Kotlin + Jetpack Compose port of the mature JetSetter Pro iOS app.

![status](https://img.shields.io/badge/status-early%20scaffold-orange)
![platform](https://img.shields.io/badge/platform-Android%208.0%2B%20(API%2026%2B)-3B9EF0)
![language](https://img.shields.io/badge/Kotlin-Compose%20%C2%B7%20Material%203-7F52FF)
![di](https://img.shields.io/badge/Hilt%20%C2%B7%20Room%20%C2%B7%20Retrofit-blue)

> ⚠️ **Early scaffold.** This is a runnable foundation, not a finished app: a themed **Home** + **Itinerary** are wired end-to-end (Compose · ViewModel/StateFlow · Repository · Room), and the other screens are stubbed. Continuing the port means filling in the remaining ~30 feature modules — see [`AGENT_GUIDE.md`](AGENT_GUIDE.md) and [`docs/FEATURE_PARITY.md`](docs/FEATURE_PARITY.md).

---

## 🎨 About the graphics (please read)

**The iOS app shipped with zero image assets.** Its `AppIcon` set is empty and every visual is an **SF Symbol** or **drawn in code** with SwiftUI shapes/gradients. There was nothing to copy.

So all Android artwork is a **brand-faithful regeneration**, not an import:
- The launcher icon is a generated **adaptive icon** built from the brand palette (deep navy `#0A2040` + sky-blue accent `#3B9EF0`).
- Tab/inline icons map SF Symbols → **Material Symbols** (`androidx.compose.material.icons`); see [`docs/SF_SYMBOL_MAP.md`](docs/SF_SYMBOL_MAP.md).
- Cards, chips, and gradients are reproduced with Compose `Brush`/`drawBehind` to match the iOS theme; see [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md).

---

## ✨ Feature snapshot

Five-tab bottom navigation, mirroring the iOS app:

| Tab | What it does | Status |
|---|---|---|
| 🏠 **Home** | Trip dashboard / at-a-glance travel status | ✅ Wired (themed, live ViewModel) |
| 🗓️ **Itinerary** | Trips, itinerary items, packing list | ✅ Wired (Room-backed, full MVVM reference) |
| ✨ **IRIS** | AI travel assistant (*Intelligent Routing & Itinerary Specialist*) | 🟡 Stubbed — Claude wiring next |
| 📊 **Expenses** | Trip expense tracking & export | 🟡 Stubbed |
| ⋯ **More** | Entry point to the remaining ~30 features | 🟡 Stubbed |

**IRIS uses the Anthropic Claude API** (`https://api.anthropic.com/v1/messages`). With no API key, it (and the whole app) runs on bundled mock data — see [`AGENT_GUIDE.md` §8](AGENT_GUIDE.md#8-the-iris-assistant-claude-api).

---

## 🧱 Tech stack

- **Language / UI:** Kotlin · Jetpack Compose · Material 3
- **Architecture:** MVVM + Repository (single source of truth)
- **DI:** Hilt
- **Local data:** Room (SQLite) · DataStore (preferences)
- **Networking:** Retrofit + OkHttp + Moshi (snake_case + ISO-8601, retry/backoff)
- **Async:** Coroutines · Flow / StateFlow
- **Background:** WorkManager (disruption polling)
- **Security:** androidx.security-crypto / Google Tink (vault encryption) · androidx.biometric
- **Misc:** androidx.core:core-splashscreen · Coil · Navigation Compose
- **Build:** Gradle (Kotlin DSL) + version catalog (`gradle/libs.versions.toml`)
- **SDK targets:** `minSdk 26` · `targetSdk 35` · `compileSdk 35` · `applicationId = com.jetsetter.pro`

---

## 🚀 Quickstart (Android Studio)

1. **Get Android Studio Ladybug** (or newer). Earlier versions predate the Compose/AGP features used here.
2. **Clone** the repo and **open the `android/` folder** in Android Studio — *not* the parent iOS repo. (When this becomes `DevJ1975/JetSetter_Android`, just open the repo root.)
   ```bash
   git clone <repo-url>
   # File → Open… → select .../jetsetter-pro/android
   ```
3. **Use JDK 17.** Settings → Build, Execution, Deployment → Build Tools → Gradle → **Gradle JDK = 17** (Studio's bundled JBR works).
4. **Install SDK 35.** Tools → SDK Manager → SDK Platforms → check **Android 15 (API 35)**; under SDK Tools, ensure Build-Tools, Platform-Tools, and the Emulator are installed.
5. **Add your API keys.** Copy the template and fill in values:
   ```bash
   cp local.properties.example local.properties
   # then set, at minimum:
   #   API_ANTHROPIC=sk-ant-...        (for the IRIS assistant)
   #   sdk.dir is written by Studio automatically
   ```
   > No keys? That's fine — the app builds and runs on **mock data** out of the box. Keys unlock live APIs. `local.properties` is git-ignored; never commit it. Full key list: [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md).
6. **Let Gradle sync** (first sync downloads dependencies — give it a few minutes).
7. **Create an emulator** (Tools → Device Manager → an API-35 Pixel) or plug in a device, then **Run ▶**.

### Build from the CLI

From the `android/` directory:

```bash
./gradlew assembleDebug     # build the debug APK
./gradlew installDebug      # build + install to a connected device/emulator
./gradlew lint              # Android Lint
./gradlew test              # JVM unit tests
```

> **Headless agents:** there is no Android SDK in sandboxed environments, so local builds won't run there. **CI is the authoritative build check** — push your branch and let [`.github/workflows/android-ci.yml`](.github/workflows/android-ci.yml) compile it. Details in [`AGENT_GUIDE.md` §9](AGENT_GUIDE.md#9-build-run--ci).

---

## 🗂️ Project layout (at a glance)

```
android/
├── README.md · AGENT_GUIDE.md
├── docs/                         # DESIGN_SYSTEM · SF_SYMBOL_MAP · FEATURE_PARITY · API_REFERENCE
├── push-to-jetsetter-android.sh  # handoff: pushes this folder to DevJ1975/JetSetter_Android
├── .github/workflows/android-ci.yml
├── gradle/libs.versions.toml     # version catalog — all deps live here
├── settings.gradle.kts · build.gradle.kts · gradle.properties · gradlew
├── local.properties.example      # API-key template → copy to local.properties (git-ignored)
└── app/
    ├── build.gradle.kts          # android{}, dependencies, BuildConfig fields
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/com/jetsetter/pro/
        │   ├── ui/{theme, components, navigation}
        │   ├── feature/{home, itinerary, iris, expenses, more}
        │   └── core/{data/{local, remote, repository, prefs}, di, model, secrets, util}
        └── res/                  # values/, mipmap-*/ (adaptive icon), xml/
```

The package root is `com.jetsetter.pro`; the layout above is fixed — new code goes in the matching package. Architecture details, the MVVM+Repository flow, and "where does X go?" are covered in [`AGENT_GUIDE.md`](AGENT_GUIDE.md).

---

## 📚 Documentation

| Doc | What's inside |
|---|---|
| **[`AGENT_GUIDE.md`](AGENT_GUIDE.md)** | The comprehensive build/onboarding guide: project layout, Swift→Kotlin mapping, Compose & state, APIs/secrets, IRIS/Claude, CI, and how to continue the port. **Start here.** |
| [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) | Color/typography/spacing tokens (`JetsetterTheme`), `JetCard`, `GoldTag`. |
| [`docs/SF_SYMBOL_MAP.md`](docs/SF_SYMBOL_MAP.md) | SF Symbol → Material Symbols / `Icons.*` replacement table. |
| [`docs/FEATURE_PARITY.md`](docs/FEATURE_PARITY.md) | All 34 iOS modules with port status (wired / stubbed / not started). |
| [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md) | Every API key, base URL, endpoint, and the mock-fallback behavior. |

---

## 🔁 Handoff to `DevJ1975/JetSetter_Android`

This `android/` folder currently lives inside the iOS repo. It will be promoted to the **root** of its own GitHub repo, `DevJ1975/JetSetter_Android`, via [`push-to-jetsetter-android.sh`](push-to-jetsetter-android.sh) (review it before the first run — it pushes to a real remote). After promotion, that repo is the source of truth for Android. See [`AGENT_GUIDE.md` §11](AGENT_GUIDE.md#11-git-workflow).

---

*JetSetter Pro for Android — © Trainovate Technologies LLC. All rights reserved.*
