# JetSetter Pro — Learn Swift by Fixing Your Own App

A hands-on guide. Each lesson points you at a real, worth-fixing issue in your
codebase and teaches the Swift concept behind it. **The code is yours to write** —
this gives you the map, the concepts, and hints, then asks you to do the driving.

## How to use this guide

- **One lesson = one git branch.** `git checkout -b lesson-1.1-number-parsing`.
  Commit when it builds and works.
- **Each lesson has:** 🎯 Goal · 📚 Concepts to learn · 📍 Where · 🐞 The problem ·
  🪜 Steps (hints only) · ✅ How to verify · 🌱 Stretch.
- **When stuck:** read the linked Apple docs first, try, *then* ask for an
  explanation of a concept (not for the fix). Good asks: "explain how
  `Dictionary(grouping:)` works," "why does my `guard` not compile?"
- **Tools you'll lean on:** Xcode's live error underlining, `⌘B` to build,
  Option-click a symbol for quick help, and the Swift Testing target already in
  the project.

### Legend
| Tag | Meaning |
|---|---|
| 🟢 | Beginner-friendly — start here |
| 🟡 | Intermediate — needs a concept or two first |
| 🔴 | Advanced — architecture / concurrency |

---

## Module 0 — Orient yourself first

Before any fix, learn the lay of the land. No code yet.

- 🎯 Understand the app's shape: it uses **MVVM** — `Features/<Name>/<Name>View.swift`
  (UI) + `<Name>ViewModel.swift` (logic/state), backed by `Core/Services/*`.
- 📚 Concepts: MVVM, `struct` vs `class`, `@State` / `@Observable` /
  `ObservableObject`, the `body` of a SwiftUI `View`.
- 🪜 Do this: open `Features/CurrencyTracker/` and read the View and ViewModel side
  by side. Trace: where does a number the user types end up? Where is it saved?
  That path (View → ViewModel → Service) repeats everywhere.
- ✅ You're ready when you can explain, out loud, "when I tap Save, which function
  runs and what does it touch?"

---

## Module 1 — Swift foundations (small, self-contained wins) 🟢

### Lesson 1.1 — Parse numbers the way the world types them
- 🎯 Let users in France/Germany/Brazil enter `12,50` without it becoming `nil`.
- 📚 Concepts: **Optionals** (`?`, `guard let`), `String` → number conversion,
  **`NumberFormatter`**, `Locale`. (Search Xcode docs: *NumberFormatter*,
  *Locale.current*.)
- 📍 `Features/ExpenseTracker/ExpenseViewModel.swift:19`; same pattern at
  `Features/CurrencyTracker/CurrencyExpenseViewModel.swift:19,278`.
- 🐞 The problem: the code uses `Double(someString)`, which only understands a `.`
  decimal separator. In comma-decimal locales it returns `nil`, so the amount
  silently becomes 0 / fails.
- 🪜 Steps:
  1. Learn why `Double("12,50")` is `nil` — try both in a Playground or
     `RunCodeSnippet`.
  2. Create a `NumberFormatter`, set `numberStyle = .decimal`. It respects the
     device locale.
  3. Use its `number(from:)` method; handle the optional it returns with `guard let`.
  4. Decide what happens on truly invalid input (empty? show an error? return early?).
- ✅ Verify: switch the simulator to a French locale (Settings → General →
  Language & Region) and enter `12,50`. It should save as 12.5, not fail.
- 🌱 Stretch: write a tiny helper `func parseAmount(_ text: String) -> Double?` and
  reuse it in both files. First taste of **DRY** / shared utilities.

### Lesson 1.2 — Make swipe-to-delete actually work
- 🎯 Let users delete a currency expense by swiping.
- 📚 Concepts: SwiftUI **`List` vs `VStack`**, `ForEach`, the `.onDelete(perform:)`
  modifier, `IndexSet`.
- 📍 `Features/CurrencyTracker/CurrencyExpenseView.swift:234`.
- 🐞 The problem: rows are laid out in a `VStack`. Swipe actions only exist on rows
  inside a `List`.
- 🪜 Steps:
  1. Learn the difference: a `VStack` just stacks views; a `List` gives you rows,
     separators, and swipe actions.
  2. Convert the container to a `List` (or embed the `ForEach` in one). Keep the row
     view the same.
  3. Add `.onDelete { indexSet in ... }` and call a delete method on the ViewModel.
  4. In the ViewModel, remove the item(s) at those indexes, then persist.
- ✅ Verify: swipe a row → Delete → it disappears and stays gone after relaunch.
- 🌱 Stretch: add a confirmation dialog before deleting.

### Lesson 1.3 — Fail safe, not dangerously wrong
- 🎯 Stop unknown airports from silently showing **Japan's** emergency info.
- 📚 Concepts: dictionary lookups returning optionals, the danger of a "default"
  that's real-looking data, empty-state UI.
- 📍 `Features/TravelEssentials/TravelEssentialsView.swift:11`.
- 🐞 The problem: an unknown airport code falls through to a hardcoded Japan entry —
  actively misleading in an emergency.
- 🪜 Steps:
  1. Find where the lookup happens and what it returns when the code isn't found.
  2. Replace the "default to Japan" behavior with an honest empty/unknown state.
  3. Design a small "we don't have info for this location" view.
- ✅ Verify: feed it a made-up code (`"ZZZ"`) → you get the empty state, not Tokyo.

---

## Module 2 — Money & time done right 🟡

### Lesson 2.1 — Never add two currencies together
- 🎯 Fix totals that sum JPY + EUR + USD as one number.
- 📚 Concepts: **`enum`** for currency, **`Dictionary(grouping:by:)`**, `reduce`,
  mapping over collections, and the idea of a "base currency."
- 📍 `Features/ExpenseTracker/ExpenseViewModel.swift:42`; also
  `CurrencyExpenseViewModel.swift:113`, `ExpenseExportView.swift:35`.
- 🐞 The problem: a single `reduce`/`+` adds raw amounts regardless of currency.
- 🪜 Steps:
  1. Decide the correct behavior first: show **per-currency subtotals**, or
     **convert all to one base currency** using `ExchangeRateService`? (Simpler =
     per-currency subtotals. Do that first.)
  2. Learn `Dictionary(grouping: expenses, by: { $0.currency })` — it gives you
     `[Currency: [Expense]]`.
  3. `reduce` each group to a subtotal.
  4. Update the UI to show subtotals (a small `ForEach` over the grouped dictionary).
- ✅ Verify: an expense list with ¥5000 + €40 + $30 shows three lines, not "5070."
- 🌱 Stretch: add a converted grand-total using `ExchangeRateService` — your first
  cross-service call.

### Lesson 2.2 — Show flight times in the airport's timezone
- 🎯 Departure shown in origin's local time, arrival in destination's.
- 📚 Concepts: **`TimeZone`**, `DateFormatter.timeZone`, `Calendar`, and why a `Date`
  has *no* timezone of its own (it's an instant; formatting adds the zone).
- 📍 `Features/FlightTracker/FlightDetailView.swift:21`; alt-flight times in
  `Features/Disruption/DisruptionDashboardView.swift`.
- 🐞 The problem: every time formats in the device's timezone, so an LA→Tokyo flight
  shows wrong wall-clock times.
- 🪜 Steps:
  1. First, understand the concept: `Date` = a point in time. The *displayed* hour
     depends on which `TimeZone` the formatter uses.
  2. Find where each flight's origin/destination timezone lives (or map airport code
     → timezone; check `Core/Utilities/AirportCoordinates.swift`).
  3. Make one `DateFormatter` per zone (or set `.timeZone` before formatting each value).
  4. Append the zone abbreviation so users see e.g. `7:20 AM PST` vs `... JST`.
- ✅ Verify: pick an international flight; departure/arrival read in their local
  zones, not yours.

---

## Module 3 — Persistence & Codable 🟡→🔴

### Lesson 3.1 — When JSON silently eats your data (dates)
- 🎯 Stop the luggage list from vanishing on load.
- 📚 Concepts: **`Codable`**, `JSONEncoder`/`JSONDecoder`, **date encoding/decoding
  strategies** (`.iso8601` vs `.deferredToDate`) — they must match.
- 📍 `Features/LuggageTracker/LuggageViewModel.swift:37`.
- 🐞 The problem: data is written with one date strategy and read with a different
  one, so decoding throws and the code falls back to `[]`.
- 🪜 Steps:
  1. Learn how `Codable` turns structs ↔ JSON, and how a date strategy changes the
     on-disk format.
  2. Find the encode side and the decode side; note the mismatch.
  3. Make them identical. Decide on one strategy (`.iso8601` is a good default)
     everywhere.
  4. **Important habit:** this bug only survived because the decode error was
     swallowed by `try?`. Temporarily print the error so you *see* it fail — then fix it.
- ✅ Verify: add a bag, kill the app, relaunch → it's still there.

### Lesson 3.2 — Two Codable rules fighting each other
- 🎯 Make the packing-list offline cache actually load.
- 📚 Concepts: **`CodingKeys`** vs **`keyEncodingStrategy = .convertToSnakeCase`** —
  using both double-transforms your keys.
- 📍 `Features/PackingList/PackingListViewModel.swift:224`.
- 🪜 Steps: pick *one* mechanism (explicit `CodingKeys` **or** the snake-case
  strategy, not both), make encode/decode symmetric, and again print the error
  before fixing so you learn to read decoding errors.
- ✅ Verify: cache round-trips — save, reload, list appears.

### Lesson 3.3 — One source of truth (fixing the write race) 🔴
- 🎯 Stop hotel bookings from being clobbered by the next itinerary edit.
- 📚 Concepts: **value vs reference types**, why two view models each owning their
  own copy of "the trips" causes lost writes, and the **single-source-of-truth**
  pattern (`@Observable`/`ObservableObject` shared store).
- 📍 `Features/Booking/HotelDetailView.swift:437`; central store
  `Core/Services/TravelStore.swift`.
- 🐞 The problem: different screens read/modify/write the whole trip blob
  independently; last writer wins, earlier changes vanish.
- 🪜 Steps (plan the design before coding — this is architectural):
  1. Learn how SwiftUI shares one observable object across views (environment /
     injection).
  2. Identify every place that writes trips directly to `UserDefaults`.
  3. Route all reads/writes through `TravelStore` so there's exactly one owner.
  4. Have views observe the store rather than holding their own copies.
- ✅ Verify: add a hotel, then edit the itinerary elsewhere — the hotel survives.
- 💡 This is the biggest conceptual leap in the guide. Pair on the design first.

---

## Module 4 — Concurrency & the deadlock 🔴

### Lesson 4.1 — Why the app freezes on "Connect expense account"
- 🎯 Understand and remove a **main-thread deadlock**.
- 📚 Concepts: **threads**, the main thread, **`async`/`await`**, **`@MainActor`**,
  and why `DispatchQueue.main.sync` *from the main thread* deadlocks instantly.
- 📍 `Core/Services/Expense/Providers/OAuthExpenseProvider.swift:270`.
- 🐞 The problem: code already on the main thread calls
  `DispatchQueue.main.sync { ... }` — it waits for the main thread to be free, but
  *it is* the main thread. Frozen forever.
- 🪜 Steps:
  1. First just *understand* it — walk through what `.sync` means. Don't touch code yet.
  2. Learn the modern replacement: mark UI-touching code `@MainActor` and use
     `await` instead of blocking.
  3. Rework the presentation-anchor lookup so it never blocks the thread it's on.
- ✅ Verify: tapping "Connect" opens the OAuth sheet instead of hanging.
- 🌱 Stretch: read about actors and data races — the foundation of modern Swift
  concurrency.

---

## Module 5 — Networking & real integrations 🔴

### Lesson 5.1 — Your first real API call (Expedia region lookup)
- 🎯 Turn destination text into a `region_id` so hotel search actually returns results.
- 📚 Concepts: **`URLSession`** with `async/await`, building a `URLRequest`,
  `Codable` response models, `URLComponents`/query items, error handling with
  `do/catch`.
- 📍 `Features/Booking/BookingViewModel.swift:104,129`; `BookingModel.swift:10`.
- 🪜 Steps:
  1. Learn the request→response→decode loop with one small endpoint (the free
     `WeatherService.swift` / `ExchangeRateService.swift` are great *read-alongs* —
     they already do this well).
  2. Add a "search regions by name" call; decode the results into a `Codable` model.
  3. Feed the resulting `region_id` into the existing hotel search instead of the
     empty destination.
- ✅ Verify: search "Tokyo" → real regions come back → hotel results populate.
- 🌱 Then tackle the other integrations the same way once comfortable: FlightAware
  polling, Amadeus check-in, expense providers (Ramp/Brex/BILL), rental cars. Each is
  the same loop with a different endpoint.

---

## Module 6 — Security basics 🟡

### Lesson 6.1 — Store secrets so they don't leak to backups
- 🎯 Harden Keychain storage and encrypt loyalty numbers.
- 📚 Concepts: the **Keychain**, accessibility classes
  (`kSecAttrAccessibleWhenUnlocked` vs `...ThisDeviceOnly`), why plaintext in
  `UserDefaults` leaks via backups.
- 📍 OAuth tokens: `Core/Services/Expense/Providers/OAuthExpenseProvider.swift:106`.
  Loyalty numbers (plaintext): `Features/.../LoyaltyViewModel.swift:63` — see
  `Core/Utilities/VaultCrypto.swift` for encryption you already have.
- 🪜 Steps: switch token accessibility to `...ThisDeviceOnly`; move loyalty numbers
  off `UserDefaults` and through `VaultCrypto` (study how `DocumentVault` does it).
- ✅ Verify: values still read back correctly after relaunch; nothing sensitive sits
  in plain `UserDefaults`.

---

## Module 7 — Write your first tests 🟢→🟡

### Lesson 7.1 — Prove your fixes with tests
- 🎯 Write unit tests for the logic you fixed (start with Lesson 2.1's currency grouping).
- 📚 Concepts: the **Swift Testing** framework (`@Test`, `#expect`),
  arrange/act/assert, testing pure logic without UI.
- 📍 Existing examples: `JetSetter ProTests/CurrencyMathTests.swift`,
  `TravelProfileEngineTests.swift` — read these first, they're your template.
- 🪜 Steps: add a test that feeds mixed-currency expenses to your grouping function
  and asserts the subtotals. Then one for `parseAmount` from Lesson 1.1.
- ✅ Verify: tests run green in Xcode's Test navigator (`⌘U`).
- 🌱 Stretch: pick any ViewModel and write its first test — 18 of them currently
  have none.

---

## Suggested path

```
Module 0 (orient)
 → 1.1 → 1.2 → 1.3        (Swift basics, quick wins)
 → 2.1 → 2.2             (money & time)
 → 7.1                   (test what you just built)
 → 3.1 → 3.2 → 3.3       (persistence, ending in architecture)
 → 4.1                   (concurrency)
 → 5.1                   (networking)
 → 6.1                   (security)
```

Everything after Module 5.1 (the remaining integrations, plus localization,
accessibility, CI/CD from the full audit) reuses these same skills — once you've
done one API integration and one persistence fix, the rest are variations.

---

## Beyond this guide (from the full audit)

These are real remaining items, but they reuse the skills above. Tackle once the
modules feel comfortable:

- Finish scaffolded features: Local Experience Engine, Document Vault photo
  encryption, in-flight phase detection without GPS, AirportMap indoor navigation,
  "Add to Apple Wallet", Translator retry, OfflineKit auto-caching.
- Wire/verify live integrations: cloud sync (Supabase) for expenses & itinerary,
  IRIS cross-device learning, expense providers, disruption rebooking, FlightAware,
  Uber/Lyft, Amadeus check-in, rental cars, AI/IRIS fallback removal.
- Production readiness: `Secrets.xcconfig` wiring, StoreKit 2 entitlement refresh,
  gating Demo Mode, real Bundle ID/Team, localization, accessibility, CI/CD.

See `AUDIT_REPORT.md` and `docs/EXECUTION-BACKLOG.md` for the exhaustive list.
