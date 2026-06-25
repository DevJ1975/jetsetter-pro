# JetSetter Pro — Android Agent & Build Guide
### Building the Native Android Port in Kotlin, Jetpack Compose & Material 3

> **Who this is for:** You're an AI agent (or a human dev) tasked with continuing the **native Android port** of JetSetter Pro — *your executive travel companion*. You may know iOS/SwiftUI already, or you may be coming straight from web. Either way, this guide maps the mature iOS app (~153 Swift files, 34 feature modules, 5-tab navigation) onto an idiomatic modern-Android stack, and walks you through how to extend the scaffold without breaking it.
>
> **This is a companion to the iOS guide** `../jetsetter-junior-dev-guide.md`. Where that book teaches "JavaScript brain → Swift reality," this one teaches "**Swift/SwiftUI brain → Kotlin/Compose reality**" — plus everything Android-specific (Gradle, Hilt, Room, Android Studio).

---

## Table of Contents

1. [What You're Building](#1-what-youre-building)
2. [How This Project Is Organized](#2-how-this-project-is-organized)
3. [iOS/Swift → Android/Kotlin Concept Mapping](#3-iosswift--androidkotlin-concept-mapping)
4. [Android Studio Survival Guide](#4-android-studio-survival-guide)
5. [Compose Fundamentals](#5-compose-fundamentals)
6. [State Management](#6-state-management)
7. [Working with APIs & Secrets](#7-working-with-apis--secrets)
8. [The IRIS Assistant (Claude API)](#8-the-iris-assistant-claude-api)
9. [Build, Run & CI](#9-build-run--ci)
10. [How to Continue the Port](#10-how-to-continue-the-port)
11. [Git Workflow](#11-git-workflow)
12. [Glossary](#12-glossary)

> **Cross-references:** Deeper detail lives in the `docs/` folder, written separately and kept in sync with this guide:
> - [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) — full color/typography/spacing tokens (`JetsetterTheme`), `JetCard`, `GoldTag`.
> - [`docs/SF_SYMBOL_MAP.md`](docs/SF_SYMBOL_MAP.md) — every SF Symbol → Material Symbols / `Icons.*` replacement (the iOS app is **100% icon-drawn**, see below).
> - [`docs/FEATURE_PARITY.md`](docs/FEATURE_PARITY.md) — the master checklist of all 34 modules: wired / stubbed / not-started.
> - [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md) — every API key, base URL, endpoint, and the mock-fallback behavior.

---

## 1. What You're Building

JetSetter Pro is a mature **iOS app** (SwiftUI + MVVM). This repository is its **native Android twin**: same product, same design language, rebuilt the Android way. It is **not** a webview wrapper, **not** Flutter, **not** Kotlin Multiplatform — it is a from-scratch Jetpack Compose app.

### The 5 tabs

The app's spine is a 5-destination bottom navigation bar, mirroring the iOS `TabView` in `ContentView.swift` one-for-one:

| Tab | iOS screen | Android destination | Status in scaffold |
|---|---|---|---|
| **Home** | `HomeView` | `feature.home.HomeScreen` | ✅ **Wired** — themed dashboard with live ViewModel + `StateFlow` |
| **Itinerary** | `ItineraryView` | `feature.itinerary.ItineraryScreen` | ✅ **Wired** — trip list, Room-backed, end-to-end MVVM example |
| **IRIS** | `IRISChatView` | `feature.iris.IrisScreen` | 🟡 **Stubbed** — chat shell present; Claude wiring is the next milestone (§8) |
| **Expenses** | `ExpenseTrackerView` | `feature.expenses.ExpensesScreen` | 🟡 **Stubbed** — themed placeholder + model |
| **More** | `MoreView` | `feature.more.MoreScreen` | 🟡 **Stubbed** — menu list routing to the remaining ~30 features |

> **IRIS** = *Intelligent Routing & Itinerary Specialist* — the in-app assistant. On iOS she ran on Apple Intelligence (on-device) with a Claude fallback. **On Android we standardize on the Anthropic Claude API.** See §8.

### What's wired vs stubbed (read this before you touch anything)

- **Wired** means: the screen renders with the real `JetsetterTheme`, a `@HiltViewModel` exposes `StateFlow` state, a repository feeds it, and (for Itinerary) data persists in Room. These two screens are your **reference implementations** — copy their shape.
- **Stubbed** means: a Composable exists and is reachable from navigation, themed correctly, but shows placeholder content. Models may exist; the repository/DAO/network layers are TODO.
- **Not started** means: one of the other ~30 features (Flight Tracker, Document Vault, Packing List, Disruption monitoring, Rental Car, etc.) has no Android code yet. Porting them is the job — see §10 and `docs/FEATURE_PARITY.md`.

### A note on graphics (important and easy to get wrong)

The iOS app ships with **zero image assets**. Its `Assets.xcassets/AppIcon` set is **empty**, and *every* visual — the app icon, tab icons, status chips, the IRIS spark, illustrations — is either an **SF Symbol** or **drawn in code** with SwiftUI shapes and gradients.

That means there is nothing to copy. Android icons and graphics are **brand-faithful regenerations**, not asset imports:

- The launcher icon is a generated **adaptive icon** (foreground + background layers), built from the brand palette (deep navy `#0A2040` + sky-blue accent `#3B9EF0`), not exported from iOS.
- Tab/inline icons map SF Symbols → **Material Symbols** (`androidx.compose.material.icons`). The mapping is enumerated in `docs/SF_SYMBOL_MAP.md`.
- Decorative gradients/cards are reproduced with Compose `Brush`/`drawBehind`, matching `JetsetterTheme` (§5, and `docs/DESIGN_SYSTEM.md`).

---

## 2. How This Project Is Organized

### Annotated directory tree

```
android/                                  ← becomes the root of DevJ1975/JetSetter_Android
├── README.md                             ← project overview + Studio quickstart
├── AGENT_GUIDE.md                        ← you are here
├── docs/
│   ├── DESIGN_SYSTEM.md                  ← colors, type, spacing, JetCard/GoldTag
│   ├── SF_SYMBOL_MAP.md                  ← SF Symbol → Material icon table
│   ├── FEATURE_PARITY.md                 ← all 34 modules: wired/stubbed/todo
│   └── API_REFERENCE.md                  ← keys, base URLs, endpoints, mock rules
├── push-to-jetsetter-android.sh          ← handoff: pushes this folder to the real repo (§11)
├── .gitignore                            ← ignores local.properties, *.keystore, build/, .idea/
├── .github/workflows/android-ci.yml      ← CI: assembleDebug + lint on every push/PR (§9)
│
├── gradle/
│   ├── libs.versions.toml                ← THE version catalog — all deps & versions live here
│   └── wrapper/…                          ← pinned Gradle wrapper
├── gradlew, gradlew.bat                   ← wrapper scripts (use ./gradlew, never a global gradle)
├── settings.gradle.kts                    ← module list + dependencyResolutionManagement
├── build.gradle.kts                       ← root build (plugin aliases, no app config here)
├── gradle.properties                      ← JVM args, AndroidX flags, Kotlin opts
├── local.properties.example              ← TEMPLATE for SDK path + API keys (copy → local.properties)
│
└── app/
    ├── build.gradle.kts                   ← app module: android{}, dependencies{}, BuildConfig fields
    └── src/main/
        ├── AndroidManifest.xml            ← permissions, <application>, launcher activity
        ├── java/com/jetsetter/pro/
        │   ├── JetSetterApp.kt            ← @HiltAndroidApp Application (entry point)
        │   ├── MainActivity.kt            ← single ComponentActivity hosting Compose + splash
        │   ├── ui/
        │   │   ├── theme/                 ← Color.kt, Type.kt, Theme.kt (JetsetterTheme), Card.kt
        │   │   ├── components/            ← reusable Composables (JetCard, GoldTag, StatusChip…)
        │   │   └── navigation/            ← JetNavHost, Destinations, JetBottomBar
        │   ├── feature/
        │   │   ├── home/                  ← HomeScreen, HomeViewModel, HomeUiState
        │   │   ├── itinerary/             ← ItineraryScreen, ItineraryViewModel, AddItem…
        │   │   ├── iris/                  ← IrisScreen, IrisViewModel, ChatMessage
        │   │   ├── expenses/              ← ExpensesScreen, ExpenseViewModel, Expense model
        │   │   └── more/                  ← MoreScreen (menu → remaining features)
        │   └── core/
        │       ├── data/
        │       │   ├── local/             ← Room: JetDatabase, DAOs, @Entity classes
        │       │   ├── remote/            ← Retrofit: ApiClient, *Api interfaces, DTOs
        │       │   ├── repository/        ← Repositories that merge local + remote
        │       │   └── prefs/             ← DataStore (UserPreferences)
        │       ├── di/                    ← Hilt @Module objects (NetworkModule, DatabaseModule…)
        │       ├── model/                 ← shared domain models (Trip, ItineraryItem…)
        │       ├── secrets/               ← Secrets.kt (reads BuildConfig, mock-fallback rule)
        │       └── util/                  ← extensions, Result helpers, date/ISO-8601 utils
        ├── src/main/res/                  ← values/ (themes, colors), mipmap-*/ (adaptive icon), xml/
        └── src/test/…                     ← unit tests (JUnit; ViewModel + repository)
```

**Package root is `com.jetsetter.pro`** and the `applicationId` is `com.jetsetter.pro`. The package layout above (`ui.theme`, `ui.components`, `ui.navigation`, `feature.{home,itinerary,iris,expenses,more}`, `core.data.{local,remote,repository,prefs}`, `core.di`, `core.model`, `core.secrets`, `core.util`) is **locked** — put new code where it belongs.

### The pattern: MVVM + Repository

Every feature follows the same five-layer flow. On iOS this was MVVM with a `Service` singleton; on Android we keep MVVM and formalize the data side behind a **Repository** injected by **Hilt**.

| Layer | iOS equivalent | Android type | Responsibility |
|---|---|---|---|
| **Model** | `struct … : Codable` | `data class` (domain) + `@Entity` (Room) + DTO (`@JsonClass`) | The shape of the data |
| **DAO** | (CoreData / `@FetchRequest`) | `@Dao interface` returning `Flow<…>` | Type-safe local DB access |
| **Api** | `URLSession` call in a Service | Retrofit `interface` with `suspend fun` | Type-safe network access |
| **Repository** | `…Service.shared` singleton | `class …Repository @Inject` | Single source of truth; merges Room + Retrofit, exposes `Flow` |
| **ViewModel** | `ObservableObject` + `@Published` | `@HiltViewModel class … : ViewModel()` exposing `StateFlow<UiState>` | Holds UI state, runs use-cases in `viewModelScope` |
| **Screen** | SwiftUI `View` | `@Composable fun …Screen(...)` | Renders state, forwards events. **No logic.** |

```
┌────────────┐   collectAsStateWithLifecycle   ┌──────────────┐
│  Composable│ ◀──────────────────────────────  │  StateFlow   │
│   Screen   │  ── onEvent(...) ───────────────▶ │ (ViewModel)  │
└────────────┘                                   └──────┬───────┘
                                                        │ viewModelScope.launch
                                                 ┌──────▼───────┐
                                                 │  Repository  │
                                                 └──┬────────┬──┘
                                          Flow<…>  │        │  suspend
                                          ┌────────▼─┐   ┌──▼─────────┐
                                          │ Room DAO │   │ Retrofit   │
                                          └──────────┘   └────────────┘
```

> ### 🚧 The one rule that matters most
> **If you're writing a network call (or a DB query, or a `withContext(Dispatchers.IO)`) inside a `@Composable`, stop.** Move it down a layer.
> - Data access belongs in the **Repository**.
> - Orchestration and state belong in the **ViewModel** (`viewModelScope`).
> - The **Composable** only reads `StateFlow` and emits events. A Composable can recompose dozens of times per second — kicking off I/O from one is the #1 way to leak coroutines and ANR the app.

---

## 3. iOS/Swift → Android/Kotlin Concept Mapping

If you know the iOS app, this is your Rosetta Stone. Two big tables: **framework** (SwiftUI/iOS → Compose/Android) and **language** (Swift → Kotlin).

### 3.1 SwiftUI / iOS framework → Jetpack Compose / Android

| iOS / SwiftUI | Android / Kotlin | Notes |
|---|---|---|
| `struct FooView: View { var body }` | `@Composable fun Foo()` | A function, not a type. No `body` — the function *is* the body. |
| `@State private var x` | `var x by remember { mutableStateOf(...) }` | Local, recomposition-scoped UI state. |
| `@Binding var x` | `value: T, onValueChange: (T) -> Unit` | Compose has no two-way binding; hoist state and pass a lambda. |
| `@StateObject` / `ObservableObject` | `@HiltViewModel class … : ViewModel()` | The ViewModel survives config changes (rotation), like `@StateObject` survives view identity. |
| `@ObservedObject` (passed in) | `viewModel(...)` obtained in the Screen, or state passed down | Prefer passing **state + lambdas** to child Composables. |
| `@EnvironmentObject` | Hilt-injected singleton, or `CompositionLocal` | App-wide deps come from Hilt; UI-tree values from `CompositionLocalProvider`. |
| `@Published var x` | `private val _x = MutableStateFlow(...); val x = _x.asStateFlow()` | The reactive property. `StateFlow` ≈ `@Published`. |
| `ObservableObject` change → view re-render | `StateFlow` emit → recomposition | Collected with `collectAsStateWithLifecycle()`. |
| `VStack { }` | `Column { }` | Vertical stack. |
| `HStack { }` | `Row { }` | Horizontal stack. |
| `ZStack { }` | `Box { }` | Layered/overlapping. |
| `Spacer()` | `Spacer(Modifier.weight(1f))` | In Compose, `Spacer` needs a size or a `weight`. |
| `LazyVStack` / `List` | `LazyColumn { items(...) { } }` | Virtualized list. `List` rows ≈ `items`. |
| `ScrollView` | `Modifier.verticalScroll(rememberScrollState())` | For non-lazy scrolling content. |
| `.padding()`, `.background()`, `.cornerRadius()` | `Modifier.padding().background().clip(RoundedCornerShape())` | **Order matters** in a `Modifier` chain (it didn't, much, in SwiftUI). |
| `.frame(width:height:)` | `Modifier.size()` / `.width()` / `.fillMaxWidth()` | |
| `.foregroundColor` / `.font` | `color = …`, `style = MaterialTheme.typography.…` on `Text` | Text styling is a parameter, not a modifier (mostly). |
| Custom `ViewModifier` (e.g. `.jetCard()`) | Custom `Modifier` extension **or** a wrapper Composable (`JetCard { }`) | We ship `JetCard { }` as a Composable (§5). |
| `NavigationStack` / `NavigationLink` | Navigation Compose: `NavHost`, `composable(route)`, `navController.navigate()` | Routes are strings (or type-safe routes). |
| `TabView { .tabItem { } }` | `Scaffold(bottomBar = { NavigationBar { NavigationBarItem(...) } })` | The 5-tab spine. |
| `.sheet(isPresented:)` | `ModalBottomSheet(onDismissRequest = ...) { }` | Bottom sheet presentation. |
| `.alert(...)` | `AlertDialog(onDismissRequest = ...) { }` | |
| `.task { await … }` | `LaunchedEffect(key) { … }` | Run a suspend block tied to composition lifecycle. |
| `.onAppear` / `.onDisappear` | `LaunchedEffect(Unit)` / `DisposableEffect` | |
| `Codable` | Moshi `@JsonClass(generateAdapter = true) data class` | JSON in/out. `@Json(name = "…")` ≈ `CodingKeys`. |
| `JSONDecoder().dateDecodingStrategy = .iso8601` | Moshi adapter for ISO-8601 (`java.time.Instant`/`OffsetDateTime`) | We standardize on ISO-8601 + snake_case on the wire. |
| `UserDefaults` | **DataStore** (`Preferences` or Proto) | `UserPreferences` lives in `core.data.prefs`. Don't use `SharedPreferences` for new code. |
| `Keychain` | **EncryptedSharedPreferences** (androidx.security-crypto) / **Tink** | The vault features (Document/Identity/Loyalty) use this — §7. |
| `URLSession` | **Retrofit** + **OkHttp** (interceptors, retry/backoff) | All HTTP goes through `core.data.remote.ApiClient`. |
| `async` / `await` | `suspend` fun / call inside a coroutine | Same mental model. `try await foo()` → `foo()` in a `suspend` context. |
| `Task { }` | `viewModelScope.launch { }` (in a VM) / `rememberCoroutineScope()` (in UI) | Structured concurrency. |
| `AsyncThrowingStream` (Claude streaming) | `Flow<String>` (e.g. `flow { emit(...) }`) | The IRIS token stream becomes a `Flow`. |
| Combine `@Published` / `PassthroughSubject` | `StateFlow` / `SharedFlow` | Kotlin Flow replaces Combine wholesale. |
| `.onReceive(publisher)` | `.collect { }` / `collectAsStateWithLifecycle()` | |
| `BGTaskScheduler` / `BGAppRefreshTask` | **WorkManager** (`CoroutineWorker`, `PeriodicWorkRequest`) | Background **disruption polling** is a `CoroutineWorker`. |
| `UNUserNotificationCenter` | `NotificationManagerCompat` + a notification channel | Disruption alerts. |
| StoreKit / `SubscriptionManager` | **Google Play Billing** | "Pro" entitlement gate. (Port later — see parity doc.) |
| PassKit (`.pkpass`, Wallet) | **Google Wallet** API | Boarding passes / loyalty cards. |
| MapKit (`AirportMap`) | **Google Maps** Compose (`maps-compose`) | |
| EventKit (`CalendarService`) | **CalendarContract** (ContentResolver) | Itinerary → device calendar sync. |
| Vision (`VisionOCRService`) | **ML Kit Text Recognition** | Receipt OCR for Expenses. |
| WatchConnectivity | **Wear OS** (Data Layer / Tiles) | Out of scope for the initial scaffold. |
| CryptoKit | **Tink** (+ androidx.security-crypto) | Vault encryption primitives. |
| `LocalAuthentication` (Face ID) | **androidx.biometric** (`BiometricPrompt`) | Unlock the vaults. |
| `LaunchScreen` / `@main` splash | **androidx.core:core-splashscreen** | Themed splash on cold start. |
| `AsyncImage` | **Coil** (`AsyncImage` from `coil-compose`) | Remote/city images. |
| `Bundle.main` Info.plist values | **`BuildConfig`** fields (generated from Gradle) | How secrets reach code — §7. |

### 3.2 Swift language → Kotlin language

| Swift | Kotlin | Notes |
|---|---|---|
| `let x = 1` | `val x = 1` | Immutable binding. |
| `var x = 1` | `var x = 1` | Mutable binding. Same keyword, same meaning. Prefer `val`. |
| `String?` (optional) | `String?` (nullable) | Same syntax, same idea. **Kotlin nullability ≈ Swift optionals.** |
| `if let y = x { }` | `x?.let { y -> }` or `if (x != null) { }` | Smart-casts: after `if (x != null)`, `x` is non-null in that block. |
| `guard let y = x else { return }` | `val y = x ?: return` | Elvis + early return. |
| `x ?? default` | `x ?: default` | Elvis operator = nil-coalescing. |
| `x!` (force unwrap) | `x!!` (not-null assertion) | Both crash on null. Avoid both. |
| `x?.foo()` (optional chaining) | `x?.foo()` | Identical. |
| `struct Foo { }` | `data class Foo(...)` | Value-ish type with auto `equals`/`hashCode`/`copy`. |
| `class Foo { }` (reference) | `class Foo { }` | Reference type. ViewModels are classes. |
| `protocol Fooable { }` | `interface Fooable { }` | |
| `extension String { }` | `fun String.foo()` (extension function) | Kotlin extensions are top-level functions, not blocks. |
| `enum Status { case onTime, delayed }` | `enum class Status { ON_TIME, DELAYED }` | Simple enum. |
| `enum E { case a(Int); case b(String) }` (associated values) | `sealed class E { data class A(val n: Int) : E(); data class B(val s: String) : E() }` | **Associated values → sealed class/interface.** This is the big one — used for UI state and results. |
| `switch x { case … }` (exhaustive) | `when (x) { … }` (exhaustive on sealed/enum) | `when` over a sealed class needs no `else`. |
| `[Trip]` | `List<Trip>` | Immutable list by default (`listOf`). `mutableListOf` for mutable. |
| `[String: Int]` | `Map<String, Int>` | |
| `arr.map { $0.x }` | `arr.map { it.x }` | `$0` → `it` (single implicit param). |
| `arr.filter { $0.isActive }` | `arr.filter { it.isActive }` | |
| `func f(a: Int, b: Int)` (labels) | `fun f(a: Int, b: Int)` + named args `f(a = 1, b = 2)` | Kotlin labels are optional but encouraged. |
| `"\(name)"` (interpolation) | `"$name"` / `"${expr}"` | |
| `defer { }` | `try { } finally { }` / `use { }` | |
| `typealias` | `typealias` | Same. |
| `Result<T, Error>` | `Result<T>` (kotlin.Result) or a custom `sealed interface Result` | We use a small custom `Result`/`UiState` sealed type for screens. |
| `@MainActor` | `Dispatchers.Main` / `withContext(Main)`; ViewModels emit on Main by default | StateFlow updates are observed on the main thread by the collector. |
| `Sendable` | (no direct equivalent; structured concurrency + immutability) | Don't worry about it on Android. |
| `#if DEBUG` | `if (BuildConfig.DEBUG)` | Runtime check, or product flavors / `buildTypes`. |

> **Mental shortcut:** Swift `struct` + `Codable` → Kotlin `data class` + Moshi `@JsonClass`. Swift `enum` with associated values → Kotlin `sealed class`. Swift `ObservableObject`/`@Published` → Kotlin `ViewModel`/`StateFlow`. Internalize those three and 80% of the port reads naturally.

---

## 4. Android Studio Survival Guide

The iOS guide had an "Xcode Survival Guide." Here's the Android Studio equivalent. (Use **Android Studio Ladybug** or newer — earlier versions predate some Compose/AGP features used here.)

### Opening the project

> **Open the `android/` folder, not the repo root.** The Android project's root is `android/` (later it becomes the root of `DevJ1975/JetSetter_Android`). If you open `jetsetter-pro/`, Studio sees the Xcode project and won't index Gradle.

1. **File → Open…** → select `…/jetsetter-pro/android`.
2. Studio detects Gradle and offers to sync. Let it. First sync downloads the Gradle distribution + all deps from `gradle/libs.versions.toml` — this can take a few minutes.
3. If prompted about the **JDK**, point it at **JDK 17** (see below).

### The interface (what each area does)

```
┌──────────────────────────────────────────────────────────────┐
│  TOOLBAR:  Run ▶  Debug 🐞  | app ▾  | Pixel 8 (AVD) ▾  | Sync │
├──────────┬───────────────────────────────────┬───────────────┤
│          │                                   │               │
│ PROJECT  │            EDITOR                 │  Compose      │
│ (left)   │   your Kotlin code               │  PREVIEW /    │
│          │                                   │  Inspector    │
│ Android/ │                                   │  (right)      │
│ Project  │                                   │               │
│ views    │                                   │               │
├──────────┴───────────────────────────────────┴───────────────┤
│  BOTTOM:  Build | Logcat | Run | Terminal | Problems          │
└──────────────────────────────────────────────────────────────┘
```

- **Project tool window (left):** toggle between the **Android** view (logical, groups source sets) and the **Project** view (true folder layout). The Android view hides Gradle noise; the Project view shows `app/src/main/java/...` exactly as on disk.
- **Compose Preview (right):** renders any `@Preview` Composable without launching the app (the Xcode Canvas analog — see §5).
- **Logcat (bottom):** the device/emulator log stream. Filter by package `com.jetsetter.pro` and by level (Error/Warn/Info). **This is where your crashes and `Log.d` output appear.**

### JDK & SDK setup (do this once)

- **JDK 17+**: Android Studio Ladybug bundles a compatible JDK (JBR 17/21). Confirm at **Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK** = 17 (or the bundled JBR). The build targets `JavaVersion.VERSION_17` and Kotlin `jvmTarget = "17"`.
- **Android SDK 35**: Open **Tools → SDK Manager → SDK Platforms** and install **Android 15 (API 35)** — this project uses `compileSdk 35` / `targetSdk 35`. Under **SDK Tools**, ensure **Android SDK Build-Tools**, **Platform-Tools**, and **Android Emulator** are checked.
- **minSdk 26** means the app runs on Android 8.0+. You can still *use* newer APIs behind `Build.VERSION.SDK_INT` checks.

### Emulator (AVD) — running without a physical device

1. **Tools → Device Manager → Create Device.**
2. Pick a phone profile (e.g. **Pixel 8**), then a **system image** with **API 35** (download if needed). Prefer a Google-APIs/Play image so Maps/Wallet work.
3. Launch the AVD, select it in the toolbar device dropdown, and press **Run ▶** (`Ctrl/⌘ + R`).

> Features that need a **real device**: hardware biometrics on some images, NFC, and certain Wallet flows. Most of JetSetter Pro runs fine on the emulator with mock data.

### Keyboard shortcuts you'll use daily

| Action | macOS | Windows/Linux |
|---|---|---|
| Run app | `⌃ R` | `Shift + F10` |
| Debug app | `⌃ D` | `Shift + F9` |
| Stop | `⌘ F2` | `Ctrl + F2` |
| Build / Make project | `⌘ F9` | `Ctrl + F9` |
| Search Everywhere (≈ Open Quickly) | `Shift Shift` | `Shift Shift` |
| Go to file | `⌘ ⇧ O` | `Ctrl + Shift + N` |
| Jump to definition | `⌘ B` / `⌘ click` | `Ctrl + B` / `Ctrl + click` |
| Reformat code | `⌘ ⌥ L` | `Ctrl + Alt + L` |
| Optimize imports | `⌃ ⌥ O` | `Ctrl + Alt + O` |
| Toggle comment | `⌘ /` | `Ctrl + /` |
| Rename (refactor) | `⇧ F6` | `Shift + F6` |
| Show Logcat | (Logcat tab) | (Logcat tab) |
| Sync Gradle | (elephant ↻ icon) | (elephant ↻ icon) |

### When things break

- **"Gradle sync failed":** read the **Build** tab message. Usually a version-catalog typo (`gradle/libs.versions.toml`) or no network for deps.
- **Weird, stale errors:** **Build → Clean Project**, then **Build → Rebuild Project**. If still odd: **File → Invalidate Caches… → Invalidate and Restart** (the `⌘⇧K` of Android).
- **"SDK location not found":** you have no `local.properties`. Copy `local.properties.example` → `local.properties` and set `sdk.dir` (Studio writes this automatically once an SDK is configured).
- **Adding a file:** right-click a package → **New → Kotlin Class/File** (or **New → Compose → Composable**). Follow the existing naming (`FooScreen.kt`, `FooViewModel.kt`).

---

## 5. Compose Fundamentals

Compose is Android's declarative UI toolkit — the SwiftUI analog. If you've written SwiftUI, this will feel familiar; the syntax differs but the model (UI = function of state) is the same.

### A basic Composable + Preview (the SwiftUI `View` + `#Preview` analog)

```kotlin
package com.jetsetter.pro.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.jetsetter.pro.ui.theme.JetsetterTheme

@Composable
fun FlightCard(
    flightNumber: String,           // "props", like a SwiftUI View's stored properties
    destination: String,
    departureTime: String,
    modifier: Modifier = Modifier,  // ALWAYS accept a Modifier param, default Modifier
) {
    JetCard(modifier = modifier) {  // our themed card wrapper (the .jetCard() analog)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = flightNumber,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = JetsetterTheme.colors.textPrimary,
            )
            Text(
                text = destination,
                style = MaterialTheme.typography.bodyMedium,
                color = JetsetterTheme.colors.textSecondary,
            )
            Text(
                text = departureTime,
                style = MaterialTheme.typography.labelMedium,
                color = JetsetterTheme.colors.textSecondary,
            )
        }
    }
}

@Preview(showBackground = true, name = "FlightCard – Dark")
@Composable
private fun FlightCardPreview() {
    JetsetterTheme {                // wrap previews in the theme, like SwiftUI's environment
        FlightCard(
            flightNumber = "DL 1423",
            destination = "Atlanta, GA",
            departureTime = "7:00 AM",
            modifier = Modifier.padding(16.dp),
        )
    }
}
```

Open this file and the **Compose Preview** panel renders it live — the Xcode Canvas equivalent. Edit, and it hot-reloads.

### Layout containers (SwiftUI stacks → Compose)

```kotlin
// Column == VStack
Column(
    verticalArrangement = Arrangement.spacedBy(16.dp),       // ≈ VStack(spacing: 16)
    horizontalAlignment = Alignment.Start,
) {
    Text("Top"); Text("Bottom")
}

// Row == HStack
Row(
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalAlignment = Alignment.CenterVertically,
) {
    Text("Left")
    Spacer(Modifier.weight(1f))   // ≈ Spacer() pushing items apart
    Text("Right")
}

// Box == ZStack
Box(contentAlignment = Alignment.Center) {
    BackgroundGradient()
    Text("Overlay text")
}

// LazyColumn == List / LazyVStack
LazyColumn(contentPadding = PaddingValues(16.dp)) {
    items(trips, key = { it.id }) { trip ->
        TripRow(trip = trip)
    }
}
```

### Modifiers (CSS-ish, like SwiftUI modifiers — but order matters)

```kotlin
Text(
    text = "Delayed",
    modifier = Modifier
        .padding(horizontal = 10.dp, vertical = 5.dp)  // applied first
        .background(JetsetterTheme.colors.warning.copy(alpha = 0.15f), CircleShape)
        .padding(2.dp),                                  // applied after background
)
```

> In SwiftUI, modifier order rarely changed the result; in Compose it **frequently** does. `padding().background()` ≠ `background().padding()`. Read a chain top-to-bottom as "apply, then apply."

### State (the `@State` analog)

```kotlin
@Composable
fun DelayBanner() {
    var expanded by remember { mutableStateOf(false) }   // ≈ @State private var expanded = false

    Column {
        Button(onClick = { expanded = !expanded }) {     // toggling triggers recomposition
            Text("Flight Delayed — Tap for Details")
        }
        if (expanded) {
            Text("New departure: 9:45 AM — Gate C22", Modifier.padding(8.dp))
        }
    }
}
```

- `remember { }` keeps the value across recompositions (like `@State` keeping value across re-renders).
- `rememberSaveable { }` *also* survives process death / rotation (use for things like text field input you don't want to lose).
- For anything that outlives the screen or needs business logic, it belongs in a **ViewModel**, not `remember` — see §6.

### Navigation (NavigationStack → Navigation Compose)

```kotlin
// ui/navigation/Destinations.kt
sealed class Dest(val route: String) {
    data object Home : Dest("home")
    data object Itinerary : Dest("itinerary")
    data object Iris : Dest("iris")
    data object Expenses : Dest("expenses")
    data object More : Dest("more")
    data object TripDetail : Dest("trip/{tripId}") {
        fun build(id: String) = "trip/$id"
    }
}

// ui/navigation/JetNavHost.kt
@Composable
fun JetNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    NavHost(navController, startDestination = Dest.Home.route, modifier = modifier) {
        composable(Dest.Home.route)      { HomeScreen(onOpenTrip = { id ->
            navController.navigate(Dest.TripDetail.build(id))
        }) }
        composable(Dest.Itinerary.route) { ItineraryScreen() }
        composable(Dest.Iris.route)      { IrisScreen() }
        composable(Dest.Expenses.route)  { ExpensesScreen() }
        composable(Dest.More.route)      { MoreScreen() }
        composable(
            route = Dest.TripDetail.route,
            arguments = listOf(navArgument("tripId") { type = NavType.StringType }),
        ) { backStack ->
            TripDetailScreen(tripId = backStack.arguments?.getString("tripId").orEmpty())
        }
    }
}
```

The 5-tab shell wires `NavHost` into a `Scaffold` bottom bar:

```kotlin
@Composable
fun JetApp() {
    val navController = rememberNavController()
    Scaffold(
        bottomBar = { JetBottomBar(navController) }  // NavigationBar with 5 NavigationBarItems
    ) { padding ->
        JetNavHost(navController, Modifier.padding(padding))
    }
}
```

### Using the JetSetter theme

The design system is ported in `ui/theme/`. The colors come straight from the iOS `JetsetterTheme` — note the brand is **deep navy + sky blue** (the iOS gradient is *named* `goldGradient` for historical reasons but renders **blue**; we keep the `GoldTag`/`goldText` names for continuity, see `docs/DESIGN_SYSTEM.md`).

```kotlin
@Composable
fun ThemedExample() {
    JetCard {                                   // ≈ .jetCard() — glass/elevated surface
        Column {
            Text("Tokyo Spring Trip", color = JetsetterTheme.colors.textPrimary)
            GoldTag(text = "On Time", icon = Icons.Filled.CheckCircle)   // accent capsule chip
        }
    }
}
```

Key tokens (full list in `docs/DESIGN_SYSTEM.md`):

| Token | Dark | Light | Use |
|---|---|---|---|
| `colors.background` | `#10131E` | `#EFF1F8` | App canvas |
| `colors.surface` | `#161929` | `#FFFFFF` | Cards |
| `colors.accent` | `#3B9EF0` | `#0055CC` | Buttons, tints, highlights |
| `colors.success` | `#1DB97D` | `#0C7A4E` | On-time / success |
| `colors.warning` | `#E8A020` | `#B07010` | Delayed / warning |
| `colors.danger` | `#E84040` | `#C42020` | Cancelled / error |
| `colors.textPrimary` | `#ECEEF4` | `#0A0C18` | Primary text |
| `colors.textSecondary`| `#8B92A8` | `#52587A` | Secondary text |

Card radius **18dp**, card padding **16dp**, spacing scale 4/8/16/24/32dp — matching iOS `JetsetterTheme.Card` and `.Spacing`.

---

## 6. State Management

This is the heart of MVVM on Android. The pattern: **ViewModel holds a `StateFlow<UiState>`; the Composable collects it lifecycle-aware; Hilt injects the ViewModel and its repository.**

### The reactive trio

| iOS | Android | Role |
|---|---|---|
| `@Published var x` | `MutableStateFlow(initial)` (private) exposed as `StateFlow` | Observable state |
| `@StateObject var vm` | `hiltViewModel()` in the Screen | Owns the ViewModel |
| view re-renders on `@Published` change | recomposition on `StateFlow` emit | Reactivity |

### Model a screen's state as one immutable `data class`

Prefer a single UI-state object over many scattered flags (it eliminates impossible states and makes previews trivial):

```kotlin
// feature/itinerary/ItineraryUiState.kt
data class ItineraryUiState(
    val trips: List<Trip> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)
```

### The ViewModel (the `ObservableObject` analog) with Hilt

```kotlin
// feature/itinerary/ItineraryViewModel.kt
package com.jetsetter.pro.feature.itinerary

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jetsetter.pro.core.data.repository.TripRepository
import com.jetsetter.pro.core.model.Trip
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ItineraryViewModel @Inject constructor(
    private val repository: TripRepository,   // injected by Hilt, no singletons
) : ViewModel() {

    private val _ui = MutableStateFlow(ItineraryUiState(isLoading = true))
    val ui: StateFlow<ItineraryUiState> = _ui.asStateFlow()

    init {
        // Collect the repository's Flow and fold it into UI state.
        // Equivalent to the iOS ItineraryViewModel.loadTrips() running on init.
        viewModelScope.launch {
            repository.observeTrips()
                .catch { e -> _ui.update { it.copy(isLoading = false, errorMessage = e.message) } }
                .collect { trips -> _ui.update { it.copy(trips = trips, isLoading = false) } }
        }
    }

    fun addTrip(trip: Trip) = viewModelScope.launch {
        runCatching { repository.addTrip(trip) }
            .onFailure { e -> _ui.update { it.copy(errorMessage = e.message) } }
    }

    fun deleteTrip(id: String) = viewModelScope.launch {
        repository.deleteTrip(id)
    }
}
```

### The repository + DAO (single source of truth)

```kotlin
// core/data/local/TripDao.kt
@Dao
interface TripDao {
    @Query("SELECT * FROM trips ORDER BY start_date ASC")
    fun observeTrips(): Flow<List<TripEntity>>          // reactive — emits on every write

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(trip: TripEntity)

    @Query("DELETE FROM trips WHERE id = :id")
    suspend fun delete(id: String)
}

// core/data/repository/TripRepository.kt
class TripRepository @Inject constructor(
    private val dao: TripDao,
    // private val api: ItineraryApi,   // add when a backend exists
) {
    fun observeTrips(): Flow<List<Trip>> =
        dao.observeTrips().map { rows -> rows.map { it.toDomain() } }

    suspend fun addTrip(trip: Trip) = dao.upsert(trip.toEntity())
    suspend fun deleteTrip(id: String) = dao.delete(id)
}
```

> On iOS the `ItineraryViewModel` persisted to `UserDefaults` and decoded JSON by hand. On Android we use **Room** (a real SQLite ORM): the DAO returns a `Flow`, so when you `upsert`, every collector — including the UI — updates automatically. That's the modern replacement for the manual `loadTrips()/saveTrips()` round-trips.

### The Screen — collect lifecycle-aware, render, forward events

```kotlin
// feature/itinerary/ItineraryScreen.kt
@Composable
fun ItineraryScreen(
    viewModel: ItineraryViewModel = hiltViewModel(),   // Hilt provides it (≈ @StateObject)
) {
    // collectAsStateWithLifecycle stops collecting when the screen is in the background —
    // the correct default. (Needs androidx.lifecycle:lifecycle-runtime-compose.)
    val state by viewModel.ui.collectAsStateWithLifecycle()

    ItineraryContent(
        state = state,
        onAddTrip = viewModel::addTrip,
        onDeleteTrip = viewModel::deleteTrip,
    )
}

@Composable
private fun ItineraryContent(
    state: ItineraryUiState,
    onAddTrip: (Trip) -> Unit,
    onDeleteTrip: (String) -> Unit,
) {
    when {
        state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        state.trips.isEmpty() -> EmptyTripsView(onAddTrip = { /* open add sheet */ })
        else -> LazyColumn(contentPadding = PaddingValues(16.dp)) {
            items(state.trips, key = { it.id }) { trip ->
                TripRow(trip = trip, onDelete = { onDeleteTrip(trip.id) })
            }
        }
    }
}
```

Notice the split: a **stateful** `ItineraryScreen` (knows the ViewModel) wrapping a **stateless** `ItineraryContent` (pure function of `state` + lambdas). The stateless half is trivially previewable and testable — always structure features this way.

> ⚠️ **Always use `collectAsStateWithLifecycle()`**, not `collectAsState()`. The latter keeps collecting while the app is backgrounded, wasting work and occasionally leaking. This is the Android equivalent of stopping a Combine subscription `.onDisappear`.

---

## 7. Working with APIs & Secrets

All HTTP goes through one place: `core.data.remote`. Never call OkHttp/Retrofit from a Composable or scatter base URLs around — add an endpoint to an `Api` interface and let the repository drive it.

### The ApiClient / Retrofit pattern

```kotlin
// core/data/remote/ApiClient.kt — built and provided by Hilt (see NetworkModule below)
// Retrofit + OkHttp + Moshi, snake_case + ISO-8601, with retry/backoff via an interceptor.

interface ClaudeApi {
    @POST("v1/messages")
    suspend fun messages(@Body body: ClaudeRequest): ClaudeResponse
}

// DTOs use Moshi; @Json(name=...) is the CodingKeys analog.
@JsonClass(generateAdapter = true)
data class ClaudeRequest(
    val model: String,
    @Json(name = "max_tokens") val maxTokens: Int,
    val system: String? = null,
    val messages: List<ClaudeMessage>,
    val stream: Boolean = false,
)

@JsonClass(generateAdapter = true)
data class ClaudeMessage(val role: String, val content: String)
```

### Hilt wiring for networking

```kotlin
// core/di/NetworkModule.kt
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides @Singleton
    fun provideMoshi(): Moshi = Moshi.Builder()
        .add(InstantJsonAdapter())                    // ISO-8601 <-> java.time.Instant
        .build()

    @Provides @Singleton
    fun provideOkHttp(): OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) BODY else NONE
        })
        .addInterceptor(RetryBackoffInterceptor(maxRetries = 3))  // exponential backoff
        .build()

    @Provides @Singleton
    fun provideClaudeApi(client: OkHttpClient, moshi: Moshi): ClaudeApi =
        Retrofit.Builder()
            .baseUrl("https://api.anthropic.com/")    // see API_REFERENCE.md
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(ClaudeApi::class.java)
}
```

### How secrets flow: `local.properties` → `BuildConfig` → `Secrets`

This is the Android port of the iOS `Secrets.xcconfig → Info.plist → AppSecrets` chain. **No key is ever committed.**

```
local.properties (gitignored)            app/build.gradle.kts                 core/secrets/Secrets.kt
┌───────────────────────────┐            ┌──────────────────────────┐        ┌─────────────────────────┐
│ API_ANTHROPIC=sk-ant-...  │  ───read─▶ │ buildConfigField(        │ ─gen─▶ │ object Secrets {        │
│ API_FLIGHTAWARE=...       │            │  "String","API_ANTHROPIC"│        │   val anthropic = BuildConfig.API_ANTHROPIC │
│ ...                       │            │ )                        │        │   fun isConfigured(v)…  │
└───────────────────────────┘            └──────────────────────────┘        └─────────────────────────┘
```

**1. Template** — `local.properties.example` lists every key (committed). Devs copy it to `local.properties` (gitignored) and fill values:

```properties
# local.properties.example  (copy to local.properties, do NOT commit local.properties)
sdk.dir=/Users/you/Library/Android/sdk
API_ANTHROPIC=YOUR_ANTHROPIC_API_KEY
API_FLIGHTAWARE=YOUR_FLIGHTAWARE_KEY
# …full list in docs/API_REFERENCE.md
```

**2. Gradle reads them and emits typed `BuildConfig` fields** (`app/build.gradle.kts`):

```kotlin
import java.util.Properties

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun secret(key: String): String = (localProps.getProperty(key) ?: System.getenv(key)).orEmpty()
//                                                                  ^ CI injects via env vars

android {
    buildFeatures { buildConfig = true; compose = true }
    defaultConfig {
        buildConfigField("String", "API_ANTHROPIC",  "\"${secret("API_ANTHROPIC")}\"")
        buildConfigField("String", "API_FLIGHTAWARE", "\"${secret("API_FLIGHTAWARE")}\"")
        // …one line per key
    }
}
```

**3. `Secrets` reads `BuildConfig` and enforces the mock rule** (`core/secrets/Secrets.kt`) — a direct port of iOS `AppSecrets.value(for:)`:

```kotlin
object Secrets {
    val anthropic: String?   get() = sanitize(BuildConfig.API_ANTHROPIC)
    val flightAware: String? get() = sanitize(BuildConfig.API_FLIGHTAWARE)

    /** Empty / placeholder values become null → callers fall back to MockData. */
    private fun sanitize(raw: String?): String? {
        val t = raw?.trim().orEmpty()
        if (t.isEmpty() || t.startsWith("YOUR_") || t == "REPLACE_ME") return null
        return t
    }

    fun isConfigured(value: String?): Boolean = sanitize(value) != null
}
```

> ### The "empty key ⇒ use MockData" rule
> Every repository checks `Secrets.isConfigured(...)` (or `Secrets.anthropic != null`) **before** a live call. If the key is missing/placeholder, it returns canned `MockData` instead of hitting the network. This is why the app **builds and runs out of the box with no keys** — exactly like the iOS `MockDataService`/`DemoSeeder` path. Mirror this in every new feature.

### Adding a new endpoint (checklist)

1. **Add the key** (if the API needs auth) to `local.properties.example`, a `buildConfigField` line, and a `Secrets` accessor — and document it in `docs/API_REFERENCE.md`.
2. **Add DTOs** in `core/data/remote` as `@JsonClass(generateAdapter = true) data class`es (snake_case via `@Json`).
3. **Add a method** to the relevant Retrofit `Api` interface (`suspend fun`, `@GET`/`@POST`).
4. **Provide the Api** in a Hilt `@Module` (`@Provides @Singleton`).
5. **Call it from the Repository**, mapping DTO → domain model, with a `Secrets.isConfigured` guard + `MockData` fallback.
6. **Expose** the data as a `Flow`/suspend result; the ViewModel folds it into `UiState`.

---

## 8. The IRIS Assistant (Claude API)

**IRIS** (*Intelligent Routing & Itinerary Specialist*) is the conversational assistant on the IRIS tab. On iOS, `AIService` routed: **Apple Intelligence on-device → Claude fallback → mock**. **Android drops the on-device tier and standardizes on the Anthropic Claude API**, keeping the mock tier for keyless/demo runs.

### Provider routing (Android)

```
Secrets.anthropic == null  ──▶  Demo mode (IrisDemoResponses)        ← always works, no key
Secrets.anthropic != null  ──▶  Claude (api.anthropic.com/v1/messages)
```

### Endpoint & headers (authoritative)

| Field | Value |
|---|---|
| URL | `https://api.anthropic.com/v1/messages` (Retrofit `baseUrl = https://api.anthropic.com/`, path `v1/messages`) |
| Method | `POST` |
| Header | `x-api-key: <API_ANTHROPIC>` |
| Header | `anthropic-version: 2023-06-01` |
| Header | `content-type: application/json` |
| Body model | e.g. `claude-3-5-sonnet-latest` (or a newer Sonnet); keep the id in one constant so it's easy to bump |

> **Auth note:** Anthropic uses the `x-api-key` header (**not** `Authorization: Bearer`). The header is injected by an OkHttp interceptor that reads `Secrets.anthropic`, so DTOs stay auth-free.

### Message schema (Moshi)

```kotlin
@JsonClass(generateAdapter = true)
data class ClaudeRequest(
    val model: String,
    @Json(name = "max_tokens") val maxTokens: Int = 1024,
    val system: String? = null,                 // IRIS personality / system prompt
    val messages: List<ClaudeMessage>,          // running conversation, oldest → newest
    val stream: Boolean = false,
)

@JsonClass(generateAdapter = true)
data class ClaudeMessage(val role: String, val content: String)  // role: "user" | "assistant"

@JsonClass(generateAdapter = true)
data class ClaudeResponse(
    val id: String,
    val role: String,
    val content: List<ClaudeContentBlock>,      // text blocks
)

@JsonClass(generateAdapter = true)
data class ClaudeContentBlock(val type: String, val text: String?)
```

### The repository call

```kotlin
class IrisRepository @Inject constructor(
    private val api: ClaudeApi,
) {
    private val systemPrompt = """
        You are IRIS — the Intelligent Routing & Itinerary Specialist for JetSetter Pro.
        You are warm, concise, and anticipatory: a quietly relentless travel companion who
        has already read the traveler's itinerary. Offer next steps; don't over-explain.
    """.trimIndent()

    /** Returns IRIS's reply, or a canned demo reply when no key is configured. */
    suspend fun ask(history: List<ChatMessage>, prompt: String): String {
        if (Secrets.anthropic == null) {                    // demo / keyless path
            delay(900)                                       // tiny "thinking" beat, like iOS
            return IrisDemoResponses.response(prompt)
        }
        val messages = history.map { ClaudeMessage(it.role, it.text) } +
            ClaudeMessage(role = "user", content = prompt)
        val resp = api.messages(
            ClaudeRequest(model = CLAUDE_MODEL, system = systemPrompt, messages = messages)
        )
        return resp.content.firstOrNull { it.type == "text" }?.text.orEmpty()
    }

    companion object { const val CLAUDE_MODEL = "claude-3-5-sonnet-latest" }
}
```

### The ViewModel + Screen

```kotlin
@HiltViewModel
class IrisViewModel @Inject constructor(
    private val repo: IrisRepository,
) : ViewModel() {
    private val _ui = MutableStateFlow(IrisUiState())
    val ui: StateFlow<IrisUiState> = _ui.asStateFlow()

    fun send(text: String) = viewModelScope.launch {
        val userMsg = ChatMessage(role = "user", text = text)
        _ui.update { it.copy(messages = it.messages + userMsg, isThinking = true) }
        val reply = runCatching { repo.ask(_ui.value.messages, text) }
            .getOrElse { "I hit a snag reaching my brain. Mind trying again?" }
        _ui.update {
            it.copy(messages = it.messages + ChatMessage("assistant", reply), isThinking = false)
        }
    }
}
```

The `IrisScreen` collects `ui` with `collectAsStateWithLifecycle()` and renders a message list + input bar, showing a typing indicator while `isThinking`.

### Where the demo / canned fallback lives

`feature.iris.IrisDemoResponses` (ported from iOS `IRISDemoResponses.swift`) maps keywords ("weather", "who are you", "visa"…) to pre-written, on-brand IRIS answers. It is the keyless/offline safety net — **the IRIS tab must always respond**, even with no `API_ANTHROPIC` key, exactly as it did on the iOS simulator.

> **Env key:** `API_ANTHROPIC` (same name as iOS `AppSecrets.Key.anthropic`). Flows through `local.properties`/CI-env → `BuildConfig.API_ANTHROPIC` → `Secrets.anthropic`. Streaming (token-by-token) is a later enhancement: model it as `Flow<String>` emitting cumulative text, the way iOS used `AsyncThrowingStream`.

---

## 9. Build, Run & CI

### Local build (CLI)

From `android/`:

```bash
./gradlew assembleDebug          # build the debug APK
./gradlew installDebug           # build + install to a connected device/emulator
./gradlew lint                   # Android Lint (writes app/build/reports/lint-results-*.html)
./gradlew test                   # JVM unit tests (ViewModels, repositories, mappers)
./gradlew :app:dependencies      # inspect the resolved dependency graph
./gradlew clean                  # wipe build/ if things get weird
```

> Always use the wrapper `./gradlew` (it pins the exact Gradle version), never a globally installed `gradle`.

### Continuous Integration — the authoritative build check

> ### 🛑 There is no Android SDK in headless agent environments.
> If you're an AI agent running in a sandbox without Android Studio/SDK, **you cannot build locally** — `./gradlew assembleDebug` will fail for lack of an SDK. **CI is the source of truth for "does it compile."** Make your change, push the branch, and let `.github/workflows/android-ci.yml` build it. Treat a green CI run as the build passing; do not claim a build succeeded that you could not actually run.

`.github/workflows/android-ci.yml` (shape):

```yaml
name: Android CI
on:
  push:
    branches: [ main, "feature/**", "fix/**" ]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }
      - uses: android-actions/setup-android@v3      # installs the Android SDK on the runner
      - uses: gradle/actions/setup-gradle@v3
      - name: Assemble (debug)
        run: ./gradlew assembleDebug --stacktrace
        env:
          API_ANTHROPIC: ${{ secrets.API_ANTHROPIC }}   # injected; never in the repo
      - name: Lint
        run: ./gradlew lint
```

Because secrets are injected as **env vars** (and `secret()` in `build.gradle.kts` falls back to `System.getenv`), CI builds with real keys when configured and still compiles when they're absent (the app just runs in mock mode).

---

## 10. How to Continue the Port

The scaffold wires **Home** and **Itinerary** and stubs **IRIS / Expenses / More**. The remaining work is porting the other ~30 iOS feature modules. `docs/FEATURE_PARITY.md` is the master checklist; keep it updated as you land each one.

### All 34 modules (iOS `Features/`) — port targets

`AirportMap` · `Assistant`/`IRIS` · `Booking` · `Carbon` · `CheckIn` · `CurrencyTracker` · `DepartureOptimizer` · `Disruption` · `DocumentVault` · `ExpenseExport` · `ExpenseTracker` · `FlightBoard` · `FlightTracker` · `GroundTransport` · `Home` · `IdentityVault` · `InFlight` · `Intelligence` · `Itinerary` · `LocalExperience` · `LoyaltyVault` · `LuggageTracker` · `More` · `OfflineKit` · `Onboarding` · `PackingList` · `RentalCar` · `Settings` · `Subscription` · `Translator` · `TravelEssentials` · `TravelWallet` · `TripJournal` · `VisaLookup`

### Recommended porting order

1. **Onboarding + Settings** — they own `UserPreferences` (DataStore) and theme/colorScheme, which everything else reads. Port these first so the app has real first-run + preferences.
2. **FlightTracker + FlightBoard + Disruption** — the core travel loop. Disruption brings in **WorkManager** background polling (the `BGTaskScheduler` analog) and notifications.
3. **PackingList + Expenses (incl. OCR via ML Kit) + ExpenseExport** — high-value, mostly local/Room data; Expenses also exercises Claude (packing suggestions used Anthropic on iOS).
4. **The vaults: DocumentVault, IdentityVault, LoyaltyVault, TravelWallet** — these need **EncryptedSharedPreferences/Tink** + **BiometricPrompt**. Do them together to share the crypto/biometric plumbing.
5. **Booking, RentalCar, GroundTransport, CheckIn** — networked partner integrations (Expedia/Amadeus/Duffel, Hertz/Enterprise/National, Uber/Lyft). Each is "add endpoint + repo + screen."
6. **Everything else** — AirportMap (Google Maps), Translator, VisaLookup, CurrencyTracker, LocalExperience, TripJournal, Carbon, InFlight, Intelligence, OfflineKit, TravelEssentials, DepartureOptimizer, Subscription (Play Billing).

### How to add a new feature module (the recipe)

Say you're porting **Lounge Finder** (illustrative). Work bottom-up:

1. **Model** — `core/model/Lounge.kt` (domain `data class`) + `core/data/local/LoungeEntity.kt` (`@Entity`) if it persists, + `LoungeDto` in `remote` if networked.
2. **DAO / Api** — `LoungeDao` (`@Dao`, `Flow`-returning) and/or `LoungeApi` (Retrofit `suspend fun`).
3. **Repository** — `core/data/repository/LoungeRepository.kt` (`@Inject`), with the `Secrets.isConfigured` + `MockData` fallback.
4. **DI** — add `@Provides` for the Api in a Hilt module; register the DAO/Entity in `JetDatabase`.
5. **ViewModel** — `feature/lounge/LoungeViewModel.kt` (`@HiltViewModel`, `StateFlow<LoungeUiState>`).
6. **Composable** — `feature/lounge/LoungeScreen.kt` (stateful wrapper + stateless content), themed with `JetCard`/`JetsetterTheme`.
7. **Navigation** — add a `Dest.Lounge` route + `composable(...)` entry in `JetNavHost`.
8. **Surface it** — either a 5th-tab item (rare; the spine is fixed at Home/Itinerary/IRIS/Expenses/More) or, far more commonly, a **row in `MoreScreen`** that navigates to it.
9. **Update** `docs/FEATURE_PARITY.md` (mark wired) and add a unit test under `src/test`.

> **Icons:** find the SF Symbol the iOS screen used and look it up in `docs/SF_SYMBOL_MAP.md` for the Material `Icons.*` replacement. Don't import iOS assets — there are none (§1).

---

## 11. Git Workflow

This `android/` folder is currently a subdirectory of the iOS repo. It will be promoted to the **root** of its own GitHub repo, `DevJ1975/JetSetter_Android`, via the handoff script.

### Branch naming

```
feature/itinerary-room-persistence
feature/iris-claude-streaming
feature/flight-tracker-port
fix/bottom-bar-tint-dark-mode
chore/bump-compose-bom
docs/feature-parity-update
```

Branch off `main`; open a PR; let CI (§9) gate the merge.

### What NOT to commit

The `.gitignore` already covers the important ones — **verify before every commit**:

```gitignore
# Secrets & signing
local.properties          # ← contains SDK path AND API keys. NEVER commit.
*.keystore
*.jks
keystore.properties

# Build output
/build/
/app/build/
.gradle/

# IDE
/.idea/
*.iml
.DS_Store

# Local Android
captures/
.cxx/
```

> The committed template is `local.properties.example` (placeholders only). The real `local.properties` is git-ignored. If you ever see a `sk-ant-…` value in a diff, stop and remove it.

### Before-every-commit checklist

- [ ] Code compiles — locally if you have the SDK, otherwise rely on CI (§9).
- [ ] `./gradlew lint` clean (or new warnings justified).
- [ ] New `@Composable` has a `@Preview`; new ViewModel/repo has a unit test.
- [ ] No network/DB calls inside Composables (§2 rule).
- [ ] No hardcoded API keys; new keys went through `local.properties.example` → `BuildConfig` → `Secrets`.
- [ ] New models that persist are Room `@Entity`s with a migration if the schema changed.
- [ ] `docs/FEATURE_PARITY.md` updated if you moved a feature's status.
- [ ] No leftover `Log.d(...)` in hot paths (prefer a tagged logger; strip debug logs).

### Handoff to the real repo — `push-to-jetsetter-android.sh`

When this scaffold is ready to live on its own, `push-to-jetsetter-android.sh` promotes the `android/` folder to the **root** of `DevJ1975/JetSetter_Android`. Conceptually it:

1. Confirms `local.properties` and other ignored files are **not** staged.
2. Initializes (or reuses) a git remote pointing at `git@github.com:DevJ1975/JetSetter_Android.git`.
3. Pushes the contents of `android/` as the repository root (so `app/`, `gradle/`, `settings.gradle.kts`, this guide, etc. sit at top level — no nested `android/`).

```bash
# from jetsetter-pro/android
./push-to-jetsetter-android.sh        # review the script before first run; it pushes to a real remote
```

> Treat the first push as a one-way door: once `JetSetter_Android` exists, that repo — not this subfolder — is the source of truth for Android. Coordinate before running it.

---

## 12. Glossary

| Term | Meaning |
|---|---|
| **Kotlin** | The primary language for modern Android (the Swift analog). |
| **Jetpack Compose** | Android's declarative UI toolkit (the SwiftUI analog). UI = `@Composable` functions of state. |
| **Material 3** | Google's design system & Compose component library (`androidx.compose.material3`). |
| **Gradle** | The build system. Tasks like `assembleDebug` build the app. Configured in `*.gradle.kts`. |
| **Gradle Kotlin DSL** | Writing Gradle build scripts in Kotlin (`build.gradle.kts`) instead of Groovy. |
| **AGP** | Android Gradle Plugin — the Gradle plugin that knows how to build Android apps. |
| **Version catalog** | `gradle/libs.versions.toml` — the single place all dependency coordinates & versions are declared. |
| **`BuildConfig`** | A class Gradle generates at build time; how compile-time values (incl. API keys) reach Kotlin. |
| **Hilt** | Dependency-injection framework (built on Dagger). `@HiltViewModel`, `@Inject`, `@Module`, `@Provides`. |
| **DI (Dependency Injection)** | Supplying an object's collaborators from outside (the Repository-singleton replacement). |
| **Room** | Jetpack's SQLite ORM. `@Entity`, `@Dao`, `@Database`; DAOs can return `Flow` for reactive reads. |
| **DAO** | Data Access Object — a `@Dao` interface of typed DB queries. |
| **Entity** | A `@Entity data class` mapping to a Room table. |
| **DataStore** | Modern key-value/typed preference storage (the `UserDefaults` analog; replaces `SharedPreferences`). |
| **Retrofit / OkHttp / Moshi** | HTTP client / networking engine / JSON (`@JsonClass`, the `Codable` analog). |
| **Coroutine** | A lightweight, suspendable unit of async work (the `Task`/async analog). |
| **`suspend`** | Marks a function that can pause without blocking a thread; callable from coroutines (≈ `async`). |
| **`viewModelScope`** | A `CoroutineScope` tied to a ViewModel's lifecycle; cancels automatically when cleared. |
| **Flow** | A cold asynchronous stream of values (the Combine `Publisher` analog). |
| **StateFlow** | A hot, always-has-a-value `Flow` for UI state (the `@Published` analog). |
| **`collectAsStateWithLifecycle`** | Collects a `Flow`/`StateFlow` into Compose state, pausing in the background. |
| **`remember` / `rememberSaveable`** | Keep state across recomposition / across recomposition + process death. |
| **Recomposition** | Compose re-invoking Composables when their state changes (the "re-render"). |
| **`Modifier`** | The chainable decorator for size/padding/background/click on a Composable. Order matters. |
| **`sealed class` / `sealed interface`** | A closed type hierarchy (the Swift `enum`-with-associated-values analog); enables exhaustive `when`. |
| **`data class`** | A class with auto `equals`/`hashCode`/`copy`/`toString` (the `struct` analog for models). |
| **WorkManager** | Deferred/guaranteed background work (`CoroutineWorker`) — the `BGTaskScheduler` analog. Drives disruption polling. |
| **`mipmap`** | Resource folders for launcher icons (`mipmap-mdpi … xxxhdpi`, `mipmap-anydpi-v26`). |
| **Adaptive icon** | An Android launcher icon defined as foreground + background layers (the brand-regenerated app icon). |
| **ProGuard / R8** | Code shrinker/obfuscator applied to release builds; rules live in `proguard-rules.pro`. |
| **AVD** | Android Virtual Device — the emulator (the iOS Simulator analog). |
| **Logcat** | The device/emulator log viewer in Android Studio (where `Log.*` output and stack traces appear). |
| **ANR** | "Application Not Responding" — main-thread blocked too long. Why I/O never goes in Composables/Main. |
| **`applicationId`** | The app's unique package identity (`com.jetsetter.pro`) — the iOS Bundle ID analog. |
| **minSdk / targetSdk / compileSdk** | Lowest supported API (26) / API the app targets (35) / API the app compiles against (35). |

---

> **Study order:** Start with §3 (Swift→Kotlin mapping) and §5 (Compose). Then read the **Itinerary** code top-to-bottom against §6 — it's the canonical end-to-end example. §7–§8 unlock once you've added one screen. Keep §10 + `docs/FEATURE_PARITY.md` open while you port. Bookmark §4 for when Studio misbehaves.

*JetSetter Pro — Android Agent Guide · Trainovate Technologies LLC*
*Keep this guide in sync with the scaffold as the port grows. When in doubt, mirror Home/Itinerary.*
