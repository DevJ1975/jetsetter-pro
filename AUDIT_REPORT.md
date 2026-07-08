# JetSetter Pro — Feature Swarm Audit

_47 features/services reviewed by parallel agents; every critical/high bug independently re-verified by a skeptic agent._


**Totals:** 47 units · 57 verified high-sev bugs · 146 medium/low bugs · 208 business-logic improvements · 5 claims rejected as false positives

> ✅ **Remediation status (2026-07-08).** This report is a snapshot from the audit pass. The **verified critical + high + medium bugs have since been fixed** on `main` in commits `ff965f1`, `357aec8`, `9ac0790`, `021ce3e`, `c0d461e` (and `878b718`) — e.g. the OAuth main-thread deadlock, flight-time timezones, currency/date parsing, mixed-currency math, in-flight GPS expiry, luggage/packing decoders, DocumentVault emergency numbers, and the IRIS UTC date shift. The 146 unverified + 208 improvements were **not** individually triaged and remain a backlog. Kept as-is for history — do not assume a listed bug is still open without checking the current code.


## Verified Critical Bugs (1)

### [CRITICAL] Expense-Providers — Main-thread deadlock in ASWebAuthenticationSession presentation anchor
- **Where:** `JetSetter Pro/Core/Services/Expense/Providers/OAuthExpenseProvider.swift:270`
- **Problem:** presentationAnchor(for:) is nonisolated and wraps its body in DispatchQueue.main.sync. ASWebAuthenticationSession invokes presentationAnchor on the main thread (its UI callbacks are main-thread). connect() itself runs on the @MainActor. So the runloop that must service main.sync is the very thread that is blocked calling it, producing a classic main.sync-on-main deadlock: the OAuth flow (Ramp/Brex/Divvy) hangs the app the instant connect() is invoked and the anchor is requested. This is normal-use path for every OAuth provider connection.
- **Fix:** Do not use DispatchQueue.main.sync. Since the surrounding provider is @MainActor and the session is presented from the main actor, resolve the anchor synchronously without hopping: mark the method's body to run assuming main thread via MainActor.assumeIsolated { ... } (iOS 17+) or capture the key window when connect() is called and store it, returning it directly. Never block the main thread with .sync from a callback that already runs on main.


## Verified High Bugs (21)

### [HIGH] AirportMap — Layover sheet overwrites the main route's shared state, corrupting the primary wayfinding card and map
- **Where:** `JetSetter Pro/Features/AirportMap/AirportMapViewModel.swift:152`
- **Problem:** LayoverWayfindingSheet is passed the SAME AirportMapViewModel instance (AirportMapView.swift:191) and calculateLayoverRoute() mutates the shared wayfindingRoute, estimatedWalkMinutes, and errorMessage that the main indoor map view also renders. After the user opens the layover sheet and dismisses it, the main map's MapPolyline (bound to viewModel.wayfindingRoute at AirportMapView.swift:72) now draws the arrival→departure layover route instead of the user→gate route, and the wayfinding card's 'N min walk' now shows the layover time. The gate route is never recomputed on dismiss, so the primary UI stays polluted with layover data.
- **Fix:** Give the layover sheet its own state (separate @Published properties like layoverRoute / layoverWalkMinutes, or a dedicated lightweight view model) so calculateLayoverRoute() does not clobber wayfindingRoute/estimatedWalkMinutes. Alternatively recompute the primary route in the sheet's onDisappear.

### [HIGH] Booking — Booking write to itinerary is silently clobbered by the live ItineraryViewModel (data loss)
- **Where:** `JetSetter Pro/Features/Booking/HotelDetailView.swift:437`
- **Problem:** addHotelToItinerary() reads jetsetter_trips from UserDefaults, appends the hotel item, and writes the whole array back directly. But ItineraryView holds an @State ItineraryViewModel that loads trips once in its init (loadTrips) and never re-reads them on appear. If that view model is already alive (Itinerary tab was visited this session), its in-memory trips array does not include the newly added hotel; the next time the user does ANY itinerary mutation (add/delete trip, toggle packing item, calendar sync) ItineraryViewModel.saveTrips() serializes its stale array and overwrites the booking — the added hotel stay disappears permanently. Multiple other subsystems (Home, IRIS, MockData) also write the same key, compounding last-writer-wins races.
- **Fix:** Route the write through the single owner of the store instead of hand-rolling encode/decode. Either inject the shared ItineraryViewModel and call viewModel.addItem(_:to:) (which mutates the in-memory array and saves), or move all jetsetter_trips access behind a single TravelStore that the Itinerary VM observes/reloads. At minimum have ItineraryView reload trips in .onAppear so a direct write can't be silently reverted.

### [HIGH] Booking — Search text is passed as region_id only if pre-resolved; free-text destination is never actually sent
- **Where:** `JetSetter Pro/Features/Booking/BookingViewModel.swift:104`
- **Problem:** The comment on line 102-103 says 'otherwise pass destination as free text', but the code only appends region_id when searchParams.regionID is non-empty, and regionID is always empty (there is no region-lookup step; the TODO at BookingModel.swift:11 is unimplemented). So in the non-mock path every real search is sent with NO destination/region parameter at all — the user's typed destination is discarded and the API receives only dates/currency/occupancy. Real searches cannot honor the destination the user entered.
- **Fix:** Implement the region_id resolution step (Expedia region search by name) before the availability call, or send the free-text destination in whatever parameter the endpoint supports. Until then the search is non-functional against the real API; the 'No hotels found for "destination"' error message (line 72) is also misleading because destination was never queried.

### [HIGH] CurrencyTracker — Swipe-to-delete is a silent no-op (rows are not in a List)
- **Where:** `JetSetter Pro/Features/CurrencyTracker/CurrencyExpenseView.swift:234`
- **Problem:** The expense rows are laid out in a VStack inside a ScrollView (expensesList -> ForEach -> expenseRow, lines 192-197 and 202-241), not inside a List. SwiftUI's .swipeActions modifier only works on rows of a List (or, on iOS 26+, in a container that explicitly opts in). Applied to a plain HStack in a VStack it renders nothing and never fires. The result is that deleteExpense(id:) is unreachable from the UI: users can add expenses but have no way to delete them. There is no other delete affordance anywhere in the view.
- **Fix:** Either wrap the expenses in a List (with .listStyle(.plain) and hidden separators to preserve the card look) so .swipeActions works, or replace swipe-to-delete with an explicit control such as a trailing delete button / context menu on each row that calls vm.deleteExpense(id:).

### [HIGH] CurrencyTracker — updateSummary double-counts destination-currency amounts as home currency when conversion is nil
- **Where:** `JetSetter Pro/Features/CurrencyTracker/CurrencyExpenseViewModel.swift:119`
- **Problem:** totalSpentHome (line 113) uses compactMap { $0.convertedAmount }, so it correctly ignores expenses whose convertedAmount is nil (entered offline before rates loaded). But the per-category and per-day loop (lines 118-123) uses `expense.convertedAmount ?? expense.amount`, substituting the RAW destination-currency amount into a home-currency accumulator. For e.g. a 1500 JPY expense with home=USD, byCategory/byDay get +1500 'USD' while totalSpentHome gets +0. The donut chart and daily-spend totals are therefore inflated and inconsistent with the headline total whenever any expense lacks a conversion (offline entry, unsupported currency, or rate<=0). The chart can even show huge slices while 'total spent' reads 0.
- **Fix:** Make the summary consistent with the total: use `guard let amountInHome = expense.convertedAmount else { continue }` in the loop (skip un-converted expenses everywhere), or compute a live fallback via convertToHome so all three aggregates use the same converted value. Do not mix raw foreign amounts into a home-currency sum.

### [HIGH] CurrencyTracker — Amount parsing uses non-localized Double(String), breaking comma-decimal locales
- **Where:** `JetSetter Pro/Features/CurrencyTracker/CurrencyExpenseViewModel.swift:19`
- **Problem:** convertedAmount does `Double(converterInput)` and AddExpenseSheet does `Double(amount)` (CurrencyExpenseView.swift:278, 283). Double.init(String) only accepts '.' as the decimal separator. With a .decimalPad keyboard in locales that use ',' (most of Europe/Latin America — exactly this app's international audience), typing '12,50' yields nil. The converter silently shows '—' and the Add button stays disabled with no explanation, so affected users literally cannot enter an expense. Conversely, entering '1,500' anywhere parses as nil rather than 1500.
- **Fix:** Parse with a locale-aware NumberFormatter (numberStyle = .decimal) or strip/normalize the grouping and decimal separators from Locale.current before Double(), and apply the same parser in both the converter and AddExpenseSheet.

### [HIGH] DocumentVault — Emergency Mode never shows the passport/document number after relaunch
- **Where:** `JetSetter Pro/Features/DocumentVault/DocumentVaultView.swift:233`
- **Problem:** EmergencyModeView reads passport.docNumberClear directly from the VaultDocument. But DocumentVaultStore.save() sets docNumberClear = nil before persisting (DocumentVaultStore.swift:23), and load() returns documents with docNumberClear == nil. The decrypted clear values live only in vm.decryptedNumbers, which is never passed to EmergencyModeView (the view is constructed as EmergencyModeView(documents: vm.documents) at DocumentVaultView.swift:32). So the passport 'Number:' line only renders for a document that was added in the current session and not yet reloaded. After any app relaunch, the single most safety-critical field in the whole feature (your passport number, offline) silently vanishes. This is the opposite of the emergency use case the feature is built for.
- **Fix:** Pass the decrypted map into EmergencyModeView, e.g. EmergencyModeView(documents: vm.documents, numbers: vm.decryptedNumbers), and render numbers[passport.id] instead of passport.docNumberClear. Alternatively, have EmergencyModeView (or the VM) rehydrate docNumberClear from decryptedNumbers before display.

### [HIGH] ExpenseExport — Partial or total submission failure is reported to the user as success
- **Where:** `JetSetter Pro/Features/ExpenseExport/ExpenseExportView.swift:324`
- **Problem:** OAuth providers (Ramp/Brex/Divvy) never throw on a per-expense failure: OAuthExpenseProvider.submit (OAuthExpenseProvider.swift:122-129) catches each expense's error and records .failed in perExpense, always returning a successful ExportBatchResult. The view only reads result.successCount and shows the green success/checkmark banner (lines 325-326, 341). If 3 of 5 expenses fail, the user sees 'Sent 2 expenses' with no failure indication. Worse, if ALL expenses fail, successCount == 0 and the banner reads 'Sent 0 expenses via Ramp.' with a success checkmark, so a total failure looks like a success. result.failedCount and result.skippedCount are never surfaced anywhere.
- **Fix:** After submit, inspect result.failedCount/skippedCount. If failedCount > 0 set isError true and message like 'Sent X, N failed — try again'. If successCount == 0 treat as an error. Consider surfacing per-expense outcomes so the user knows which items to resubmit.

### [HIGH] ExpenseTracker — Totals and per-category chart sum across mixed currencies without conversion
- **Where:** `JetSetter Pro/Features/ExpenseTracker/ExpenseViewModel.swift:42`
- **Problem:** totalAmount (lines 42-44) and expensesByCategory (lines 55-56) reduce the raw `amount` of every expense regardless of its `currency`. Each Expense carries its own currency (ExpenseModel.swift:71), and the OCR flow explicitly lets the user pick a non-USD currency (ScanReceiptView.swift:179-185, default is UserPreferences.shared.currency). So a receipt of ¥5000 JPY, €40 EUR and $30 USD are added as 5000+40+30 = 5070 and rendered as 'USD 5070.00' in totalSummaryCard (ExpenseTrackerView.swift:71) and '$5070' in the category chart (ExpenseTrackerView.swift:103). Any traveler using more than one currency — the core use case for a travel app — sees a wildly wrong total. This is silent data corruption of the headline number the whole feature exists to show.
- **Fix:** Convert each expense to a single display currency before summing (use the app's existing currency/FX service if one exists, otherwise group totals per-currency). At minimum, group by currency: `Dictionary(grouping: expenses, by: \.currency).mapValues { $0.reduce(0){$0+$1.amount} }` and show per-currency subtotals, or convert to UserPreferences.shared.currency. Do not label a cross-currency sum 'USD'.

### [HIGH] ExpenseTracker — Amount parsing with Double(String) breaks in comma-decimal locales
- **Where:** `JetSetter Pro/Features/ExpenseTracker/ExpenseTrackerView.swift:303`
- **Problem:** AddExpenseView.save() (line 303) and canSave (line 236) parse the amount field with `Double(amount)`, and ScanReceiptView.saveExpense() does the same (ScanReceiptView.swift:256). The field uses a .decimalPad keyboard, which in locales that use a comma decimal separator (most of Europe, Latin America — again, prime travel destinations) presents and accepts '42,50'. `Double("42,50")` returns nil because the failable Double initializer only accepts a period. Result: in those locales the Save button silently stays disabled / does nothing, or if a user types '1,234' meaning 1234 it parses as nil. The user cannot log an expense at all.
- **Fix:** Parse with a locale-aware NumberFormatter (numberStyle = .decimal) instead of Double(String), or normalize the separator before Double(). Apply the same fix in ScanReceiptView.saveExpense() (line 256) and in the confirmedAmount prefill/validation.

### [HIGH] FlightTracker — All flight times displayed in device-local timezone instead of airport-local time
- **Where:** `JetSetter Pro/Features/FlightTracker/FlightDetailView.swift:21`
- **Problem:** `timeFormatter` is created with no `timeZone` set, so it defaults to the device's current timezone. AeroAPI returns scheduled/estimated/actual times as UTC Dates, and the app knows each airport's IANA zone (`Airport.timeZone`, lines 162-164 of FlightModel.swift). Every time shown in the timing card (departs/arrives at lines 415/426) and the check-in departure label (line 69) is rendered in whatever timezone the phone is in, NOT the origin/destination local time. A traveler in New York looking at an LAX departure will see the wrong clock time, and while abroad every time is wrong. This is a core-correctness defect for a flight tracker.
- **Fix:** Use two formatters (or set `timeZone` per call): render departure times with `flight.origin.timeZone` and arrival times with `flight.destination.timeZone`, falling back to `.current` only when the zone is unknown. e.g. `let f = DateFormatter(); f.timeStyle = .short; f.timeZone = flight.origin.timeZone ?? .current`. Also append a zone abbreviation so users know which local time they're seeing.

### [HIGH] InFlight — hasGPSFix never expires — stale position/speed shown indefinitely after signal loss
- **Where:** `JetSetter Pro/Core/Services/InFlightTrackingService.swift:357`
- **Problem:** The InFlightSnapshot doc explicitly promises hasGPSFix is 'True when CLLocationManager has a recent fix (< 30s old)' (line 26). In practice hasGPSFix is set to true on the first location update (line 357) and is NEVER reset to false. lastLocationAt is stored (line 358) but read nowhere. On a real flight GPS drops out constantly (cabin, wing shadow, banking). Once locked, InFlightView.routeMap keeps rendering the frozen liveCoordinate (line 235) and the stats grid keeps showing the last groundSpeed/heading as if live, and the GPS card keeps saying 'GPS LOCKED' — actively misleading the traveler about their position for the rest of the flight.
- **Fix:** Expire the fix based on lastLocationAt. Either check age at read time (a computed property: hasGPSFix = Date().timeIntervalSince(lastLocationAt) < 30) or run a lightweight timer that flips snapshot.hasGPSFix=false and clears coordinate/groundSpeed when lastLocationAt is older than ~30s. Also honor CLLocation.horizontalAccuracy — reject updates with accuracy < 0 or absurdly large values before setting the fix.

### [HIGH] LuggageTracker — Date-strategy mismatch silently wipes the entire bag list on load
- **Where:** `JetSetter Pro/Features/LuggageTracker/LuggageViewModel.swift:37`
- **Problem:** MockDataService seeds and activates bags with an encoder configured `dateEncodingStrategy = .iso8601` (MockDataService.swift:46-47 and :711-712), writing dates as ISO-8601 strings under the shared key `jetsetter_bags`. LuggageViewModel.loadBags() decodes with a plain `JSONDecoder()` whose default strategy (.deferredToDate) expects a numeric Double for Date. Every seeded/active Bag has date fields (`lastChecked`) and BagScanEvent.timestamp values, so decoding throws a type-mismatch. The catch on line 38-40 swallows the error and sets `bags = []`, so the demo/seeded bags never appear and the user sees the empty state. This also fires on the `.jetSetterBagsActivated` reload after check-in (View line 77), so completing check-in makes the bag list vanish instead of showing active tracking.
- **Fix:** Use a decoder configured with the matching strategy in loadBags(): `let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; bags = try decoder.decode([Bag].self, from: data)`. Correspondingly, saveBags() should encode with `.iso8601` so round-tripping stays consistent with MockDataService. Also, do not overwrite `bags` with `[]` on decode failure — log/keep the current in-memory list to avoid silent data loss.

### [HIGH] PackingList — Local cache never decodes: snake_case strategy conflicts with explicit snake_case CodingKeys
- **Where:** `JetSetter Pro/Features/PackingList/PackingListViewModel.swift:224`
- **Problem:** saveLocally sets encoder.keyEncodingStrategy = .convertToSnakeCase (line 226) and loadLocally sets decoder.keyDecodingStrategy = .convertFromSnakeCase (line 237). But SmartPackingItem already declares explicit CodingKeys with snake_case raw values (is_packed, is_custom) and PackingListResult declares trip_id/generated_at. On decode, .convertFromSnakeCase transforms incoming JSON key 'is_packed' into 'isPacked' before matching, but the only CodingKey present has stringValue 'is_packed' so the lookup fails and decoding throws. Because loadLocally uses try? and returns nil, the failure is silent. Net effect: the offline/local fallback in load() (line 49) always yields nil, so signed-out/offline users see an empty Generate prompt even though a list was cached moments earlier.
- **Fix:** Remove both key strategies (the explicit CodingKeys already produce correct snake_case on disk): drop encoder.keyEncodingStrategy = .convertToSnakeCase and decoder.keyDecodingStrategy = .convertFromSnakeCase, keeping only the .iso8601 date strategies. Alternatively remove the explicit CodingKeys and rely solely on the strategies, but do not mix both.

### [HIGH] Translator — Re-translating identical text/language leaves the spinner stuck forever
- **Where:** `JetSetter Pro/Features/Translator/TranslatorView.swift:257`
- **Problem:** triggerTranslation sets isTranslating = true and assigns a new TranslationSession.Configuration. .translationTask only invokes its closure when the configuration value changes (Configuration is Equatable on source/target). If the user translates the same target language twice in a row — e.g. taps Translate again after clearing/retrying, or the camera scans text with the same target already set — the new Configuration equals the previous one, so translationTask does NOT re-fire. runTranslation never runs, isTranslating stays true, and the ProgressView spins indefinitely while no translation happens. Editing source text then re-tapping Translate to the same language reproduces this: the visible result is stale and the spinner hangs.
- **Fix:** Call translationConfig?.invalidate() before reassigning, or force a config-identity change. Idiomatic pattern: if let config = translationConfig { config.invalidate() } else { translationConfig = .init(source: nil, target: targetLanguage) }. Alternatively re-run against the same session by keeping the session and calling translate again rather than relying solely on config-change to trigger.

### [HIGH] TravelEssentials — Airport-code and mismatched destinations silently fall back to Japan
- **Where:** `JetSetter Pro/Features/TravelEssentials/TravelEssentialsView.swift:11`
- **Problem:** The initial country is TravelEssentialsData.find(query: nextTripDestination() ?? "") ?? TravelEssentialsData.countries.first!. countries.first is Japan (line 53 of TravelEssentialsData). Real trip destinations in this app are stored as airport codes ("ATL") or city strings ("Atlanta, GA", "Tokyo, Japan") — verified in DemoSeeder.swift and MockDataService.swift. find() only matches on country id/name or substring, so "ATL", "Atlanta, GA", or any US city returns nil and the screen silently defaults to Japan. A traveler to the US/anywhere-not-name-matchable is shown Japan's emergency numbers (110/119), tipping, plugs and water advice — dangerous wrong data presented as authoritative.
- **Fix:** Map airport codes and city strings to countries (e.g. reuse the airport/city→country tables already in the codebase, or parse the trailing country token after the comma). When no country can be resolved, do NOT default to an arbitrary country — show a neutral 'Pick your destination' empty state so the user is never shown wrong emergency info.

### [HIGH] TravelWallet — "Add to Apple Wallet" for non-boarding-pass detail path silently no-ops (no observer)
- **Where:** `JetSetter Pro/Features/TravelWallet/TravelWalletView.swift:620`
- **Problem:** In WalletItemDetailView.addToAppleWallet(), when a valid PKPass is decoded and not already in the library, the code posts NSNotification.Name("AddPKPassToWallet") and relies on some UIKit layer to present PKAddPassesViewController. A project-wide grep shows NOTHING observes "AddPKPassToWallet". So the user taps "Add to Apple Wallet", pkPassAddResult stays nil (no feedback), and the pass is never added. The user sees no error and nothing happens.
- **Fix:** Replace the NotificationCenter.post with a direct call to the existing PassKitService.presentAddPass(pass) (which BoardingPassCard already uses at TravelWalletView-adjacent BoardingPassDetailView.swift:351), or register an observer for "AddPKPassToWallet" that presents PKAddPassesViewController. Also set pkPassAddResult on the not-added branch so the user gets feedback.

### [HIGH] IRIS-Core — AddTripTool parses trip dates as UTC midnight but displays/stores them for local time, shifting dates by a day
- **Where:** `JetSetter Pro/Core/Services/IRIS/IRISActionTools.swift:176`
- **Problem:** AddTripTool.parseDate first tries ISO8601DateFormatter with .withFullDate, which parses a 'yyyy-MM-dd' string to midnight UTC. For any valid yyyy-MM-dd this ISO path always succeeds, so the local-time DateFormatter fallback is never reached. The resulting Date is then formatted with a local DateFormatter (df.dateStyle=.medium, lines 161-162) and stored via TravelStore.appendTrip. For users in negative-UTC offsets (all of the Americas), 2026-08-15T00:00Z renders as Aug 14 locally, so 'add a trip starting Aug 15' is confirmed and saved as Aug 14. SearchRentalCarsTool and DisruptionTool reuse this same parseDate, so their date handling is off by a day too, and it also skews the trigger windows that compare against startDate.
- **Fix:** Parse yyyy-MM-dd in the user's calendar/timezone: drop the ISO .withFullDate branch and use a DateFormatter with dateFormat 'yyyy-MM-dd', locale en_US_POSIX, and timeZone = Calendar.current.timeZone. Keep parsing and display in the same timezone so the confirmed/saved date matches what the user said.

### [HIGH] Expense-Providers — OAuth tokens and API secrets stored in Keychain without device-only/no-backup accessibility
- **Where:** `JetSetter Pro/Core/Services/Expense/Providers/OAuthExpenseProvider.swift:106`
- **Problem:** KeychainCredentials.store defaults accessibility to nil (KeychainCredentials.swift:30), meaning the item gets the Keychain default kSecAttrAccessibleWhenUnlocked. Every credential write in this feature omits the accessibility argument: OAuthExpenseProvider.connect (line 106) and submit (line 118) store OAuthTokens (access + refresh tokens), and ExpensifyProvider.saveCredentials (ExpensifyProvider.swift:58) stores the partnerUserSecret. kSecAttrAccessibleWhenUnlocked items are included in encrypted device backups and migrate to a new device on restore. The enum even defines .whenUnlockedThisDeviceOnly ('never migrated to a new device or iCloud Keychain — appropriate for session tokens') but nothing ever passes it, so long-lived financial-system OAuth refresh tokens and Expensify secrets leak into backups and cross-device restores.
- **Fix:** Pass accessibility: .whenUnlockedThisDeviceOnly at all three store call sites (OAuth connect/submit and Expensify saveCredentials), or make .whenUnlockedThisDeviceOnly the default in store(). Ensure the option is also applied on the SecItemUpdate path (it currently is, line 39) so re-writes keep the stricter class.

### [HIGH] Disruption-Services — rebookingUrl is built from the Amadeus offer id, which is not a valid bookable URL
- **Where:** `JetSetter Pro/Core/Services/DisruptionResponseEngine.swift:169`
- **Problem:** mapAlternativeFlight sets bookingToken = offer.id (line 282), and handleDisruption builds `https://www.amadeus.com/offers/\(token)`. Amadeus flight-offer IDs are ephemeral shopping identifiers (valid only within the same shopping session and typically expiring within minutes); amadeus.com/offers/<id> is not a real deep-link and will 404. The user taps a rebook CTA that leads nowhere. Combined with checkRebookingEligibility failing open to `true`, the CTA is shown aggressively but is non-functional.
- **Fix:** Either route rebooking through the Duffel proxy (which actually holds a bookable order) to produce a real change/booking link, or drop rebookingUrl and instead pass the alternative offer into the in-app booking flow where a fresh Flight Offers Price + Create Order call can be made. Do not synthesize a fake amadeus.com URL.

### [HIGH] Flight-Services — Phase detection depends on GPS ground speed that is unavailable in airplane mode — taxi/takeoff/landing transitions never fire
- **Where:** `JetSetter Pro/Core/Services/InFlightTrackingService.swift:279`
- **Problem:** The parked→taxi (line 279, speed > 2.5), taxi→takeoffRoll (line 282, speed > 22), finalApproach→landing (line 300, speed > 22) and landing→arrived (line 303, speed < 8) transitions all key off snapshot.groundSpeedMps, which is ONLY populated by CLLocation (line 355). The file header advertises the feature 'works in airplane mode for altitude + acceleration; GPS lights up when the user has a window seat.' In airplane mode / aisle seat there is no GPS, so groundSpeedMps stays 0 forever: the phase machine can never leave .parked, and the takeoff/landing chimes and loved-ones prompts (handlePhaseTransition, lines 320/325) never trigger — the core feature silently no-ops for most real flyers. The accelMagnitudeAverage the accelerometer computes (line 255) is collected but never consulted in recomputePhase.
- **Fix:** Drive taxi/takeoff detection from the sensors that actually work offline: use accelMagnitudeAverage (sustained forward accel) plus vertical-speed/altitude climb to detect takeoff, and altitude falling + leveling to detect landing/arrival, treating GPS speed as an optional refinement rather than a required gate.


## Verified Medium Bugs (31)

### [MEDIUM] AirportMap — startTracking() is never called — pedometer and heading updates never start, live-pace ETA is dead code
- **Where:** `JetSetter Pro/Features/AirportMap/AirportMapViewModel.swift:68`
- **Problem:** startTracking() (which calls startUpdatingHeading() and startPedometer()) is defined but invoked nowhere in the codebase (verified via grep: only the definition exists). AirportMapView.onAppear only calls requestLocationPermission(), and location updates are started separately inside locationManagerDidChangeAuthorization. Consequences: (1) the pedometer never starts, so startPedometer/updateWalkEstimateFromPedometer never run and the entire 'live pedometer pace' feature is dead — estimatedWalkMinutes always comes from MapKit expectedTravelTime; (2) heading updates never start, so the map compass/orientation feature is inert; (3) onDisappear still calls stopTracking(), which calls pedometer.stopUpdates() on a pedometer that was never started. This directly contradicts the feature's advertised 'indoor positioning active' behavior.
- **Fix:** Call viewModel.startTracking() in AirportMapView.onAppear (after requesting permission, or in locationManagerDidChangeAuthorization once authorized) instead of relying on the delegate's manager.startUpdatingLocation(). Consolidate location start into startTracking() so heading + pedometer + location all begin together, and only call it when authorization is granted.

### [MEDIUM] Assistant — In-progress trips are excluded from assistant context
- **Where:** `JetSetter Pro/Features/Assistant/AssistantViewModel.swift:105`
- **Problem:** buildSystemPrompt() filters trips with `$0.startDate >= today` and takes the earliest. A trip the user is CURRENTLY on (started before today, ends in the future) has startDate < today and is silently dropped. So the exact user who most needs contextual help — someone actively traveling — gets NO trip context injected, and if they also have a future trip, the assistant talks about the wrong (later) trip instead of the current one.
- **Fix:** Filter on the trip still being relevant, e.g. `$0.endDate >= today`, and prefer a trip whose date range contains today. Example: pick `trips.first { $0.startDate <= today && $0.endDate >= today }` (in-progress) else the earliest with `startDate >= today`.

### [MEDIUM] DepartureOptimizer — Rideshare buttons ignore the deep link they build and always open a generic web page
- **Where:** `JetSetter Pro/Features/DepartureOptimizer/DepartureOptimizerView.swift:324`
- **Problem:** rideshareButton receives a fully-built deep-link URL (uberURL()/lyftURL() at lines 312-313 which encode pickup=my_location, dropoff coordinates and nickname), but the button action at lines 324-326 discards it and unconditionally opens https://m.uber.com / https://ride.lyft.com with no trip pre-filled. The card copy at line 307 promises "your trip pre-filled", which never happens. Also uberURL()/lyftURL() are dead code aside from being passed in and dropped, and the guard in them (nil when location/dest missing) never disables the button — a user with no location still gets a bare web page.
- **Fix:** In the button action, prefer the passed-in `url` (native scheme) and fall back to the provider mobile-web URL only if the app isn't installed; or at minimum append the pickup/dropoff query params to the web URLs so the promise of a pre-filled trip holds. Disable the button when url == nil (no location).

### [MEDIUM] Disruption — Alternative flight times rendered in device timezone, not the airport's
- **Where:** `JetSetter Pro/Features/Disruption/DisruptionDashboardView.swift`
- **Problem:** AlternativeFlightCard.timeFmt is an HH:mm DateFormatter with no timeZone set, so it formats departure/arrival Dates in the *device's* local timezone. The stored Dates are absolute instants for flights whose origin/destination are in other timezones (sample is SFO->NRT). A user in New York looking at an SFO departure, or anyone in a different zone than the flight, will see a wrong-looking clock time. FlightSnapshot.scheduledDeparture has the same problem wherever it is displayed. This is a classic flight-app timezone defect that users will absolutely hit on international routes.
- **Fix:** Store or carry an IANA timezone per airport (origin/destination) and set timeFmt.timeZone accordingly before formatting each end of the segment (departure uses origin tz, arrival uses destination tz), and label the zone. At minimum append the timezone abbreviation so the displayed time is unambiguous. Do not format cross-timezone flight instants with the default device timezone.

### [MEDIUM] ExpenseExport — Selected total sums mixed currencies and mislabels the result
- **Where:** `JetSetter Pro/Features/ExpenseExport/ExpenseExportView.swift:35`
- **Problem:** totalSelected (lines 35-37) does a raw numeric sum of expense.amount across all selected expenses regardless of currency, then the summary card (line 116) labels it with selectedExpenses.first?.currency. Travel expenses are exactly the case where a user has mixed currencies (e.g. USD flights + EUR hotel + JPY meals). The 'TOTAL' shown adds 100 USD + 100 EUR = '200 USD', which is meaningless and understates/overstates the real reimbursement. The same flaw exists in the PDF summary (PDFExpenseReportRenderer.swift:96-108) and the email body (EmailPDFProvider.swift:105-118).
- **Fix:** Group by currency and either show per-currency subtotals (e.g. 'USD 120.00 · EUR 80.00') or convert to a single base currency using a known rate before summing. At minimum, when more than one currency is present, avoid presenting a single summed figure under one currency label.

### [MEDIUM] FlightBoard — User flight can appear as "ON TIME" days before departure, indistinguishable from same-day flights
- **Where:** `JetSetter Pro/Features/FlightBoard/FlightBoardData.swift:50`
- **Problem:** loadUserFlightRow pulls the *next upcoming* flight (filter startDate > now, sorted ascending) with no upper time bound. minutesAway falls into the `default` case for anything >= 45 min out, so a flight 7 days away is labelled `.onTime`. The scheduledTime is formatted as bare `HH:mm` (line 47/62) with no date, so a flight departing next Tuesday at 18:25 renders identically to a same-day 18:25 departure, sitting at the top of a 'LIVE' departures board alongside sample flights that are all within ~5 hours of now. Users will read it as 'my flight boards today at 18:25' and potentially rush to the airport.
- **Fix:** Only surface the user flight on the board when it is actually today / within the board's realistic horizon (e.g. `Calendar.current.isDateInToday(next.startDate)` or minutesAway < ~360). Otherwise omit it (return nil). If you do keep far-future flights, append the date (e.g. 'JUL 12 18:25') or a relative marker so it is not confused with today's departures.

### [MEDIUM] GroundTransport — uber_booked marker stored as dictionary but read as Bool — IRIS suppression never fires
- **Where:** `JetSetter Pro/Features/GroundTransport/GroundTransportViewModel.swift:327`
- **Problem:** persistBookingMarker writes a [String: Any] payload to UserDefaults key "uber_booked". But IRISTriggers.evaluateRideToAirport reads that same key with UserDefaults.standard.bool(forKey: "uber_booked") (IRISTriggers.swift:254). UserDefaults.bool(forKey:) returns false for any non-numeric/non-bool value (a dictionary), so the flag is always false. The intended behavior — suppress the "book a ride to the airport" IRIS suggestion once the user has already booked a ride — silently never works. The comment at VM line 257 explicitly claims other parts of the app (Home, IRIS) can detect the booked ride via this marker.
- **Fix:** Standardize the marker type across both sides. Either write a Bool sentinel alongside the payload (e.g. UserDefaults.standard.set(true, forKey: "uber_booked") plus a separate key like "uber_booked_details" for the dictionary), or have IRISTriggers check object(forKey:) != nil instead of bool(forKey:). cancelBookedRide already removes the key, so once the write type is fixed the round-trip will be consistent.

### [MEDIUM] GroundTransport — Booking marker is never persisted in live (non-mock) builds
- **Where:** `JetSetter Pro/Features/GroundTransport/GroundTransportViewModel.swift:261`
- **Problem:** book(option:) returns early for live builds (if !MockDataService.isEnabled { set externalWebURL; return }) at lines 261-268, before ever reaching persistBookingMarker(for:) at line 308. persistBookingMarker (and setting bookedRide) only runs in the mock/demo path. So in a real shipped build the "uber_booked" marker is never written at all, meaning Home/IRIS can never learn a ride was booked, and cancelBookedRide clears a key that was never set. Even if bug #1 is fixed, the signal is still dead in production.
- **Fix:** Write the booking marker regardless of build mode. In the live branch, after presenting externalWebURL, still persist a lightweight marker (provider + timestamp) so IRIS/Home suppression logic works in production. Consider a shared helper so both branches persist consistently.

### [MEDIUM] GroundTransport — Uber/Lyft trip duration mislabeled and displayed as time-to-pickup ("min away")
- **Where:** `JetSetter Pro/Features/GroundTransport/GroundTransportModel.swift:93`
- **Problem:** UberPriceEstimate.estimatedPickupMinutes (Model:93) maps Uber's `duration` field to minutes. In the Uber /estimates/price response `duration` is the estimated TRIP duration (pickup-to-dropoff travel time), not the ETA for a driver to reach the rider. The same mistake exists for Lyft: LyftCostEstimate.estimatedPickupMinutes (Model:120) uses estimatedDurationSeconds, which is also the trip travel time, not pickup ETA. The UI then renders this as "\(option.estimatedMinutes) min away" (GroundTransportView.swift:254), telling the user a driver is e.g. "27 min away" when that is actually a 27-minute trip. For an airport-transfer app this materially misleads users about when their ride arrives.
- **Fix:** Pickup ETA comes from a separate endpoint (Uber /estimates/time, Lyft eta), not the price/cost estimate. Either fetch the ETA endpoint and populate estimatedMinutes from it, or relabel the field/UI to "trip time" (e.g. "~27 min trip") so the number matches its true meaning. Do not present trip duration as pickup ETA.

### [MEDIUM] IRIS-Feature — send() has no re-entrancy guard — concurrent calls corrupt streaming/isResponding state
- **Where:** `JetSetter Pro/Features/IRIS/IRISChatViewModel.swift:28`
- **Problem:** send(_:) only guards against empty text (line 30), not against being called while a response is already in flight. It can be invoked concurrently from three paths: the send button (disabled while responding, OK), TextField.onSubmit in IRISChatView.swift:266 (NOT gated by canSend, and the TextField is never disabled during a response), and the voice loop via onUtterance in IRISVoiceController.swift:235. If a second send() starts before the first finishes, both mutate streamingContent/isResponding on the shared VM, and the first call's `defer` block (lines 36-39) sets isResponding=false and clears streamingContent while the second stream is still yielding — producing a dropped/garbled bubble and a UI that shows 'not responding' mid-stream. The two IRISAgentService streams also race on the same underlying LanguageModelSession.
- **Fix:** Add an early guard at the top of send(): `guard !isResponding else { return nil }`. Also disable the TextField (or gate onSubmit on canSend) while vm.isResponding so a second submit can't be dispatched.

### [MEDIUM] InFlight — Phase state machine can never leave 'parked' without GPS ground speed — breaks in airplane mode
- **Where:** `JetSetter Pro/Core/Services/InFlightTrackingService.swift:279`
- **Problem:** recomputePhase gates parked->taxi on speed > 2.5 and taxi->takeoffRoll on speed > 22 (lines 279, 282), where snapshot.groundSpeedMps only ever gets a nonzero value from a GPS location update (line 355). In airplane mode — which the UI explicitly advertises as supported ('accurate even in airplane mode', InFlightView.swift:371) — GPS is off, so groundSpeedMps stays 0 forever, the phase is stuck at .parked, and the entire milestone pipeline (takeoff/landing audio chime, promptLovedOnes, FlightLiveActivityService departure/end at lines 320-329) silently never fires even as the barometer clearly shows a climb. The 'text your loved ones on takeoff/landing' feature is effectively dead for any airplane-mode user.
- **Fix:** Make the climb/descent branches altitude+vertical-speed driven so they work without GPS. E.g. allow parked->climb (or a takeoff transition) when verticalSpeedMps > ~2.5 m/s sustained and altitudeMeters rises past a threshold, using the accelMagnitudeAverage as a corroborating signal, so the barometer alone can drive takeoff/landing detection when GPS is unavailable.

### [MEDIUM] Itinerary — durationInDays undercounts trip length by one day and is time-sensitive
- **Where:** `JetSetter Pro/Features/Itinerary/ItineraryModel.swift:60`
- **Problem:** durationInDays computes Calendar.dateComponents([.day], from: startDate, to: endDate).day. Because trips are created with startDate = Date() (current time) and endDate = start + 7 days (AddTripView.swift:376-377), and DatePicker with .date still carries a time-of-day, the day delta is inclusive-exclusive. A Jul 1–Jul 7 trip yields 6, not 7. This value is displayed directly to users as the 'DAYS' stat in TripJournalView (lines 91, 151, 315) and drives forecastDays in PackingListService.swift:95, so a 7-day trip shows '6 DAYS' and generates one day too few of packing forecast. Worse, because the components include time, two trips over the same calendar span can report different day counts depending on the hour the picker was left at (e.g. start 10am → end 9am next-week rounds down).
- **Fix:** Normalize to whole calendar days and count inclusively: `let s = Calendar.current.startOfDay(for: startDate); let e = Calendar.current.startOfDay(for: endDate); return (Calendar.current.dateComponents([.day], from: s, to: e).day ?? 0) + 1`. This makes a same-day trip = 1 day and a Jul 1–Jul 7 trip = 7 days, independent of time-of-day.

### [MEDIUM] LoyaltyVault — Sensitive loyalty account data stored unencrypted in UserDefaults
- **Where:** `JetSetter Pro/Features/LoyaltyVault/LoyaltyViewModel.swift:63`
- **Problem:** All loyalty accounts — including member/frequent-flyer numbers, tiers and notes — are JSON-encoded and written to UserDefaults.standard.set(data, forKey: storageKey). UserDefaults is stored in an unprotected plist and is included in unencrypted device backups and iTunes/Finder backups. Frequent-flyer and hotel loyalty numbers are PII commonly used as account credentials (they can be used to redeem/steal points), and the free-form `notes` field invites users to store even more sensitive data. The feature is literally branded a 'Vault' (LoyaltyVaultView / 'Miles & Loyalty'), setting an expectation of secure storage that plaintext UserDefaults does not meet.
- **Fix:** Persist the encoded blob in the Keychain (kSecClassGenericPassword with kSecAttrAccessibleWhenUnlockedThisDeviceOnly to keep it off backups), matching whatever the app's DocumentVault uses. At minimum encrypt the JSON before writing and set the file/data as not-backed-up. Keep the same encode/decode path but route the bytes through Keychain instead of UserDefaults.

### [MEDIUM] OfflineKit — Cache marked 'Expired' after 24h even though offline data is still valid and usable
- **Where:** `JetSetter Pro/Core/Services/OfflineKitService.swift:179`
- **Problem:** expiresAt is hard-coded to now + 24h and OfflineTripSnapshot.isFresh (line 28) returns expiresAt > Date(). Because caching is only ever triggered manually from OfflineKitView (there is no automatic refresher — see below), a user who caches their kit the recommended way before a flight will see the whole grid flip to the orange 'Expired' state and the 'Fresh until' tile turn to 'Expired' just 24h later, even though the cached JSON is still perfectly readable offline. Users routinely prep an offline kit 2-3 days before departure, so this fires in the exact primary use case. The persisted data is not deleted, so the UI is misleading rather than functionally broken.
- **Fix:** Base freshness on the trip window rather than a fixed 24h TTL: keep the snapshot considered 'fresh' until (e.g.) trip.endDate, or compute expiresAt as min(now+someTTL, endDate) and treat weather/FX as the only truly perishable parts. At minimum, distinguish 'stale (data may be outdated)' from 'unusable', and never present a cached-but-usable kit as 'Expired'.

### [MEDIUM] OfflineKit — Advertised automatic caching '48h before' window never runs — offline kit is silently empty unless user opens this screen and taps Refresh
- **Where:** `JetSetter Pro/Core/Services/OfflineKitService.swift:101`
- **Problem:** The doc comment on cache() states it is 'Designed to be called ... automatically when a trip enters its 48h-before window.' A repo-wide search shows the only caller of OfflineKitService.cache is OfflineKitView.refresh (OfflineKitView.swift:243). There is no background/scheduled caller. Result: unless the user manually navigates to this screen and taps 'Refresh Offline Kit', OfflineTripSnapshot never exists, and when they lose connectivity in flight/abroad they have nothing cached — the exact scenario the feature exists to prevent. The feature silently no-ops for anyone who doesn't discover the manual button.
- **Fix:** Add a scheduled/lifecycle trigger (BGAppRefreshTask or an app-foreground check) that calls cache() when the soonest upcoming trip enters its pre-departure window, or invoke it from the existing DisruptionMonitor/notification pipeline. Until then, correct the comment so it doesn't imply behavior that doesn't exist.

### [MEDIUM] RentalCar — Booking confirmation copy lies about the action it performs
- **Where:** `JetSetter Pro/Features/RentalCar/RentalCarDetailView.swift:396`
- **Problem:** The confirmation sheet tells the user: "Tapping \"Continue to <Provider>\" will open the <Provider> app (or App Store if not installed) to complete your booking." and the button label is "Continue to <Provider>". But onConfirm() calls vm.book(vehicle:), which (RentalCarViewModel.book, line 144-146) only sets externalWebURL = vehicle.provider.websiteURL, opening the generic provider homepage (e.g. https://www.enterprise.com) inside an in-app web view. It does NOT open the provider app or App Store, and it does NOT carry the location/dates/vehicle selection — the user lands on a bare homepage and must re-enter everything. The comment on websiteURL (RentalCarModel.swift:55-56) confirms the §7.7 in-app-only rule, so the app text is stale and misleading.
- **Fix:** Rewrite the confirmation copy and button to reflect reality, e.g. "Continue on <Provider>.com" / "...will open <Provider>'s booking site inside JetSetter Pro." Ideally pass a deep-linked booking URL (location + dates) instead of the bare homepage so the user isn't dropped on a blank search.

### [MEDIUM] Settings — Disabling Flight Alerts cancels ALL notifications (trip + expense reminders too)
- **Where:** `JetSetter Pro/Features/Settings/SettingsView.swift:389`
- **Problem:** The Flight Alerts toggle's onChange calls notifications.cancelAllNotifications() when turned off. Per NotificationManager.cancelAllNotifications() (NotificationManager.swift:310-312) this calls removeAllPendingNotificationRequests() AND removeAllDeliveredNotifications() — it wipes every scheduled notification, including Trip Reminders and the Weekly Expense Review, not just flight alerts. Worse, re-enabling the toggle does nothing (no re-schedule path exists; grep shows no caller of any flight/trip scheduling outside NotificationManager). So a user who toggles Flight Alerts off then back on silently loses trip reminders and weekly expense reminders permanently until they toggle those individually.
- **Fix:** Cancel only flight-alert notifications here (add a NotificationManager.cancelFlightAlerts() that removes just the flight-alert identifiers) instead of cancelAllNotifications(). On re-enable, re-schedule flight alerts for upcoming trips. Do not use the global cancel-all from a per-category toggle.

### [MEDIUM] Settings — Delete Account treats server failure as success and never surfaces the error
- **Where:** `JetSetter Pro/Features/Settings/SettingsView.swift:842`
- **Problem:** deleteAccount() catches a failed SupabaseService.deleteAccount() by only setting authError, then unconditionally runs clearLocalData(), sets signedInUser = nil and email = "". Two problems: (1) authError is only rendered in the signed-OUT auth form (line 534-538); after this runs the view flips to signed-out but authError is set, so the message may flash oddly or be lost, and while signed-in there is no error UI at all — the user is told nothing when the server delete fails. (2) The account may still exist server-side (synced trips/expenses in the cloud) while the app clears local state and signs out, giving the false impression the account was deleted. This is a privacy/compliance issue for a 'permanently deletes all synced data' promise (see alert copy at line 86).
- **Fix:** On failure, do NOT proceed to sign-out/clear as if successful. Keep the user signed in, show a dedicated error alert ('Account deletion failed, please try again'), and only wipe local + sign out after the server confirms deletion. If a local wipe is still desired on failure for privacy, make that an explicit, separate user choice rather than silently masking a failed server delete.

### [MEDIUM] Subscription — PremiumGate only blurs UI — gated views still fully instantiate and run their side effects/network calls
- **Where:** `JetSetter Pro/Features/Subscription/PremiumGate.swift:19`
- **Problem:** premiumGate(feature:) applies .blur(radius: 10) + .allowsHitTesting(false) over the gated content, but the content View is still constructed and its body/.task/.onAppear/ViewModel init all execute for non-subscribers. Confirmed at AssistantView.swift:42 where .premiumGate wraps the entire Assistant view: a non-Pro user opening the AI Assistant, Live Flight Tracking, Booking Assistant, or Disruption AI screens still builds those views behind the blur, so any data fetch / paid API call (Claude calls, flight-status polling, booking availability) fires for a user who has not paid. This is both a monetization leak (paid quota consumed by free users) and a potential privacy/cost issue.
- **Fix:** Gate structurally, not visually. When !isProSubscriber, do not render `content` at all — show only the upgrade overlay (e.g. `if subscriptionManager.isProSubscriber { content } else { upgradeOverlay }`). If a blurred teaser of real content is desired, ensure the gated view itself checks entitlement before performing any network/side-effect work rather than relying on the modifier to suppress it.

### [MEDIUM] Subscription — restorePurchases() silently no-ops when no entitlements are found
- **Where:** `JetSetter Pro/Core/Services/SubscriptionManager.swift:107`
- **Problem:** On tapping Restore Purchases, AppStore.sync() succeeds and refreshEntitlements() runs; if the account owns no active subscription, isProSubscriber stays false, purchaseError stays nil, and no UI change occurs. The user sees the spinner flash and then absolutely nothing — no confirmation, no 'nothing to restore' message. Users who legitimately have no purchase, or who are signed into the wrong Apple ID, get zero feedback and will assume the button is broken.
- **Fix:** After refreshEntitlements() in restorePurchases(), branch on the result: if isProSubscriber became true, dismiss/confirm; if still false, set purchaseError to a user-facing message like 'No active subscription found for this Apple ID.' Consider a separate success/info message channel so it isn't styled as an error.

### [MEDIUM] Translator — Language code comparison uses maximalIdentifier, so preset lookup never matches
- **Where:** `JetSetter Pro/Features/Translator/TranslatorView.swift:49`
- **Problem:** currentLanguageDisplay compares Locale.Language.maximalIdentifier against preset codes like "ja", "fr", "es". maximalIdentifier performs likely-subtags expansion and returns fully-maximized identifiers such as "ja-Jpan-JP", "fr-Latn-FR", "es-Latn-ES". These never equal the short preset codes, so the first(where:) at line 50 fails for essentially every language and the header always falls back to ("Target", "🌐"). The same defect hits line 82 (selectedCode passed to the picker) so the checkmark at line 301 never appears next to the currently-selected language. Compound codes like "zh-Hans" also won't round-trip.
- **Fix:** Use minimalIdentifier or compare on a normalized language code. Simplest fix: store the selected preset code in @State (e.g. @State private var targetCode = "ja") and derive Locale.Language from it, comparing the raw string. Or compute code via targetLanguage.languageCode?.identifier and match the base, while special-casing script variants (zh-Hans/zh-Hant). Do not use maximalIdentifier for equality against short codes.

### [MEDIUM] TravelEssentials — nextTripDestination() ignores the trip the user is currently on
- **Where:** `JetSetter Pro/Features/TravelEssentials/TravelEssentialsView.swift:338`
- **Problem:** nextTripDestination() filters trips with `$0.startDate > now`, i.e. strictly future trips. A trip that has already started but not ended (the user is currently abroad — exactly when Travel Essentials is most needed) is excluded. Once a trip begins, the screen stops auto-selecting that country and reverts to the default (Japan, see bug above) or to the next future trip's country.
- **Fix:** Prefer the in-progress trip: select the trip where startDate <= now < endDate first, and only fall back to the soonest future trip. e.g. filter `$0.endDate >= now` and sort by startDate, taking the first, so an active trip wins.

### [MEDIUM] VisaLookup — Unknown destinations silently fall back to Japan (wrong country shown)
- **Where:** `JetSetter Pro/Features/VisaLookup/VisaLookupView.swift:11`
- **Problem:** The initial selection is `VisaRequirements.find(query: nextTripDestination() ?? "FR") ?? VisaRequirements.forUSPassport.first!`. When the next trip's destination is not in the static list (e.g. "Georgia", "San Marino", "French Polynesia", or any city string that doesn't literally contain a supported country name), `find` returns nil and the view falls back to `forUSPassport.first!`, which is Japan. The user with a trip to, say, Georgia will be shown Japan's visa rules with the header "For US passport holders" and no indication the destination didn't match. This is misleading in a domain (entry requirements) where a wrong answer can cause a denied boarding/entry.
- **Fix:** Do not silently substitute the first list element. If `find` returns nil, either default to a clearly-neutral state (e.g. an explicit "Select a destination" empty state / auto-open the picker) or fall back to a safe generic message. At minimum make the no-match fallback consistent with the `"FR"` default used when there is no trip, and surface to the user that their destination wasn't recognized.

### [MEDIUM] Expense-Providers — Share-sheet fallback reports success before the user acts and swallows PDF write failure
- **Where:** `JetSetter Pro/Core/Services/Expense/Providers/EmailPDFProvider.swift:85`
- **Problem:** submitViaShareSheet writes the PDF with `try?` (line 85), discarding any write error, then presents UIActivityViewController and immediately returns an ExportBatchResult marking every expense .submitted (lines 93-99) without awaiting the activity controller's completion handler. If the temp write fails, the share item URL points at a missing/empty file yet the app still records the whole batch as submitted. Even on success the user may cancel the share sheet, but the batch is already marked submitted — leading to the app telling the user expenses were exported when nothing left the device.
- **Fix:** Await UIActivityViewController.completionWithItemsHandler in a checked continuation and only resolve .submitted when completed == true, .userCancelled otherwise. Replace `try?` with `try` (propagate the write error) or verify the file exists/non-empty before presenting; on write failure throw providerFailure.

### [MEDIUM] Network-Layer — Google Vision API key leaked in URL query string
- **Where:** `JetSetter Pro/Core/Network/Endpoints.swift:161`
- **Problem:** The Google Vision API key is embedded directly in the URL query string (?key=<secret>). Query strings are logged far more aggressively than headers/bodies: they appear in URLSession/OS network logs, crash reports, any proxy or MITM debugging tooling, and are captured by URLProtocol/analytics. Unlike the other integrations here (FlightAware x-apikey, WorldTracer x-partner-key, Claude x-api-key) which correctly place the secret in a header, this one exposes the credential in the request line where it is much more likely to be captured or logged.
- **Fix:** Google Vision only supports API keys via query param for unauthenticated calls, but you can and should avoid logging it and ideally move to an OAuth/service-account bearer token in a header. At minimum, never log full request URLs for this endpoint, and ensure the URL is never included in error strings surfaced to users. If key-in-query is unavoidable, restrict the key (API + bundle-id restrictions) in the Google console so a leaked key is not freely usable.

### [MEDIUM] Flight-Services — hasGPSFix never resets when GPS goes stale — snapshot shows stale position as a live fix
- **Where:** `JetSetter Pro/Core/Services/InFlightTrackingService.swift:357`
- **Problem:** The snapshot doc for hasGPSFix (line 26) and lastLocationAt (line 119) promise 'a recent fix (< 30s old)', but hasGPSFix is only ever set to true (line 357) and never back to false. lastLocationAt is recorded (line 358) but never read anywhere. When the traveler is airborne without a window seat, or the GPS drops mid-flight, groundSpeed/heading/coordinate freeze at their last value while hasGPSFix stays true, so the UI keeps rendering a stale position and speed as if it were live. Ground-speed staying frozen also means recomputePhase keeps using a stale speed for taxi/takeoff/landing detection.
- **Fix:** Add a staleness check: either a repeating timer (or a computed property) that sets hasGPSFix = false and clears groundSpeedMps/heading when Date().timeIntervalSince(lastLocationAt) > 30. Make hasGPSFix a computed value derived from lastLocationAt rather than a latched Bool.

### [MEDIUM] Data-Services — Location continuation can be resumed twice (crash) or leaked (permanent hang)
- **Where:** `JetSetter Pro/Core/Services/LocationService.swift:98`
- **Problem:** requestCurrentLocation() stores the continuation and calls requestLocation() for the notDetermined case (line 69) BEFORE the OS prompt is answered. requestLocation() with an undetermined status silently fails/does nothing, and the flow relies on locationManagerDidChangeAuthorization to re-issue requestLocation() (line 101). But that delegate then calls requestLocation() a SECOND time while a request path is already in flight, and both didUpdateLocations and didFailWithError resume the SAME continuation without guarding against nil-reset ordering. Concretely: if the user grants permission, requestLocation() is fired from line 77 (which no-ops) and again from line 101; whichever delivers a location resumes the continuation, but if a failure and a success race (or two rapid auth changes) occur, `locationContinuation?.resume` is called twice -> Swift runtime crash 'SWIFT TASK CONTINUATION MISUSE'. Conversely, if the user denies at the prompt, didChangeAuthorization handles .denied (line 102-104), but if status goes to some other value or the manager never fires a callback, the continuation is never resumed and the awaiting Task hangs forever (GroundTransportViewModel.loadPickup awaits this).
- **Fix:** Guard every resume by atomically taking the continuation: `guard let c = locationContinuation else { return }; locationContinuation = nil; c.resume(...)`. Do NOT call requestLocation() from requestCurrentLocation() when status is .notDetermined; only request authorization there and let didChangeAuthorization fire the single requestLocation(). Add a timeout (Task.sleep + cancel) that resumes with LocationError.timeout so callers can never hang.

### [MEDIUM] Platform-Services — Supabase session never refreshed — all cloud sync silently dies ~1 hour after sign-in
- **Where:** `JetSetter Pro/Core/Services/SupabaseService.swift:190`
- **Problem:** refreshSession() exists but is never called anywhere in the codebase (verified via grep — only definition, no callers). GoTrue access tokens expire in ~3600s (expiresIn default at line 501). ensureSignedIn() at line 147 returns early whenever isSignedIn is true (i.e. a cached session exists), and isSignedIn only checks cachedSession != nil (line 140) — it never inspects expiresAt. So after the first hour, sendRaw() keeps attaching a stale Bearer token (line 440), every trips/expenses sync + fetch + deleteAccount returns 401, and the error is surfaced to the user as a generic failure or swallowed. cachedSession.expiresAt is stored but never read.
- **Fix:** Add a guard that refreshes before using the token: in ensureAuthenticated()/before each authenticated request, if let session = cachedSession, session.expiresAt < Date().addingTimeInterval(60) { try await refreshSession() }. Alternatively, on a 401 from validate(), refresh once and retry. Also change isSignedIn / ensureSignedIn to account for a refresh-token being present so an expired-but-refreshable session is repaired instead of treated as valid.

### [MEDIUM] Security-Services — Receipt image + Google Vision API key sent as URL query parameter
- **Where:** `JetSetter Pro/Core/Services/VisionOCRService.swift:100`
- **Problem:** Endpoints.GoogleVision.annotateURL embeds the Vision API key directly in the query string (Endpoints.swift:161: vision.googleapis.com/v1/images:annotate?key=<googleVision>). The full base64 receipt image is POSTed to this URL. The API key travels in the request URL, so it is logged by any proxy/analytics/crash reporter that records URLs, and is trivially extractable. A leaked Vision key can be abused for billing.
- **Fix:** Move the API key out of the URL. Use an ephemeral server-side proxy, or at minimum pass the key via header and restrict the key to the app bundle ID / with per-key quotas. Ensure URLs are not logged.

### [MEDIUM] Security-Services — Amount regex never matches integer/no-decimal currencies (JPY, KRW, etc.)
- **Where:** `JetSetter Pro/Core/Services/VisionOCRService.swift:148`
- **Problem:** The pattern requires a mandatory (?:\.\d{2}) fractional part. Yen and won receipts have no decimals (e.g. 'Total ¥20,350'), so extractAmount returns nil for exactly the destinations this travel app targets. Ironically the demo mock at line 83 shows a ¥20,350 Nobu Tokyo receipt that the real parser could never extract. Users in Japan get 'No text detected' or a nil amount on valid receipts.
- **Fix:** Make the decimal group optional: match '((?:\d{1,3}(?:,\d{3})*|\d+)(?:\.\d{1,2})?)'. Beware European receipts use ',' as the decimal separator — consider normalizing based on detected locale (VisionTextAnnotation.locale is already captured but unused).

### [MEDIUM] Misc-Services — Rental results sorted by raw dailyRate across mixed currencies
- **Where:** `JetSetter Pro/Core/Services/RentalCarService.swift:72`
- **Problem:** searchVehicles merges vehicles from Enterprise/Hertz/National and sorts by `$0.dailyRate < $1.dailyRate` while each provider carries its own `currency` (e.g. Enterprise v.rates.currency, Hertz g.bestRate.currency, National v.priceInfo.currencyCode). If two providers quote in different currencies (a real case at an intl airport like NRT, where one might return JPY and another USD), the numeric comparison is meaningless — a 8000 JPY car (~$52) sorts below a 60 USD car. The 'cheapest first' ordering the UI relies on becomes wrong.
- **Fix:** Normalize to a common currency before sorting (convert via a rate table / user's display currency), or at minimum group/sort within each currency and surface the currency in the sort key. Do not compare `dailyRate` values that have different `currency` fields directly.


## Verified Low Bugs (4)

### [LOW] DepartureOptimizer — Rideshare + Navigate + Route map all use the ORIGIN airport as the drop-off/destination
- **Where:** `JetSetter Pro/Features/DepartureOptimizer/DepartureOptimizerView.swift:515`
- **Problem:** destinationAirportCoord(for:) resolves its coordinate from originAirportIATA(for:) instead of destinationAirportIATA(for:). Everything named 'destination' in the view (line 62 route-sheet dest, line 343 Uber dropoff, line 350 Lyft dropoff) therefore points at the DEPARTURE airport, not the arrival airport. For the airport-drop-off use case (Navigate-to-airport, Order-a-ride) the origin airport is actually what you want to drive to, so the Navigate sheet happens to work — but the naming makes the Uber/Lyft 'dropoff' semantically the departure airport while the code comments/labels (line 345 "\(iata) Airport" where iata=destinationAirportIATA) claim it is the ARRIVAL airport. Net effect: the Uber deep link's dropoff coordinate is the departure airport but its nickname label is the arrival airport IATA — a mismatched pin/label. If a caller ever reused this helper for true destination routing it would be silently wrong.
- **Fix:** Rename to two explicit helpers: originAirportCoord(for:) (departure, used by Navigate + rideshare dropoff since you drive to the departure airport) and destinationAirportCoord(for:) (arrival). At line 345 pass the ORIGIN iata as the nickname so the dropoff coordinate and its label agree. Do not use destinationAirportIATA for the rideshare nickname when the coordinate is the origin airport.

### [LOW] Intelligence — activeCard identity churns every evaluation, re-animating the card every 60s
- **Where:** `JetSetter Pro/Features/Intelligence/TravelIntelligenceViewModel.swift:47`
- **Problem:** Each signal evaluator (evaluateImminentFlight/CheckInWindow/TripStartingSoon) constructs its ProactiveTrigger with a fresh UUID() every call (lines 141, 163, 185). evaluate() runs on every HomeView surface and once per minute via startAutoRefresh. The guard `next?.id != activeCard?.id` at line 47 compares those random UUIDs, so even when the *same logical card* is still valid, the ids differ and the branch always executes: activeCard is reassigned inside withAnimation, forcing the card to re-run the spring insertion/removal transition (TravelIntelligenceCardView lines 14-17) roughly every 60 seconds. Users see the card flicker/re-slide and the countdown text jump abruptly each minute.
- **Fix:** Compare on a stable identity instead of the random UUID. Use the dismissKey (type + dismissIdentifier) for the equality check, e.g. `if dismissKey(for: next) != activeCard.map(dismissKey(for:))` (guarding nils), or make the trigger id deterministic from type+dismissIdentifier. Only reassign activeCard when the stable key or the displayed body actually changes.

### [LOW] LuggageTracker — saveBags() writes dates in a different format than MockDataService reads/writes
- **Where:** `JetSetter Pro/Features/LuggageTracker/LuggageViewModel.swift:45`
- **Problem:** saveBags() encodes with a default `JSONEncoder()` (numeric .deferredToDate dates), while everything else that touches the `jetsetter_bags` key (MockDataService seed at :46-47, activation at :711-712) uses `.iso8601`. Once the user adds/tracks/deletes a bag and saveBags() runs, the stored blob switches to numeric-date format; any later code path that decodes with an .iso8601 decoder (or re-seeding logic that assumes ISO strings) will then fail to parse. The two writers are permanently inconsistent on the same key.
- **Fix:** Standardize on one strategy for the `jetsetter_bags` key. Configure saveBags()'s encoder with `dateEncodingStrategy = .iso8601` to match MockDataService, and configure the decoder in loadBags() to match. Ideally centralize the encoder/decoder for this key so both files can't drift.

### [LOW] TripJournal — Thumbnail/full-image continuation can leak and hang the loading task
- **Where:** `JetSetter Pro/Core/Services/PhotoLibraryService.swift:85`
- **Problem:** thumbnail(for:) and fullImage(for:) wrap PHImageManager.requestImage in a withCheckedContinuation and only resume when the callback delivers a NON-degraded image (guard !isDegraded, !didResume). In opportunistic mode there are real cases where the final (non-degraded) callback never fires — e.g. the request is cancelled/superseded, or an iCloud fetch delivers only a low-res degraded frame and then errors, or PHImageResultIsInCloudKey / an error is returned with isDegraded not set the way expected. When only degraded callbacks arrive, the guard filters every callback, the continuation is never resumed, and the GridCell/.task awaiting it hangs forever, leaking the continuation (and the cell shows a perpetual spinner). Because these run on many cells simultaneously during scrolling, several tasks can be stuck at once.
- **Fix:** Resume on the final result regardless of degradation, or add explicit handling: resume when (image != nil && !isDegraded) OR when info[PHImageErrorKey] != nil OR info[PHImageCancelledKey] == true. At minimum, resume once with whatever non-degraded image (or nil) is delivered, and also resume with nil if the callback reports an error or cancellation so the awaiting task never hangs.


## Other Bugs (medium/low, un-verified) (146)

- **[medium] AirportMap** — isInsideSupportedAirport and indoorLevelIndex never reset when the user leaves the terminal or floor data disappears (`JetSetter Pro/Features/AirportMap/AirportMapViewModel.swift:262`)
  - Add an else branch: when location.floor == nil, set isInsideSupportedAirport = false (and optionally reset indoorLevelIndex to 0). Only report the floor while floor data is actually present.

- **[medium] AirportMap** — calculateLayoverRoute() silently no-ops if user location hasn't been acquired yet (`JetSetter Pro/Features/AirportMap/AirportMapViewModel.swift:135`)
  - Remove the userLocation guard from calculateLayoverRoute (or use it only to bias the search region if present). If a fix is genuinely required, surface an explicit 'waiting for location' state instead of returning silently.

- **[medium] AirportMap** — Error alert uses a constant isPresented binding, so the alert can fail to dismiss and re-present (`JetSetter Pro/Features/AirportMap/AirportMapView.swift:115`)
  - Use a proper two-way binding, e.g. `.alert("Map Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } }))`, or introduce a Bool @Published presentation flag.

- **[low] AirportMap** — nearbyPOIs are loaded around the destination gate but never filtered to the airport / current floor (`JetSetter Pro/Features/AirportMap/AirportMapViewModel.swift:169`)
  - Constrain POIs to airport-interior categories and, where floor data is available, filter/annotate by level; consider dropping .hotel from the filter for an airside gate context.

- **[medium] Assistant** — Suggestion chip implies an agentic action the plain chat path cannot perform (`JetSetter Pro/Features/Assistant/AssistantView.swift:147`)
  - Either route these action-style prompts through the IRIS action router / relevant services, or replace the chips with prompts the pure-chat path can actually answer well. At minimum drop the 'Submit my ... expenses' chip from this non-agentic surface so users aren't led to expect an action.

- **[medium] Assistant** — First context-window overflow on Apple Intelligence surfaces a user-facing error instead of retrying (`JetSetter Pro/Core/Services/AIService.swift:132`)
  - On context-window-exceeded, transparently recover in the same request: drop the session and re-issue `session.streamResponse(to: prompt)` once against a fresh session before finishing with an error. Optionally track turn count and pre-emptively recycle the session.

- **[low] Assistant** — No guard against concurrent sends in the ViewModel (`JetSetter Pro/Features/Assistant/AssistantViewModel.swift:39`)
  - Add `guard !isWaitingForResponse else { return }` at the top of sendMessage, or hold the streaming Task and cancel/ignore re-entrant calls, so the ViewModel is safe independent of the View's disabled state.

- **[medium] Booking** — lowestNightlyRate compares raw numbers across mixed currencies (`JetSetter Pro/Features/Booking/BookingModel.swift:47`)
  - Filter rates to the searched currency (searchParams.currency) before taking min, and derive lowestRateCurrency from the same rate that produced the min (e.g. return the winning RoomRate, not first). Guard against comparing values with differing currency codes.

- **[low] Booking** — numberOfNights / checkout date use device local calendar with day-granularity, off-by-one near DST/timezone boundaries (`JetSetter Pro/Features/Booking/BookingModel.swift:29`)
  - Normalize check-in/check-out to startOfDay in a fixed calendar (or compute nights in the API 'yyyy-MM-dd' string space) so the nights count is stable regardless of device time zone / DST.

- **[medium] Booking** — buildQueryItems always sends occupancy '2-0'-style with children hardcoded and ignores rooms count (`JetSetter Pro/Features/Booking/BookingViewModel.swift:99`)
  - Emit one occupancy query item per room (repeat the occupancy param rooms times) and stop hardcoding rooms=1; either wire rooms into the UI+query or remove the unused field to avoid the misleading default.

- **[low] Booking** — Confirmation number is a non-unique 5-digit random with no collision or persistence guarantee (`JetSetter Pro/Features/Booking/HotelDetailView.swift:392`)
  - If keeping the mock, widen the entropy (UUID-derived) and persist the confirmation regardless of the itinerary toggle. If this is meant to ship, back it with a real booking-create call; do not show 'Check your email' for a locally faked booking.

- **[medium] Carbon** — Short/long-haul emission-factor cliff makes a longer flight report less CO2 than a shorter one (`JetSetter Pro/Features/Carbon/CarbonFootprintView.swift:298`)
  - Replace the hard step with a continuous factor. Either blend linearly between ~0.255 and ~0.150 over a transition band (e.g. 1000-3000 km), or model total fuel as a fixed climb component plus a per-km cruise component (kg = climbFuelCO2 + distance*cruiseFactor) so the curve is monotonic in distance.

- **[low] Carbon** — Same origin and destination renders a valid 0 kg result instead of an error/guard (`JetSetter Pro/Features/Carbon/CarbonFootprintView.swift:35`)
  - In distanceKm (or before rendering resultCard at line 35), guard against origin.uppercased() == destination.uppercased() and treat it like the unrecognized-airport case, showing a 'origin and destination are the same' message.

- **[medium] CheckIn** — Success-step side effects fire in onAppear with no guard — Live Activity start and notifications can double-fire (`JetSetter Pro/Features/CheckIn/CheckInFlowView.swift:351`)
  - Gate the block with a `@State private var didCommit = false` set inside onAppear: `guard !didCommit else { return }; didCommit = true`. Then run the side effects once.

- **[medium] CheckIn** — No-wallet-item check-in persists an orphaned identity that never matches a real flight (`JetSetter Pro/Features/CheckIn/CheckInFlowView.swift:23`)
  - Do not run markCheckedIn / Live Activity with placeholder defaults. Either require a real departure (make the parameter non-optional and force callers to supply the flight's actual startDate) or skip persistence when the flow was opened without a concrete flight (e.g. a `hasRealFlight` flag).

- **[medium] CheckIn** — Wallet-assigned seat outside the Business cabin is uneditable and can be un-changeable (`JetSetter Pro/Features/CheckIn/CheckInFlowView.swift:150`)
  - Make the cabin that contains the user's seat selectable, or gray out cross-cabin selection entirely and only allow re-selection within the same cabin. At minimum, when walletItem?.seatNumber is present, drive isSelectable off which cabin owns that seat rather than hardcoding Business.

- **[low] CheckIn** — Two inconsistent airline-code extractions from the same flight number (`JetSetter Pro/Features/CheckIn/CheckInFlowView.swift:362`)
  - Compute the airline code once (prefer the prefix(while: isLetter) form) and reuse it in both the FlightLiveActivityService.start call and the TravelProfileStore.record attributes.

- **[low] CheckIn** — Route parsing produces literal placeholder IATA codes for the Live Activity (`JetSetter Pro/Features/CheckIn/CheckInFlowView.swift:359`)
  - Pass structured origin/destination IATA into CheckInFlowView instead of re-parsing a display string, and substitute nil/empty (not "—") when a code is unavailable.

- **[low] CheckIn-Services** — Amadeus token refresh has a check-then-act race across concurrent check-in lookups (`JetSetter Pro/Core/Services/CheckInService.swift:137`)
  - Coalesce in-flight token fetches: store an `private var tokenTask: Task<String, Error>?` and have concurrent callers await the same task, clearing it on completion. Alternatively acceptable to leave given actor serialization already prevents corruption.

- **[medium] CheckIn-Services** — Airlines that expose only a Mobile check-in link are silently dropped (returns nil) (`JetSetter Pro/Core/Services/CheckInService.swift:196`)
  - When no Web/All link exists but a Mobile link does, fall back to the mobile href as the primary webURL (or return a result with webURL = mobile). e.g. `let primary = webLink ?? mobileLink; guard let href = primary?.href, let url = URL(string: href) else { return nil }` and set mobileURL only when it differs.

- **[medium] CheckIn-Services** — Check-in notification fire time ignores the flight's departure timezone / opens at wrong moment for offline-configured airlines (`JetSetter Pro/Core/Services/CheckInService.swift:108`)
  - Use a UNTimeIntervalNotificationTrigger with `timeInterval: checkInOpenTime.timeIntervalSinceNow` (guarded > 0), which fires at a fixed instant regardless of timezone changes, instead of decomposing into calendar components.

- **[low] CheckIn-Services** — Notification identifier can collide when two flights share a departure timestamp, and cancel silently no-ops on mismatch (`JetSetter Pro/Core/Services/CheckInService.swift:123`)
  - Normalize flightNumber (`flightNumber.uppercased()`) when building the id in both scheduleCheckInNotification and cancelCheckInNotification so schedule/cancel and the two stores agree.

- **[medium] CurrencyTracker** — Zero-decimal currencies (JPY, KRW, VND) displayed with two decimal places (`JetSetter Pro/Features/CurrencyTracker/CurrencyExpenseView.swift:222`)
  - Format money with Decimal/NSDecimalNumber and a currency NumberFormatter (or .formatted(.currency(code:))) keyed off the actual currency code so the correct number of fraction digits is used per currency, and round conversions to the target currency's minor units.

- **[medium] CurrencyTracker** — Budget entered in destination currency will be compared against a home-currency total (`JetSetter Pro/Features/CurrencyTracker/CurrencyExpenseViewModel.swift:127`)
  - Add a way to set/edit the budget and clearly define/enforce that it is in homeCurrency (convert if entered otherwise). Until then the budget card is dead code that will confuse the next maintainer.

- **[medium] Data-Services** — LocationService is not thread-safe: continuation and CLLocationManager touched from multiple actors (`JetSetter Pro/Core/Services/LocationService.swift:37`)
  - Annotate the class @MainActor (delegate callbacks then hop to main) or serialize all continuation access through a dedicated actor/lock. Ensure requestLocation()/authorization calls and continuation mutation happen in one isolation domain.

- **[medium] Data-Services** — Wikipedia missing-page ('-1') is treated as a valid photo lookup and negatively cached (`JetSetter Pro/Core/Services/CityPhotoService.swift:94`)
  - Pick the page deterministically (prefer a page whose id != "-1" and that contains a `thumbnail`), and distinguish 'confirmed no image' from 'transient failure' — don't cache nil on network errors (line 105) so a retry can succeed later. Consider using &redirects=1 and generator=... to resolve redirects.

- **[low] Data-Services** — Weather cache key truncates toward zero, mixing distinct coordinates and misplacing negatives (`JetSetter Pro/Core/Services/WeatherService.swift:75`)
  - Use (latitude*10).rounded() cast to Int for symmetric bucketing, or format with String(format:"%.1f_%.1f") to make intent explicit. Consider a finer bucket (0.01deg) if precision matters.

- **[low] Data-Services** — Claude streaming ignores HTTP error body and misclassifies non-200 as generic bad-server-response (`JetSetter Pro/Core/Services/AIService.swift:198`)
  - Read `bytes`/data on non-200, decode Anthropic's {type:error, error:{type,message}} and surface a typed error (invalid key vs rate-limit vs overloaded). This directly improves the fallback UX when Apple Intelligence is unavailable.

- **[medium] DepartureOptimizer** — Leave reminder is scheduled even after the user DENIES notification permission (`JetSetter Pro/Features/DepartureOptimizer/DepartureOptimizerView.swift:388`)
  - Capture the Bool: `guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]), granted else { /* surface a message */ return }`. Optionally show an alert directing the user to Settings when denied.

- **[medium] DepartureOptimizer** — TSA/urgency uses the DEVICE's local time zone, not the origin airport's time zone (`JetSetter Pro/Core/Services/TSAWaitEstimator.swift:64`)
  - Look up the origin airport's time zone (e.g. from an IATA→timezone table) and set the Calendar's timeZone before extracting hour/weekday, so peak/off-peak reflects local airport time rather than device time.

- **[low] DepartureOptimizer** — ETA in the route sheet ignores whatever real time has elapsed while driving (`JetSetter Pro/Features/DepartureOptimizer/RouteMapSheet.swift:149`)
  - If this is ever used for real navigation, base ETA on actual wall-clock start time + real remaining travel time rather than sim progress; otherwise label it clearly as a demo/simulated ETA.

- **[medium] DepartureOptimizer** — refreshRecommendation shows a stale/incorrect error and no retry when location is unavailable (`JetSetter Pro/Features/DepartureOptimizer/DepartureOptimizerView.swift:469`)
  - Add a 'Retry' / 'Enable location' action on the error card that re-invokes the location request (and deep-links to Settings on denied), and re-attempt location acquisition rather than caching a one-shot nil.

- **[medium] Disruption** — priceFormatted ignores locale/currency formatting and prints raw code (`JetSetter Pro/Features/Disruption/DisruptionModel.swift`)
  - Use price.formatted(.currency(code: currency)) (Foundation FormatStyle) which localizes symbol placement, grouping, and fraction digits. If whole-unit display is intentional, add .precision(.fractionLength(0)) explicitly rather than %.0f.

- **[medium] Disruption** — Rebooking URL fabricated from Amadeus offer token is not a real bookable page (`JetSetter Pro/Features/Disruption/DisruptionViewModel.swift`)
  - Do not synthesize a URL from the Amadeus token. Prefer event.rebookingUrl (or an alternative-specific real deep link if one is stored on AlternativeFlight); only fall back to a genuine search/booking URL. If no real bookable URL exists, disable the CTA rather than opening a dead page.

- **[medium] Disruption** — Resolving one event leaves duplicate same-flight events still active (`JetSetter Pro/Features/Disruption/DisruptionViewModel.swift`)
  - When resolving, resolve every active event matching the same flight key (flightNumber|origin|destination), or resolve by the deduped group. Upsert all of them so the whole flight clears from the active list.

- **[low] Disruption** — Resolve rollback restores event to top of active list, losing its sort position (`JetSetter Pro/Features/Disruption/DisruptionViewModel.swift`)
  - After a failed resolve, re-run the partition/sort (or re-insert respecting createdAt) instead of unconditional insert(at: 0), or simply call load() to restore canonical ordering.

- **[low] Disruption** — manualPoll's inner load() can no-op against a concurrent .task load, leaving stale data (`JetSetter Pro/Features/Disruption/DisruptionViewModel.swift`)
  - Have manualPoll perform the fetch directly (or await/serialize with the in-flight load) rather than relying on load()'s early-return guard, or track a single loading task and await it instead of dropping the reload.

- **[medium] Disruption-Services** — Amadeus OAuth token cache races: concurrent alternative searches fire duplicate token requests (`JetSetter Pro/Core/Services/DisruptionResponseEngine.swift:378`)
  - Store an in-flight `Task<String, Error>?` on the actor. On entry, if a fetch task already exists and is unresolved, await it instead of starting a new one; clear it when done. This coalesces concurrent callers onto a single token request.

- **[medium] Disruption-Services** — Missed-connection layover compares FlightAware UTC arrival against the next itinerary item's stored startDate with no timezone/source guarantee (`JetSetter Pro/Core/Services/DisruptionMonitorService.swift:263`)
  - Validate the connection before computing layover: require flightItems[index+1] to depart from the arrival airport of the current leg and within a sane window (e.g. same calendar day / < a few hours after arrival). Confirm both Dates are true UTC-anchored absolute times; if the itinerary startDate is wall-clock, resolve it against the departure airport timezone before subtracting.

- **[medium] Disruption-Services** — Gate-change cache is per flight-number global, causing false gate-change alerts for recurring flight numbers across trips/days (`JetSetter Pro/Core/Services/DisruptionMonitorService.swift:69`)
  - Key the gate cache by a per-instance identifier (flightNumber + scheduled departure date, or trip.id + flightNumber) so gate comparisons only happen within the same flight instance. Ideally fetch by ident+date to disambiguate which occurrence AeroAPI returns.

- **[medium] Disruption-Services** — extractFlightNumber only normalizes 2-letter carrier + space + digit, dropping 3-char and alphanumeric IATA codes (`JetSetter Pro/Core/Services/DisruptionMonitorService.swift:430`)
  - Widen the carrier-code class to allow a digit in the designator, e.g. normalize `([A-Z0-9]{2})\s+(\d)` and extract `\b[A-Z0-9]{2}\d{1,4}\b` (guarding against pure-numeric matches). Validate the first char is a letter or the two-char code contains at least one letter.

- **[low] Disruption-Services** — Major-delay and missed-connection thresholds use strict > / < , silently ignoring the exact boundary and negative/absent delays (`JetSetter Pro/Core/Services/DisruptionMonitorService.swift:248`)
  - Use `delayMin >= majorDelayThresholdMinutes` and `layoverMinutes <= missedConnectionThresholdMin` (or adjust the copy) so the boundary matches the stated '45+' / 'under 60' semantics.

- **[medium] DocumentVault** — Document metadata (issuing country, expiry, notes) is persisted unencrypted in UserDefaults (`JetSetter Pro/Features/DocumentVault/DocumentVaultStore.swift:28`)
  - Encrypt the whole serialized blob with VaultCrypto.encrypt() before writing to UserDefaults (or move to a file protected with .completeFileProtection / an encrypted store). At minimum, correct the 'encrypted at rest' comments so the security posture isn't overstated.

- **[low] DocumentVault** — Keychain key uses ThisDeviceOnly but not biometric/passcode access control, and app deletes reinstall leaves orphaned ciphertext undecryptable (`JetSetter Pro/Core/Services/VaultCrypto.swift:94`)
  - If the biometric guarantee matters, create the key with SecAccessControlCreateWithFlags(.biometryCurrentSet/.userPresence) and store with kSecAttrAccessControl. Surface decryption failures (distinguish 'no key on this device' from other errors) instead of silently dropping the number in decryptNumbers.

- **[low] DocumentVault** — expiryUrgency / daysUntilExpiry returns 0 (critical, not expired) for a document that expired earlier the same day (`JetSetter Pro/Features/DocumentVault/DocumentModel.swift:111`)
  - Compare on calendar-day boundaries: let today = Calendar.current.startOfDay(for: Date()); let target = Calendar.current.startOfDay(for: expiry); days = dateComponents([.day], from: today, to: target). Then days <= 0 can be treated as expired (or day 0 explicitly labeled 'Expires today').

- **[low] DocumentVault** — entryRequirements 'contains' fallback matches on the wrong direction and can mismatch (`JetSetter Pro/Features/DocumentVault/DocumentVaultViewModel.swift:149`)
  - Normalize case and match against a canonical country field, and iterate deterministically (e.g. sort keys by length descending so the most specific match wins), or key off an ISO country code rather than free-text contains.

- **[medium] Expense-Providers** — Mail continuation never resumes if the composer is dismissed without a delegate callback (`JetSetter Pro/Core/Services/Expense/Providers/EmailPDFProvider.swift:73`)
  - Guard against concurrent submits: if pendingContinuation != nil at submit time, throw or serialize. Capture the expenses inside the continuation closure rather than in a shared pendingExpenses property so a re-entrant call can't clobber it. Consider resuming with userCancelled if the composer is dismissed without a result.

- **[medium] Expense-Providers** — OAuth connect proceeds with empty clientID instead of reporting missing configuration (`JetSetter Pro/Core/Services/Expense/Providers/RampProvider.swift:24`)
  - In OAuthExpenseProvider.connect (and/or a computed isConfigured on endpoints), check endpoints.clientID.isEmpty and throw ExpenseExportError.configurationMissing(displayName) before building the auth URL. Optionally hide/disable unconfigured providers in the registry.

- **[low] Expense-Providers** — postExpense partial-batch failures are recorded but token refresh only happens once up front (`JetSetter Pro/Core/Services/Expense/Providers/OAuthExpenseProvider.swift:116`)
  - On a 401 from postExpense, refresh the token once, persist it, and retry the request before recording .failed. Alternatively re-check isExpired each iteration and refresh proactively.

- **[low] Expense-Providers** — Force-unwrapped .data(using: .utf8)! on multipart boundary strings (`JetSetter Pro/Core/Services/Expense/Providers/ExpensifyProvider.swift:104`)
  - Use ?? Data() or throw providerFailure on nil encoding rather than force-unwrapping, for consistency with the rest of the error-returning method.

- **[medium] ExpenseExport** — Trip date-window filter assumes endDate is midnight; wrong inclusion at day boundaries (`JetSetter Pro/Features/ExpenseExport/ExpenseExportView.swift:27`)
  - Use Calendar.current: let end = Calendar.current.startOfDay(for: trip.endDate) then add one day via Calendar.date(byAdding: .day, value: 1, to: end); filter date >= startOfDay(startDate) && date < that. This makes the window a clean set of calendar days independent of the stored time-of-day and DST.

- **[medium] ExpenseExport** — PDF line-item table silently drops expenses that overflow page 1, desyncing from the total (`JetSetter Pro/Features/ExpenseExport/PDFExpenseReportRenderer.swift:181`)
  - When y exceeds the page limit, call context.beginPage(), reset y to the top margin, redraw the table header, and continue. Track pageIdx so footers stay correct. Do the same overflow handling before the receipt-audit loop.

- **[low] ExpenseExport** — Category subtotals in PDF summary are silently truncated (`JetSetter Pro/Features/ExpenseExport/PDFExpenseReportRenderer.swift:140`)
  - Either allocate enough vertical space for all present categories, wrap into a second column, or aggregate the overflow into an 'Other categories' line so the displayed subtotals reconcile to the total.

- **[medium] ExpenseExport** — Share-sheet fallback reports success even if PDF write fails (`JetSetter Pro/Core/Services/Expense/Providers/EmailPDFProvider.swift:85`)
  - Use try pdfData.write(...) (propagate the error) instead of try?. For accurate outcome reporting, use a UIActivityViewController completion handler and only resolve as submitted when completed == true, mapping cancellation to ExpenseExportError.userCancelled.

- **[medium] ExpenseTracker** — No validation against negative or zero amounts (`JetSetter Pro/Features/ExpenseTracker/ExpenseTrackerView.swift:302`)
  - Require amount > 0 in canSave and in the OCR confirm disabled-check: `Double(amount).map { $0 > 0 } ?? false`.

- **[medium] ExpenseTracker** — MapKit geocode+directions failures are swallowed with no user feedback (`JetSetter Pro/Features/ExpenseTracker/ExpenseViewModel.swift:214`)
  - Surface an error: have calculateDistance throw or return a Result, and set an errorMessage in LogMileageView when nil ('Couldn't find a driving route between those addresses.').

- **[low] ExpenseTracker** — isCalculating not reset if the mileage view is dismissed mid-calculation (`JetSetter Pro/Features/ExpenseTracker/ExpenseTrackerView.swift:387`)
  - Use `isCalculating = true; defer { isCalculating = false }` around the await, matching suggestCategory().

- **[medium] Flight-Services** — recomputePhase is only invoked from altitude and location callbacks, so with no altimeter and no GPS it never runs (`JetSetter Pro/Core/Services/InFlightTrackingService.swift:235`)
  - Also call recomputePhase() at the end of processAcceleration, or run a low-frequency ticker that recomputes phase from whatever signals are currently available; gate start() on isAvailable and surface lastError when no usable sensor is present.

- **[medium] Flight-Services** — Live Activity staleDate computed from estimatedDeparture even after departure/cancellation (`JetSetter Pro/Core/Services/FlightLiveActivityService.swift:92`)
  - Compute staleDate = max(Date(), estimatedDeparture) + buffer, and for terminal statuses (.cancelled, .departed) either call end() or set a short dismissal so the card doesn't linger 4h.

- **[medium] Flight-Services** — start() ends the previous activity asynchronously with no guard against races / dropped current (`JetSetter Pro/Core/Services/FlightLiveActivityService.swift:46`)
  - In the catch block set current = nil. Before ending, compare existing.attributes.flightNumber to the incoming flightNumber and skip the end/recreate (or just update) when they match.

- **[low] Flight-Services** — Demo-mode altitude is an unbounded random walk that can drift far from 35,000 ft (`JetSetter Pro/Core/Services/InFlightTrackingService.swift:189`)
  - Oscillate around a fixed cruise altitude (e.g. base + sin(t)*small) instead of accumulating, and wrap longitude into [-180,180].

- **[low] Flight-Services** — No minimum-dwell / hysteresis on phase transitions — phases can flicker on noisy sensor data (`JetSetter Pro/Core/Services/InFlightTrackingService.swift:309`)
  - Require a minimum dwell (e.g. ignore transitions within N seconds of phaseEnteredAt) and/or latch one-shot milestones (takeoff, arrived) so their side effects can't re-fire.

- **[medium] FlightBoard** — scheduledTime formatted in device-local timezone with no departure-airport timezone or date (`JetSetter Pro/Features/FlightBoard/FlightBoardData.swift:46`)
  - Attach the departure airport's timezone to the flight item (or derive it from origin IATA) and set `f.timeZone` accordingly before formatting; otherwise clearly label the board as showing local device time. At minimum reuse a shared formatter so the user row and samples are consistent.

- **[low] FlightBoard** — extractGate leaves whitespace if notes use a tab or multiple spaces (`JetSetter Pro/Features/FlightBoard/FlightBoardData.swift:86`)
  - Capture the group value directly instead of string-replacing the label, e.g. use an NSRegularExpression / Regex capture group and return only capture 1, or `.trimmingCharacters(in: .whitespaces)` the result after stripping the label.

- **[medium] FlightBoard** — Destination IATA parsed from free-text location assumes exact ' → ' separator and origin-first order (`JetSetter Pro/Features/FlightBoard/FlightBoardData.swift:41`)
  - Normalize separators (accept '→', '->', ' to ', '-') and fall back to extracting a 3-letter IATA token via regex from the location or title, or store origin/dest IATA as structured fields on ItineraryItem rather than reparsing free text.

- **[medium] FlightTracker** — Flight identifier interpolated into URL without percent-encoding (`JetSetter Pro/Core/Network/Endpoints.swift:38`)
  - Percent-encode the path component: `ident.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` before interpolation, or build the URL with `URLComponents`. flightTrack(ident:) at line 44 has the same issue (faFlightId is more constrained but still worth encoding).

- **[low] FlightTracker** — Progress bar width not clamped — can overflow the track if API returns >100 or negative (`JetSetter Pro/Features/FlightTracker/FlightDetailView.swift:471`)
  - Clamp: `let p = max(0, min(100, percent))` and use `p` for the width. Do the same for the `Double($0)/100.0` progress passed to the map.

- **[medium] GroundTransport** — Lyft cost estimate priceRange truncates cents via integer division, understating the max (`JetSetter Pro/Features/GroundTransport/GroundTransportModel.swift:115`)
  - Format as currency with cents, e.g. use Decimal(cents)/100 with .formatted(.currency(code:)) or String(format: "$%.2f", Double(cents)/100). Round the displayed range consistently (round the max up if you want a conservative estimate) rather than truncating.

- **[low] GroundTransport** — Dropoff coordinates geocoded but Uber deep link sends a raw address string; product_id from ride type (`JetSetter Pro/Features/GroundTransport/GroundTransportModel.swift:53`)
  - If/when deep-linking is enabled, pass dropoff[latitude]/dropoff[longitude] (the geocoded CLLocation is available) rather than a formatted address, and use real product identifiers. Otherwise remove deepLinkURL/appStoreURL as dead code to avoid future misuse.

- **[medium] Home** — parsedGate regex leaves 'Gate ' prefix when gate contains lowercase or spacing variants; but more importantly gate 'B14' fallback fabricates a fake gate into a real boarding pass (`JetSetter Pro/Features/Home/HomeView.swift:606`)
  - Do not inject fabricated gate/seat/confirmation values into a boarding pass that represents a real flight. Pass nil / "—" through so the UI shows an empty/placeholder gate, or clearly label the pass as a demo stand-in. Only use B14/3A when MockDataService.isEnabled is true.

- **[medium] Home** — Shared timeFormatter mutated for destination timezone can corrupt concurrently-computed time strings (`JetSetter Pro/Features/Home/HomeViewModel.swift:367`)
  - Use a dedicated DateFormatter instance for destination local time (its own cached formatter with timeZone set once when destinationTimeZone changes), instead of mutating the shared timeFormatter and resetting it each call.

- **[medium] Home** — IRISTriggers.shared.evaluate() called inside body decodes UserDefaults JSON on every render (`JetSetter Pro/Features/Home/HomeView.swift:44`)
  - Replace the inline IRISTriggers.shared.evaluate() with viewModel.topIRISSuggestion == nil (the already-cached queue), and refresh that queue via reloadIRISSuggestions() on the relevant events rather than decoding UserDefaults during layout.

- **[medium] Home** — loadDestinationData geocodes trip.destination but only clears nothing on failure — stale destination weather/timezone persist across flights (`JetSetter Pro/Features/Home/HomeViewModel.swift:217`)
  - Set destinationTimeZone = nil and destinationWeather = nil at the top of loadDestinationData() (after the mock branch) before attempting the geocode, so a failed lookup shows the loading/empty state rather than stale data from a previous destination.

- **[low] Home** — recordCompletedTrips uses trip.endDate < now with no timezone/all-day consideration; a same-day return can be marked completed prematurely (`JetSetter Pro/Features/Home/HomeViewModel.swift:271`)
  - Add a small grace margin (e.g. endDate + some hours) or compare against end-of-day for date-only trips before recording completion, to avoid recording the learning signal while the trip is effectively still active.

- **[medium] IRIS-Core** — IRISVoiceController re-requests permissions and reinstalls speech assets on every listen cycle (`JetSetter Pro/Core/Services/IRIS/IRISVoiceController.swift:97`)
  - Split one-time setup (permissions + asset install + transcriber/analyzer construction) from the per-utterance listen restart. Cache the granted-permission result and the built analyzer/transcriber; on resumeLoop only reinstall the mic tap and restart the audio engine instead of re-running beginSession from scratch.

- **[low] IRIS-Core** — Preference dedup normalizes only on lowercase, letting near-duplicate values accumulate (`JetSetter Pro/Core/Services/IRIS/IRISMemory.swift:97`)
  - Normalize more aggressively before comparison (trim, collapse whitespace, strip trailing 's'/punctuation), or cap/merge entries per category. At minimum de-duplicate the joined values in summaryForPrompt() so the prompt stays lean.

- **[low] IRIS-Core** — ISO8601 departure parse: primary formatter with .withFractionalSeconds fails on the documented example format (`JetSetter Pro/Core/Services/IRIS/IRISTools.swift:287`)
  - Make the primary formatter tolerant: try without fractional seconds first (formatOptions=[.withInternetDateTime]) and add a fractional-seconds fallback, so the documented example hits the primary path.

- **[medium] IRIS-Feature** — Streamed reply is dropped if the stream completes with empty final snapshot despite prior content (`JetSetter Pro/Features/IRIS/IRISChatViewModel.swift:52`)
  - Capture the last non-empty snapshot into a local var during the loop and use that for `reply`; only surface the 'didn't respond' error when no non-empty snapshot was ever received.

- **[medium] IRIS-Feature** — onDisappear stops voice but leaves a confirmation card pending in the shared router (`JetSetter Pro/Features/IRIS/IRISChatView.swift:57`)
  - In onDisappear, also call router.cancelPendingAction() (or persist/clear it deliberately) so an abandoned confirmation doesn't leak across navigations and sessions.

- **[medium] IRIS-Feature** — confirmPending isCommitting flag is a View @State that resets on redraw, allowing double-commit (`JetSetter Pro/Features/IRIS/IRISChatView.swift:339`)
  - Clear router.pendingAction optimistically before awaiting commit (or move the in-flight flag onto the router), so the card cannot be re-presented while the write is running.

- **[low] IdentityVault** — State picker cannot recover a persisted non-live state selection (`JetSetter Pro/Features/IdentityVault/IdentityVaultView.swift:349`)
  - Add a second Section (e.g. "Coming soon") that lists `DigitalIDStates.all.filter { !$0.isLive }` so every state in `all` is selectable, or drop the isLive concept entirely if only live states will ever ship. At minimum guarantee `selectedState` is always present in the list so the checkmark and change-flow work.

- **[medium] InFlight** — descent -> cruise re-transition resets phaseEnteredAt and can re-fire logic incorrectly (`JetSetter Pro/Core/Services/InFlightTrackingService.swift:297`)
  - Require hysteresis: only allow descent->cruise if a sustained positive/zero vertical speed persists for N seconds AND altitude is actually increasing, not merely momentarily flat. Prefer a monotonic phase progression (don't allow going backwards from descent to cruise), or add a minimum dwell time in a phase before permitting a reversal.

- **[medium] InFlight** — verticalSpeedMps carried forward on stale delta produces phantom climb/descent (`JetSetter Pro/Core/Services/InFlightTrackingService.swift:227`)
  - Skip the update (return early) when dt <= 0.1 instead of latching a stale derivative, and low-pass filter vSpeed the same way accelMagnitudeAverage is filtered (line 255) before using it for phase thresholds and the 'VERTICAL SPEED' tile.

- **[low] InFlight** — Auto-started demo tracking not stopped if user backgrounds/re-enters before onDisappear ordering (`JetSetter Pro/Features/InFlight/InFlightView.swift:79`)
  - Track ownership more robustly: clear didAutoStartDemoTracking whenever the user manually toggles tracking, and consider keying activeFlightNumber/activeDestinationCity to the currently presented flight rather than last-writer-wins on the singleton.

- **[medium] Intelligence** — Gate-closing ding fires even after the user dismisses the card (`JetSetter Pro/Features/Intelligence/TravelIntelligenceViewModel.swift:127`)
  - Move the AudioAlertService side effect out of the pure evaluator. Compute candidates side-effect-free, apply the dismissedKeys filter, and only after selecting `next` (line 45) trigger the ding for the surviving card if it is a leaveNow/not-checked-in signal. That keeps the alert tied to a card actually shown to the user.

- **[medium] Intelligence** — Coverage gap: no proactive card between 4h and 12h before departure (`JetSetter Pro/Features/Intelligence/TravelIntelligenceViewModel.swift:156`)
  - Close the gap: either extend the check-in window lower bound (e.g. hours <= 24 with no >12 floor, since check-in typically stays open until ~1h before) or add a mid-range 'Head to the airport soon' signal covering 4h-12h. At minimum change line 156 to `hours > 4` so check-in coverage is continuous down to the imminent window.

- **[low] Intelligence** — Trip-starting-soon countdown truncates hours instead of rounding (`JetSetter Pro/Features/Intelligence/TravelIntelligenceViewModel.swift:188`)
  - Round to nearest and/or reuse a day-aware format: e.g. `Int(hours.rounded())` or show 'tomorrow'/'in 2 days' for the 24-48h range instead of a raw hour count.

- **[medium] Itinerary** — addEvent returns EKEvent.eventIdentifier which is an implicitly-unwrapped optional and can be nil (`JetSetter Pro/Core/Services/CalendarService.swift:101`)
  - Guard the identifier: `guard let id = event.eventIdentifier else { throw CalendarError.eventSaveFailed(...) }; return id`. Also consider validating defaultCalendarForNewEvents up front and surfacing a clear 'no writable calendar' error.

- **[medium] Itinerary** — Calendar sync stores a stale local ID; deleting an item that was synced leaves an orphan calendar event (`JetSetter Pro/Features/Itinerary/ItineraryViewModel.swift:79`)
  - In deleteItem (and deleteTrip), for any item with a non-nil calendarEventIdentifier, fire an async CalendarService.removeEvent(identifier:) before/after removing it locally. Since these funcs are non-async, spin off a detached Task, or make them async and await removal.

- **[medium] Itinerary** — Calendar event created from itinerary times has no time zone anchoring, causing wrong times across DST/travel (`JetSetter Pro/Core/Services/CalendarService.swift:87`)
  - Capture and store the intended time zone on ItineraryItem (or derive from location) and set event.timeZone accordingly. At minimum document that times are stored as absolute instants so the picker UX matches.

- **[medium] Learning-Engine** — weightedRanking has no tiebreak — equal-weight rankings are nondeterministic (`JetSetter Pro/Core/Services/Learning/TravelProfileEngine.swift:205`)
  - Add a deterministic secondary/tertiary key, e.g. `.sorted { $0.weight != $1.weight ? $0.weight > $1.weight : ($0.count != $1.count ? $0.count > $1.count : $0.value < $1.value) }` before applying prefix(limit).

- **[low] Learning-Engine** — mostCommon tiebreak returns the OPPOSITE of what its comment promises (`JetSetter Pro/Core/Services/Learning/TravelProfileEngine.swift:242`)
  - Flip the tie comparator to `$0.key < $1.key` to actually yield the lexicographically smallest key on a tie (matching the comment), or update the comment to say 'largest' — pick one and make code and doc agree.

- **[medium] Learning-Engine** — recompute() does synchronous UserDefaults JSON decode of 3 stores on the main actor on every single record() (`JetSetter Pro/Core/Services/Learning/TravelProfileStore.swift:66`)
  - Debounce/coalesce recompute (e.g. schedule a single recompute on the next runloop via a pending flag), or decode the three history arrays off-main and only assign `profile` on the main actor. At minimum, cache the decoded history and invalidate only when those keys actually change.

- **[low] Learning-Engine** — spendStats reports a plain arithmetic mean, mixing currencies-correctly but ignoring outliers and count-weighting (`JetSetter Pro/Core/Services/Learning/TravelProfileEngine.swift:216`)
  - Use a median (or trimmed mean) for the 'typical' figure to resist single large receipts, and drop the redundant `!items.isEmpty` check. Optionally expose both median and count so the prompt can say '~median across N'.

- **[medium] LocalExperience** — Free experiences render as "$" (budget) instead of free (`JetSetter Pro/Features/LocalExperience/ExperienceModel.swift:62`)
  - Special-case free: `var symbol: String { self == .free ? "Free" : String(repeating: "$", count: rawValue) }`. Removing the max(_,1) also makes budget=$, moderate=$$, etc. render correctly (currently budget and free both show "$").

- **[medium] LocalExperience** — Past/expired events are bucketed into "Right Now" (`JetSetter Pro/Features/LocalExperience/ExperienceModel.swift:96`)
  - Guard the lower bound, e.g. treat negative deltas as expired and either drop them or bucket separately: `if hours < 0 { return .thisTrip /* or filter out */ }` before the `< 3` / `< 12` checks; ideally filter expired events out of the feed entirely.

- **[low] LocalExperience** — Time-slot bucketing uses device timezone, not destination timezone (`JetSetter Pro/Features/LocalExperience/ExperienceModel.swift:95`)
  - Carry the destination TimeZone on the trip/Experience and compute the buckets using a Calendar whose timeZone is set to the destination, or key 'tonight' off the destination-local hour of eventDate rather than a raw hours-from-now delta.

- **[medium] LoyaltyVault** — Accounts with an unknown programID are shown in the Airline section but excluded from TOTAL MILES (`JetSetter Pro/Features/LoyaltyVault/LoyaltyViewModel.swift:84`)
  - Make the fallback consistent. Either drop unknown-program accounts into a distinct 'Other' group and exclude them from both totals, or have the totals include the same fallback kind used by groupedAccounts. Practically: compute kind once per account with a single helper (e.g. `kind(for: account)`) and use it in both the totals and the grouping so they can never diverge.

- **[medium] LoyaltyVault** — Summary total is round-tripped through a locale-formatted string, corrupting it in grouping locales (`JetSetter Pro/Features/LoyaltyVault/LoyaltyVaultView.swift:85`)
  - Pass the raw Int into summaryColumn and let AnimatedCounter format it, rather than formatting to a String and re-parsing. Change summaryColumn's signature to take `value: Int` (target) plus a formatter, and drop the `value.filter(\.isNumber)` reconstruction entirely.

- **[medium] LuggageTracker** — Add-Bag accepts tag numbers that WorldTracer will always reject (`JetSetter Pro/Features/LuggageTracker/LuggageTrackerView.swift:314`)
  - Validate the tag on save: strip whitespace and require 7-10 numeric digits before persisting (mirroring traceBag's rule), and surface an inline validation error / disable Save if a non-empty tag is malformed. This keeps stored data trackable and gives immediate feedback.

- **[medium] Misc-Services** — Departure 'leave by' time can silently be in the past with no signal beyond color (`JetSetter Pro/Core/Services/DepartureOptimizerService.swift:156`)
  - Add an 'already late / infeasible' state when minutesRunway < 0 (e.g. urgency .critical but a distinct label like 'Departure window passed'), and guard the DepartureBriefing so IRIS doesn't quote a leave-by time that is in the past.

- **[medium] Misc-Services** — TSA estimate uses Calendar.current (device timezone) for an airport in another timezone (`JetSetter Pro/Core/Services/TSAWaitEstimator.swift:63`)
  - Resolve the airport's timezone (from an airport DB / coordinate lookup) and build a Calendar with that TimeZone before extracting hour/weekday, so peak modeling reflects local-airport time rather than device time.

- **[low] Misc-Services** — Packing NLTagger 'seen' set only checks labels, never contains extracted raw nouns (`JetSetter Pro/Core/Services/PackingListService.swift:216`)
  - Track a single normalized set (or check against both labels and keywords consistently), and fix the restaurant guard to test a value that is actually inserted (e.g. `!found.contains("dining out")`).

- **[medium] Misc-Services** — Anthropic API key sent directly from the device / empty-key request proceeds (`JetSetter Pro/Core/Services/PackingListService.swift:298`)
  - Route Claude calls through a backend proxy that holds the key, or at minimum short-circuit with a clear error when AnthropicConfig.apiKey.isEmpty so callers can distinguish 'not configured' from 'network failure'. Never ship the provider key in the client.

- **[medium] Network-Layer** — Flight ident / baggage tag interpolated into URL path without percent-encoding (`JetSetter Pro/Core/Network/Endpoints.swift:38`)
  - Percent-encode the path component before interpolation: ident.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), or build the URL with URLComponents and append the path segment. This prevents both silent nil failures and path-injection from stray '/'/'#' characters.

- **[medium] Network-Layer** — 429 Retry-After header only parsed as integer seconds, ignoring HTTP-date form (`JetSetter Pro/Core/Network/APIClient.swift:163`)
  - If TimeInterval(value) fails, attempt to parse value as an HTTP-date with a DateFormatter (RFC 1123 / 'EEE, dd MMM yyyy HH:mm:ss zzz', en_US_POSIX, GMT) and return date.timeIntervalSinceNow (clamped to >= 0). This makes backoff and the user-facing message correct for date-form Retry-After responses.

- **[low] Network-Layer** — Retry-After can produce an unbounded sleep that hangs the request (`JetSetter Pro/Core/Network/APIClient.swift:173`)
  - Do not clamp a server-supplied Retry-After to the 10s ceiling used for backoff jitter. Either sleep the full suggested value (bounded by a larger sane max like 60s), or if the suggested wait exceeds the ceiling, fail fast with rateLimited(retryAfter:) rather than retrying too early and burning attempts.

- **[medium] OfflineKit** — Destination airport derived from first flight in unsorted items array — can cache weather for the wrong city on multi-leg/return trips (`JetSetter Pro/Core/Services/OfflineKitService.swift:203`)
  - Sort flight items by startDate and pick the first-by-time outbound leg's arrival code (or better, pick the arrival matching trip.destination). Consider caching weather for the actual trip.destination city rather than inferring it from itinerary text.

- **[low] OfflineKit** — extractAirportCode returns empty string on trips with no parseable flight, silently skipping weather with no signal (`JetSetter Pro/Core/Services/OfflineKitService.swift:210`)
  - Parse against multiple common separators (→, -, –, ' to '), fall back to geocoding trip.destination, and surface a distinct 'Couldn't determine destination airport' state rather than the generic 'Not cached'.

- **[low] Onboarding** — Currency button text dimmed based on wrong field (copy/paste bug) (`JetSetter Pro/Features/Onboarding/OnboardingView.swift:204`)
  - Remove the displayName dependency. Since currency is always set, render `currencyDisplayText` in full `.white` (or key the dimming off whether currency differs from a sentinel), e.g. `.foregroundStyle(.white)`.

- **[medium] Onboarding** — Home airport accepts arbitrary unvalidated text (`JetSetter Pro/Features/Onboarding/OnboardingView.swift:323`)
  - Trim and validate before saving, e.g. `let code = homeAirport.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(); if code.count == 3, code.allSatisfy(\.isLetter) { preferences.homeAirport = code }`. Optionally show inline validation feedback and set `.textInputAutocapitalization(.characters)` on the field.

- **[low] Onboarding** — Display name saved without trimming whitespace (`JetSetter Pro/Features/Onboarding/OnboardingView.swift:322`)
  - Trim first: `let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { preferences.displayName = name }`.

- **[medium] PackingList** — load() early-return prevents any remote re-sync after first successful load (`JetSetter Pro/Features/PackingList/PackingListViewModel.swift:33`)
  - Add an explicit refresh path: drop the guard and always attempt a remote fetch (comparing generatedAt to pick the newer copy), or add a separate refresh() invoked on pull-to-refresh / foreground that re-fetches regardless of in-memory state.

- **[low] PackingList** — Dead unreachable demo fallback branch inside generateList catch (`JetSetter Pro/Features/PackingList/PackingListViewModel.swift:85`)
  - Delete the unreachable if/else in the catch and keep only the errorMessage assignment, or, if a real generation failure in demo mode should still show curated data, restructure so the fallback is actually reachable (the top-of-function guard already short-circuits demo mode).

- **[low] PackingList** — deleteItems(at:in:) is unused dead code with fragile offset mapping (`JetSetter Pro/Features/PackingList/PackingListViewModel.swift:194`)
  - Remove deleteItems(at:in:) (and the Array[safe:] helper if otherwise unused), or wire it up and add a comment asserting offset order must match groupedByCategory. The id-based deleteItem already covers the UI need.

- **[medium] Platform-Services** — Expense/trip dates round-tripped through a UTC date-only formatter shift the calendar day for users west of UTC (`JetSetter Pro/Core/Services/SupabaseService.swift:114`)
  - Format/parse these date-only columns using the user's current calendar/timezone (or store start-of-day in the local calendar), not UTC — since these are calendar dates, not instants. e.g. set dateOnly.timeZone = .current, or better, strip to a local start-of-day Date on decode so the day the user picked is preserved regardless of device timezone.

- **[medium] Platform-Services** — Trip-day 7:30am reminder silently never fires when the trip starts later the same day (`JetSetter Pro/Core/Services/NotificationManager.swift:202`)
  - Compute the actual 7:30 fireDate via Calendar.current.date(from: comps) and guard fireDate > Date() (return early or fire an immediate/near-immediate notification when 7:30 has already passed), mirroring the other schedulers.

- **[low] Platform-Services** — Watch 'clear next flight' sends an empty application context that iOS treats as no-change, so stale flight glance persists (`JetSetter Pro/Core/Services/WatchConnectivityService.swift:94`)
  - Send an explicit sentinel instead of an empty dict, e.g. context = [NextFlightSnapshot.userInfoKey + "_cleared": true] or a versioned empty payload the watch checks for, so the watch can actively clear its glance.

- **[low] Platform-Services** — Anonymous/email signup assumes a session is always returned; email-confirmation-required projects will throw and lose the account (`JetSetter Pro/Core/Services/SupabaseService.swift:491`)
  - Treat a session-less signup response as a distinct 'confirmation required' outcome rather than a hard parse failure: detect the missing tokens and surface a 'check your email to confirm' state instead of throwing a malformed-response error.

- **[medium] RentalCar** — deepLinkURL() interpolates unencoded, user-controlled location into a URL (`JetSetter Pro/Features/RentalCar/RentalCarModel.swift:163`)
  - Build the URL with URLComponents + URLQueryItem so values are percent-encoded, or drop the function entirely if the in-app-web flow is the only supported path. If it is meant to be used, wire book() to prefer deepLinkURL() and fall back to appStoreURL/websiteURL.

- **[medium] RentalCar** — Class filter chips can leave the user staring at an empty list with no way back (`JetSetter Pro/Features/RentalCar/RentalCarViewModel.swift:43`)
  - When hasSearched is true and vehicles is non-empty but sortedVehicles is empty, show a distinct "No cars match your filters" state with a "Reset filters" button that clears selectedClass and restores all providers, rather than the generic empty state that only offers a destructive Clear Search.

- **[medium] RentalCar** — numberOfDays uses wall-clock timestamps, so day count is off for same-day-of-week partial days (`JetSetter Pro/Features/RentalCar/RentalCarModel.swift:133`)
  - Compute numberOfDays from startOfDay-normalized dates (Calendar.startOfDay for both) so it reflects calendar-day spans, and/or derive the "× N days" label from the provider's actual billed-days figure rather than a locally recomputed diff so the multiplication reads consistently.

- **[low] RentalCar** — Provider result merge is not deterministic — Hertz vehicles get random UUID ids each search (`JetSetter Pro/Core/Services/RentalCarService.swift:144`)
  - Derive a stable id for Hertz from the response, e.g. "hertz-\(g.sippCode)" (SIPP code is the group key) or a hash of provider+sipp+make+model, instead of UUID().

- **[medium] Security-Services** — KeychainCredentials.store ignores accessibility when updating an existing item (`JetSetter Pro/Core/Services/Expense/KeychainCredentials.swift:41`)
  - Default accessibility to .whenUnlockedThisDeviceOnly for these credential blobs instead of nil, so secrets are never backed up or migrated unless a caller explicitly opts in.

- **[medium] Security-Services** — OfflineKit silently reports success when persistence fails (`JetSetter Pro/Core/Services/OfflineKitService.swift:189`)
  - Make cache() throwing (or return an optional/Result) and propagate encode/write failure so the UI can show 'caching failed'. Consider persisting to a file in the app support directory instead of UserDefaults for large payloads.

- **[medium] Security-Services** — Expedia client_secret is not URL-encoded in the form body (`JetSetter Pro/Core/Services/ExpediaAuthService.swift:47`)
  - Percent-encode each value (addingPercentEncoding with a form-safe allowed set, or build via URLComponents.percentEncodedQuery) before joining with '&'.

- **[low] Security-Services** — PassKit relevantDate reflection is fragile and mislabels non-boarding passes' dates (`JetSetter Pro/Core/Services/PassKitService.swift:74`)
  - Use the real API with availability: `if #available(iOS 18, *) { pass.relevantDates.first?.startDate }` else `pass.relevantDate`. Reflection on an NSObject subclass is not a reliable substitute.

- **[medium] Settings** — syncToCloud reports success even when nothing was decoded/synced (`JetSetter Pro/Features/Settings/SettingsView.swift:859`)
  - Distinguish 'no data' from 'decode failed'. Use try JSONDecoder().decode(...) (propagating the error into the catch) rather than try?, or track whether any sync actually occurred and report an accurate status. Consider surfacing a count ('Synced 12 trips, 34 expenses').

- **[medium] Settings** — Version-tap demo reset gesture is active in RELEASE builds (`JetSetter Pro/Features/Settings/SettingsView.swift:677`)
  - Wrap the entire tap-count gesture + confirmationDialog in #if DEBUG, matching the other presentation/developer affordances. This hidden reset should never be reachable in a production build.

- **[medium] Settings** — Cloud sync is upload-only and can overwrite newer server data (`JetSetter Pro/Features/Settings/SettingsView.swift:854`)
  - Implement a two-way sync (pull remote, merge by id/updatedAt, then push) or at minimum a pull-on-sign-in. If only push is supported for now, change the button label/copy to reflect 'Back up to Cloud' rather than implying multi-device sync.

- **[low] Settings** — Manual loved-one phone numbers are stored raw with no format validation (`JetSetter Pro/Features/Settings/LovedOnesSettingsView.swift:83`)
  - Validate/normalize the phone input (strip non-dial characters, require a minimum digit count, ideally libPhoneNumber-style normalization) before storing, and dedupe by normalized number so a contact isn't texted twice.

- **[medium] Subscription** — loadProducts() swallows errors, leaving paywall stuck on an infinite spinner (`JetSetter Pro/Core/Services/SubscriptionManager.swift:70`)
  - On catch, set purchaseError (or a dedicated loadError) to a message and show a Retry button in pricingSection when products is empty AND an error occurred, so the user can re-invoke loadProducts().

- **[low] Subscription** — Product sort predicate is not a valid strict-weak-ordering (`JetSetter Pro/Core/Services/SubscriptionManager.swift:69`)
  - Sort by an explicit rank, e.g. define an order index per product ID (annual=0, monthly=1, ...) and sort on that: `products = fetched.sorted { rank($0.id) < rank($1.id) }`.

- **[medium] Translator** — isTranslating reset in defer runs off the MainActor (`JetSetter Pro/Features/Translator/TranslatorView.swift:261`)
  - Move the isTranslating reset onto the main actor. Either annotate the closure/func @MainActor, or replace `defer { isTranslating = false }` with explicit `await MainActor.run { isTranslating = false }` in both the success and catch paths (or at the end after the do/catch).

- **[medium] Translator** — Scanner start failure and missing camera permission are swallowed silently (`JetSetter Pro/Features/Translator/TranslatorView.swift:337`)
  - Capture the startScanning() error and surface it (set errorMessage and dismiss the cover, or show an in-cover message). Check AVCaptureDevice.authorizationStatus(for: .video) before presenting and route .denied to a Settings prompt. Ensure NSCameraUsageDescription is present in Info.plist.

- **[medium] TravelEssentials** — find() substring match can resolve unrelated destinations to a wrong country (`JetSetter Pro/Core/Utilities/TravelEssentialsData.swift:69`)
  - Restrict the substring branch to token/word-boundary matches (split query on commas/whitespace and compare whole tokens to country names and ISO codes) rather than raw `contains`, and prefer the trailing token (typically the country in 'City, Country').

- **[medium] TravelWallet** — Check-in notification toggle initial state is never restored from scheduled state (`JetSetter Pro/Features/TravelWallet/CheckInCardView.swift:20`)
  - In loadCheckInLink() (or a dedicated .task), query UNUserNotificationCenter.current().pendingNotificationRequests() for id "checkin_\(flightNumber)_\(Int(departureDate.timeIntervalSince1970))" and set notificationScheduled accordingly so the toggle reflects reality.

- **[medium] TravelWallet** — checkInIsOpen / timeUntilCheckIn never refresh while the card is on screen (`JetSetter Pro/Features/TravelWallet/CheckInCardView.swift:28`)
  - Wrap the countdown/button in a TimelineView(.periodic(from: .now, by: 60)) or add a Timer.publish to recompute checkInIsOpen, so the button enables and the countdown updates live.

- **[medium] TravelWallet** — Boarding time rendered in device-local timezone, not departure-airport time (`JetSetter Pro/Features/TravelWallet/BoardingPassDetailView.swift:369`)
  - Persist a departure timezone (IATA-derived or from the pkpass) in rawData and format boarding/departure times in that zone, or explicitly label times as local-device time. At minimum store and use a departure_timezone identifier for boardingTimeString.

- **[low] TravelWallet** — Optimistic-delete rollback can insert at a stale index (`JetSetter Pro/Features/TravelWallet/WalletViewModel.swift:100`)
  - On rollback, re-insert by value and re-sort instead of by captured index: items.append(removed); items.sort { $0.date < $1.date }. This is order-safe and crash-safe regardless of interleaving.

- **[low] TravelWallet** — groupedByTrip sort comparator is incorrect / incomplete (`JetSetter Pro/Features/TravelWallet/WalletModel.swift:176`)
  - Either delete groupedByTrip until needed, or implement a total-order comparator that puts active-containing groups first, then nil-tripId, then all-completed, with a stable tie-breaker (e.g., earliest item date).

- **[medium] TripJournal** — Photo fetch upper-bound includes an extra full calendar day (`JetSetter Pro/Features/TripJournal/TripJournalView.swift:308`)
  - Clamp to the end of the trip's last calendar day: pass Calendar.current.startOfDay(for: trip.endDate) advanced by one day (via date(byAdding:.day,value:1)) instead of addingTimeInterval(86400), or use dateInterval(of:.day,for: trip.endDate).end. Also normalize the lower bound to startOfDay(trip.startDate) so morning-of-departure photos aren’t excluded when startDate has a nonzero time.

- **[low] TripJournal** — MockDataService demo mode grants photo access UI even when the user explicitly denied it on-device (`JetSetter Pro/Features/TripJournal/TripJournalView.swift:301`)
  - Gate the demo override on running in the simulator (or on a flag that means 'no real photo library available'), e.g. #if targetEnvironment(simulator), rather than the global MockDataService.isEnabled, so a genuine denial on a physical device still surfaces the deniedCard.

- **[medium] VisaLookup** — Inconsistent no-data vs no-match default (France when no trip, Japan when unmatched) (`JetSetter Pro/Features/VisaLookup/VisaLookupView.swift:11`)
  - Pick one deterministic default path and centralize it. Prefer surfacing an explicit unmatched state over any hardcoded country so the badge/fee/rules never appear authoritative for the wrong country.

- **[medium] VisaLookup** — find() substring matching can return the wrong country for free-text destinations (`JetSetter Pro/Core/Utilities/VisaRequirements.swift:214`)
  - Tighten matching: prefer exact ISO-code and exact countryName equality first (already done), then only fall back to substring matching on a whitelist of known aliases/city→country mappings, and require the matched token to be word-bounded (e.g. split the query on ',' / whitespace and compare tokens) rather than raw `contains`. Consider returning nil for ambiguous multi-match cases instead of `.first`.

- **[low] VisaLookup** — Trip already in progress on the departure day is excluded from auto-detect (`JetSetter Pro/Features/VisaLookup/VisaLookupView.swift:204`)
  - Filter by end-of-trip instead of start (e.g. `$0.endDate >= Date()`), or include trips whose window currently contains `Date()`, so an in-progress trip is preferred for the visa lookup.


## Business-Logic Improvements (208)


### High impact (25)

- **AirportMap — Gate-level coordinates are not in Apple Maps, so 'min walk' times are fabricated from a centroid match** (AirportMapViewModel.resolveGateCoordinate (lines 223-244) → estimatedMinutes / wayfinding card)
  - resolveGateCoordinate does an MKLocalSearch for a string like 'Gate A12 SFO' and returns response.mapItems.first.placemark.coordinate. Apple Maps does not expose individual gate coordinates as searchable POIs, so this returns the airport centroid (or an arbitrary nearby match), making the resulting 'NN min walk' and the drawn polyline essentially meaningless — MKDirections .walking will also often route via outdoor roads, not concourses. The feature presents a precise-looking number the app cannot actually compute. Recommend shipping a bundled per-airport gate coordinate/graph dataset (or an internal wayfinding graph) for the ~20 supported airports and computing walk time from that; at minimum, label the estimate as approximate and validate the resolved match is inside the airport bounds before trusting it.

- **Booking — 'Add to Itinerary' can be missed, losing the only record of the booking** (HotelDetailView.swift BookingConfirmationView (addHotelToItinerary / bookingSuccessView))
  - The booking is only ever persisted if the user explicitly taps 'Add to Itinerary' before dismissing; the 'Done' button dismisses without saving. Given the app tells the user the booking is confirmed, the stay should be auto-added to the itinerary on confirmation (with the option to remove), so a confirmed booking is never silently discarded.

- **Carbon — Radiative-forcing-inflated figure is reused for offset cost and physical comparisons, overstating them ~1.9x** (CarbonFootprintView.swift offsetCard (line 136) + comparisonCard (lines 108-118), CarbonMath.kg (line 299))
  - CarbonMath.kg multiplies by a 1.9x RF factor, turning the number into a warming-equivalent (CO2e), not physical CO2 mass. estCost = co2/100*0.80 (line 136) then prices offsets off this inflated number, but offset providers retire actual CO2 tonnage — so the shown cost is ~1.9x too high. Likewise 'tree-years of sequestration' (co2/21) and 'driving X km' (co2*5) describe physical CO2 processes but are fed the RF-inflated value, overstating them ~1.9x. Compute a physical co2Mass (without RF) and use it for offset cost, tree-years, and driving comparisons; reserve the RF-adjusted CO2e for the headline warming-impact number, and label the two distinctly so the methodology card claim stays honest.

- **CheckIn — Seat map is entirely static mock data unrelated to the real flight** (CheckInFlowView.seatMapView (lines 150-176))
  - The cabins, row ranges, seat letters, and taken-seat sets are hardcoded regardless of which flight is being checked into. A user checking in to any flight sees the same AA169-style 1-2-1 First/Business layout and the same 'Economy: Sold out'. This is acceptable for a demo but misleads real users about availability and their own aircraft. Drive the map from the flight's aircraft type / seat inventory, and at minimum ensure the user's actual assigned seat and cabin are represented.

- **CheckIn-Services — 24h check-in window is hardcoded and wrong for many carriers** (CheckInService.scheduleCheckInNotification (line 108) and body text (line 113))
  - Check-in does NOT universally open exactly 24h before departure: many international carriers open 48h, 36h, or 30h before (Emirates/Qatar/Lufthansa often 48h; some LCCs earlier), and the notification even hardcodes 'check-in is now open'. Firing exactly at T-24h can be hours late (user misses free seat selection) or the message is simply false. Store a per-airline check-in-open lead time (the fallback dictionary is the natural place, and Amadeus/airline data can supply it) and schedule against that, defaulting to 24h only when unknown.

- **Data-Services — FX conversion supports only base->target, silently returns nil for cross-currency and same-currency** (ExchangeRateService + CurrencyModel.ExchangeRates.convert)
  - rates(for:) fetches a rate table keyed on ONE base currency, and convert(amount:to:) returns nil whenever the target isn't in that table (CurrencyModel.swift:17). Two real user cases break: (1) converting a currency back to base (e.g. EUR->USD when base=USD) has no self-rate unless the API includes base:1.0, and (2) converting between two non-base currencies (EUR->JPY) is impossible without re-fetching. Since rates are relative to base, derive cross rates as amount * (rates[to] / rates[from]) and treat rate-to-base as 1/rates[from]. This makes the converter work for any pair from a single fetch.

- **DepartureOptimizer — Boarding buffer is a fixed 30 min regardless of domestic vs international** (DepartureOptimizerService.recommend (boardingBufferMinutes default 30) / DepartureOptimizerView.refreshRecommendation)
  - The view never passes boardingBufferMinutes, so every flight uses 30 min gate buffer. International departures typically want 2-3h at the airport (passport control, longer security, earlier boarding-gate closure). Detect international by comparing origin vs destination country (you already resolve both IATA codes) and raise the boarding + arrival buffer accordingly; expose it as a user-adjustable setting.

- **DepartureOptimizer — Recommendation is computed once and never refreshes as time passes** (DepartureOptimizerView.task/refreshRecommendation)
  - leaveAt, minutesUntilLeave, and urgency are computed on appear (and on lane change) but never re-run. A user who opens the screen 40 minutes early and leaves it open will see a frozen 'in 40 min' and stale traffic. Add a periodic refresh (Timer/AsyncStream every ~60s while visible) so the countdown, urgency color, and 'You're X min behind. Go now.' state stay live.

- **Disruption-Services — Rebooking eligibility fails open to true, showing a rebook CTA that may be non-functional** (DisruptionResponseEngine.checkRebookingEligibility (lines 295-319))
  - The method returns true on missing Duffel order ID, empty config, non-2xx response, or any network error. Combined with the fake amadeus.com rebooking URL, a user whose booking was NOT made through Duffel (most users, given the order ID comes from a boarding-pass wallet item's rawData) will always see 'rebooking eligible' and be sent to a dead link. Prefer failing open only for transient network errors; when there is simply no Duffel order for the trip, treat rebooking as 'search alternatives only' and surface the airline's own manage-booking/rebook path rather than implying in-app change is possible.

- **DocumentVault — Add Document sheet ignores all user input and inserts fixed mock data** (DocumentVaultView.AddDocumentSheet (add(_:) line 404))
  - Tapping any row inserts a canned document (hardcoded number like 'X12345678', fixed issuing country, expiry computed as now + N years). There is no form to enter a real passport number, country, expiry, or photo. For a shipping build this means the vault can never hold the user's actual documents — it only ever stores demo values, making the feature non-functional as a product (and the encrypted-number machinery pointless). Replace the mock-row picker with a real entry form (type picker, number field, country, date picker, optional photo via PhotosPicker/scanner) feeding addDocument.

- **DocumentVault — Documents are single-device only with no backup or export, so users lose everything on device loss** (DocumentVaultStore (UserDefaults + ThisDeviceOnly key))
  - Persistence is local UserDefaults and the crypto key is ThisDeviceOnly (won't migrate in an iCloud/encrypted backup restore). The stated value prop is offline access to critical travel docs during an emergency — but if the phone is lost/stolen/replaced (exactly the emergency scenario), all documents are gone with no recovery. Offer an encrypted export (or opt-in encrypted iCloud/keychain-synced storage) so a replacement device can restore the vault.

- **Expense-Providers — Email PDF total sums mixed-currency expenses as if one currency** (EmailPDFProvider.messageBody (EmailPDFProvider.swift:104-118))
  - messageBody reduces all expense.amount into a single total and labels it with only the first expense's currency (currency = expenses.first?.currency ?? "USD"). A traveler with EUR, GBP, and USD receipts gets a nonsensical total like 'EUR 842.00' that mixes three currencies at 1:1. Group and subtotal by currency, or convert to a home currency using the app's exchange-rate service before totalling, and label each subtotal correctly.

- **ExpenseTracker — IRS mileage rate is hardcoded to 2024 and will silently under/over-reimburse** (ExpenseModel.swift:121-127 (irsMileageRatePerMile) used by logMileage and LogMileageView)
  - irsMileageRatePerMile is a static 0.67 labeled '2024 IRS standard rate' (the current date in this project is 2026-07-05, so it is already two years stale — the 2025 rate is 0.70). Every mileage expense is calculated and stored at the wrong rate for business reimbursement, and the stored expense freezes that rate forever. Make the rate date-aware (a lookup table keyed by year, selecting the rate for expense.date's year) so historical entries keep their correct-for-that-year rate and new entries use the current year. Also allow a user override for non-US travelers, since the IRS rate is US-specific.

- **Flight-Services — Bag estimate ignores international arrivals and immigration/customs** (BagDeliveryEstimator.swift:37)
  - estimate() only branches on a large-hub set vs typical, with a 12-35 min ceiling. For international arrivals the traveler clears immigration BEFORE reaching the carousel, and at hubs like LHR/CDG/JFK the wheels-down-to-bag gap is routinely 45-90+ min. Since IRIS uses expectedMinutes to time a curb ride pickup (IRISFlightActionsTool / IRISTriggers callers), a 27-min midpoint for an international arrival will schedule the ride far too early. Add an isInternational parameter (or infer from origin/destination country) and widen the estimate materially for international carousels.

- **GroundTransport — "Compare prices instantly" but options are never sorted or compared** (GroundTransportViewModel.fetchEstimates / GroundTransportView.rideList)
  - The prompt copy (GroundTransportView.swift:209) promises to "compare Uber and Lyft prices instantly," yet rideOptions = uber + lyft (VM:134) preserves API order, and the list groups strictly by provider (View:134-139) with no price ordering or cross-provider "cheapest"/"fastest" highlighting. Users must eyeball raw ranges across two sections. Parse the numeric low bound of each priceRange and surface a "Best price" / "Fastest" badge, and/or offer a sort toggle, so the screen actually delivers the comparison it advertises.

- **IRIS-Feature — Voice mode cannot complete write actions hands-free** (IRISChatView.swift confirmPending / IRISVoiceController onUtterance)
  - When a spoken utterance triggers a write tool, IRISAgentService stages an IRISPendingAction and speaks the reply (IRISVoiceController.swift:235-238), but committing requires a manual tap on IRISConfirmationCard. A driver/hands-free user is told the action is ready yet cannot complete it by voice — the whole point of voice mode. Add a spoken confirmation path: when voice is active and a pending action exists, have IRIS ask 'Shall I confirm?' and accept a yes/no utterance to call action.commit()/cancelPendingAction(), then feed the result back through recordActionResult and speak it.

- **Learning-Engine — Airline/city ranking treats free-text values as identity keys with no normalization, splitting the same entity** (weightedRanking + normalizeBrand/normalizeCity (lines 193-208, 254-262))
  - Airlines come in as raw codes AND names from three sources: flight signal 'airline' attribute, loyalty value, and boarding-pass airline. 'AA' vs 'American Airlines' vs 'American' become three separate ranked entries, fragmenting weight so no airline reaches meaningful confidence. normalizeBrand only trims whitespace and normalizeCity only splits on comma. Add a canonicalization pass (IATA code<->name map for airlines, case/diacritic folding for cities/brands) before ranking so the same entity accumulates its full weight.

- **LuggageTracker — Report Missing button is a no-op stub** (BagDetailView.swift:163-176 (bottomCTAs))
  - The 'Report Missing' CTA has an empty action (`// Stub — report missing`). It is presented prominently on every bag detail screen regardless of status, so a user with a genuinely lost bag taps it and nothing happens — the worst moment to silently no-op. Either wire it to a real action (file a WorldTracer PIR / open the airline's lost-baggage flow / set status to .missing and start monitoring) or hide/disable it with a 'coming soon' state until implemented.

- **Misc-Services — Rental fan-out fails the whole search if any single provider throws** (Core/Services/RentalCarService.swift:56)
  - withThrowingTaskGroup + `for try await` means the first provider that throws (timeout, 500, decode failure at Hertz) cancels the group and aborts the entire search, so a user gets zero results even though Enterprise and National returned inventory. Make per-provider fetches return [] on failure (or collect partial results and only throw noVehiclesAvailable when ALL providers came back empty), so one flaky partner API doesn't hide every car.

- **More — Airport Map opens hardcoded JFK / Terminal 8 / Gate B14 instead of the user's real flight** (JetSetter Pro/Features/More/MoreView.swift:134 (AirportMapView destination))
  - The "Airport Map" card always launches AirportMapView(airportIATA: "JFK", terminal: "8", gate: "B14"), a fixed demo location, no matter where the user is actually flying. Every other card routes contextually, so this one silently shows the wrong airport for anyone not departing JFK. Resolve the current/next trip (the same nextOrLatestTrip pattern already used in this file, or HomeViewModel's origin resolution) and derive the IATA/terminal/gate from the upcoming flight segment; fall back to the user's home airport (preferences.homeAirport) rather than a literal JFK constant.

- **PackingList — Regenerate silently destroys user customizations and packed progress** (PackingListViewModel.regenerateList)
  - regenerateList (line 152) sets packingList = nil then generates a brand-new PackingListResult with a fresh id and AI items only, permanently discarding all isCustom user-added items and every isPacked check-off with no confirmation. A user mid-trip who packed 80% and added personal items loses everything on an accidental tap of the toolbar Regenerate button. Add a confirmation dialog and/or merge: preserve isCustom items and re-map isPacked for regenerated items whose name still matches.

- **Platform-Services — Sync only ever upserts — locally deleted trips/expenses resurrect on the next device** (SupabaseService.swift:242 syncTrips / :262 syncExpenses)
  - syncTrips/syncExpenses POST with merge-duplicates upsert and early-return on empty (lines 244, 264), and there is no delete-diff. If a user deletes a trip on device A, it's simply absent from the next upload; the row remains in Supabase and re-downloads to device A on fetch (and stays on device B). Deletions never propagate. Add an explicit delete/tombstone step (compute rows present remotely but absent locally and DELETE them, or maintain a deleted-ids set) so removals actually sync.

- **TravelEssentials — Emergency call rows only copy the number — no dialer hand-off even where allowed** (TravelEssentialsView.swift callRow (lines 224-253))
  - The code comment (§7.7) claims iOS can't place PSTN calls in-app, so tapping an emergency number only copies it to the clipboard and shows a toast. This is incorrect: `UIApplication.shared.open(URL(string: "tel://112"))` is fully supported and is the expected behavior for an emergency reference. In a real emergency, forcing the user to copy '112', leave the app, open Phone, paste, and dial adds dangerous friction. Offer a real 'Call' action (tel: URL) with copy as a secondary/long-press option.

- **TravelWallet — Fabricated boarding-pass fields presented as real (GROUP 1, SEQUENCE 048, fake QR)** (BoardingPassDetailView.swift (detailsBlock lines 267-268, qrPayload lines 330-341))
  - GROUP is hardcoded to "1", SEQUENCE to "048", and qrPayload builds a non-standard "M1 ..." string described in-code as making it "look authentic when scanned." A traveler could try to board with this and be turned away, or trust a wrong boarding group. Only render GROUP/SEQUENCE/QR when derived from a real imported pkpass barcode; otherwise omit them or clearly label the view as a summary, and render the actual PKPass barcode payload when pkpass_data exists rather than synthesizing one.

- **VisaLookup — Schengen 90/180 rule is stated but not computed against the user's actual trips** (VisaLookupView requirementCard + VisaRequirements Schengen entries)
  - Every Schengen country shows "Max stay 90 days" plus a note about the 90-days-in-any-180-day rule across all member states, but the app already stores the user's trips. The per-country 90-day max is misleading because the allowance is shared across the whole Schengen area. Compute remaining Schengen days from the user's stored trip history (sum of Schengen days in the trailing 180-day window) and show a real "X of 90 days remaining" figure. This is the single highest-value smart feature the existing data enables and prevents users overstaying.


### Medium impact (104)

- **About — Feature-tour images use a fixed 540pt-tall page container that clips at large Dynamic Type / small devices** (JetSetter Pro/Features/About/AboutView.swift:136 (featureTour))
  - The TabView is pinned to `.frame(height: 540)` while each slide stacks a 420pt-max image plus a title and (multi-line, up to ~3 lines) caption plus 36pt bottom padding. On smaller devices (e.g. iPhone SE) or at accessibility Dynamic Type sizes the caption grows and the fixed 540pt page will clip the caption and/or the page-index dots underneath it. Make the image height and page height adaptive (e.g. drive image maxHeight off a GeometryReader or a ScaledMetric, and let the page height grow) so the caption is never truncated for large-text users.

- **AirportMap — Indoor-support list is a hardcoded 20-airport allowlist that will drift from Apple's actual coverage** (AirportMapViewModel.indoorMapsAirports / supportsIndoorMaps (lines 46-83))
  - supportsIndoorMaps gates the entire indoor experience on a static Set of 20 IATA codes. Apple adds/removes indoor venue coverage over time, so users at newly-supported airports get the 'Indoor Maps Unavailable' fallback while users at delisted ones get a broken indoor view. There is no way to detect coverage at runtime. Recommend detecting indoor availability dynamically (e.g. observe whether CLLocation.floor data arrives, or query venue data) and treating the static list only as a hint, or make the list remotely configurable so it can be updated without an app release.

- **AirportMap — Walking ETA uses raw MapKit expectedTravelTime with no security/boarding buffer for connections** (AirportMapViewModel.estimatedMinutes (246-250) and LayoverWayfindingSheet threshold (AirportMapView.swift:429))
  - The layover sheet colors the walk time red when minutes > 30 to warn of a tight connection, but the number is just walking time — it ignores time to clear security/immigration on international connections, terminal-change shuttles/trains, and boarding-gate-closes-before-departure buffers. A 25-min walk shown green can still be a missed connection. Recommend adding a configurable connection buffer (and a distinct buffer for international/terminal-change layovers) and comparing against the actual time remaining until boarding rather than a flat 30-minute threshold.

- **Assistant — Partial streamed reply is discarded on error/cancellation** (AssistantViewModel.sendMessage (lines 52-72))
  - The `defer` block clears streamingContent, and both the CancellationError path (line 67) and the generic error path (line 69) return without persisting whatever text already streamed. If a response streams 90% then the connection drops, the user sees the text vanish and gets a generic error with nothing saved. Consider committing a non-empty partial reply as an assistant message (optionally flagged 'response interrupted') instead of throwing it away.

- **Assistant — conversationHistory grows unbounded and is sent in full to Claude every turn** (AssistantViewModel.conversationHistory / AIService.streamFromClaude (line 173))
  - Every turn resends the entire history to Claude with max_tokens 1024. A long chat will steadily inflate input tokens (cost + latency) and eventually risk the model context limit with no trimming. Cap the history (e.g. last N turns or a token budget) before building the request. Note the Apple Intelligence path ignores this array entirely and relies on its own session transcript, so behavior between providers already diverges.

- **Booking — Overlapping-trip matching can attach a hotel to the wrong trip** (HotelDetailView.swift:417-423 addHotelToItinerary trip selection)
  - The item is added to the FIRST trip whose date range overlaps the stay, else the FIRST trip in the array, else a new trip. Destination is never considered — a hotel in Tokyo can be attached to an unrelated overlapping trip to Paris, or dumped into trips[0]. Match on destination (searchParams.destination vs trip.destination) in addition to date overlap before falling back, and prefer creating a new trip over trips[0] when nothing matches.

- **Booking — Prices display raw currency code + integer, dropping cents and localization** (BookingModel.swift formattedNightlyPrice/formattedTotalPrice (77-86) and row/detail displays)
  - Prices are rendered as '\(currency) \(%.0f value)' e.g. 'USD 420', truncating any fractional amount and using the ISO code instead of a symbol/locale-aware format. For totals this can mis-state the price by up to ~1 unit and looks unpolished. Use Decimal + Double parsing is also lossy for money; parse to Decimal and format with .currency(code:) so '$462.50' renders correctly and rounding never silently drops cents.

- **Carbon — Class multiplier and passenger count are applied to a per-passenger base, which over-counts group business/first bookings** (CarbonMath.kg (lines 300-305) + resultCard PER PERSON (line 93))
  - kg() = distance * perPassengerKmFactor * classMultiplier * passengers. For N passengers all in business (2.9x), total scales as N*2.9, which is defensible, but the class multiplier is applied uniformly to every passenger with no way to mix cabins (common for families/couples booking one premium + one economy). Also, the ICAO class multipliers should be normalized so a full aircraft's summed per-class emissions reconcile to actual fuel; using raw 1.0/1.5/2.9/4.0 as absolute multipliers over-counts a full premium cabin. Consider per-passenger cabin selection and calibrating multipliers against a load-factor-normalized baseline.

- **CheckIn — Confirming step is a fixed 1.5s fake and never surfaces failure** (CheckInFlowView.confirmingStep (lines 291-294))
  - The 'Checking in with American Airlines…' step always advances to success after a fixed sleep with no real network call and no failure branch. Real check-in can fail (seat gone, document missing, check-in window closed). When wired to a backend, add an error path back to the seat map with a retry, and reflect the actual carrier name rather than hardcoding American Airlines (the flight may be any airline).

- **CheckIn — Success screen and persistence run even if the confirmed seat is unavailable** (CheckInFlowView.seatButton / successStep (lines 221-249, 316-322))
  - Because only Business is selectable and selection is guarded, the user can't tap a taken seat — but selectedSeat can still be a wallet seat that the mock 'taken' set marks as taken (e.g. a First/Premium seat), and the flow will happily confirm it and show 'Seat X confirmed'. Validate that the final selectedSeat is not in any taken set before advancing to confirming, and block confirmation with an inline message otherwise.

- **CheckIn-Services — Amadeus success is only cached in-memory; hardcoded fallback URLs go stale with no refresh path** (CheckInService fallbackAirlines (lines 221-244) and fetchFromAmadeus)
  - Resolved Amadeus results are never persisted, so every launch re-hits the API (or falls back). The fallback dictionary is comment-dated 'April 2026' and warns URLs rot. Persist the last successful Amadeus CheckInResult per IATA code (UserDefaults/disk) and prefer it over the static dictionary when the network fails, so users get the freshest known URL rather than a potentially-dead hardcoded one.

- **CheckIn-Services — checkInResult returns nil for any airline outside the 20-carrier fallback when Amadeus is unavailable** (CheckInService.checkInResult / fallbackResult (lines 86-98, 246-256))
  - If credentials aren't configured (hasCredentials false) or the API fails, any airline not in the 20-entry dictionary yields nil and the UI dead-ends at 'Check-in link unavailable.' A large share of real itineraries use regional/other carriers. Provide a graceful last resort: construct a Google/airline search deep link or surface the airline's known domain so the user always gets somewhere actionable rather than a dead end.

- **CurrencyTracker — Converter direction is fixed home->destination with no swap** (CurrencyExpenseView.swift converterCard (lines 61-90))
  - The converter only goes home->destination (input labeled homeCurrency, output destination). Travelers most often want the reverse: 'what is this 1500 yen price in my home currency?'. The arrow.left.arrow.right icon (line 72) implies a swap that doesn't exist. Make it a real toggle, or add a second reciprocal line, so users can convert both directions.

- **CurrencyTracker — Rates load only on view appear; stale/failed loads leave conversions permanently nil** (CurrencyExpenseViewModel.load()/backfillConversions (lines 51-63, 102-110))
  - load() runs once via .task. If rates fail, errorMessage is set but never surfaced in the UI (no view reads vm.errorMessage), and expenses added while rates are nil get convertedAmount=nil. backfillConversions only runs on the next successful load(). Users who add expenses offline see them counted incorrectly (see summary bug) and get no retry affordance. Add a visible error banner with a retry button, and re-run backfill/updateSummary automatically when rates later become available.

- **CurrencyTracker — Destination currency guessed by substring match on trip.destination, with silent wrong fallback** (CurrencyExpenseRouterView.destinationCurrency (lines 328-360))
  - The hard-coded city/country map (only ~30 entries) falls back to the user's HOME currency when the destination is unknown (line 359). That means a trip to, say, Portugal or Egypt silently tracks expenses in the home currency, so every conversion is 1:1 and the whole feature quietly does nothing useful without any indication. The substring match is also fragile ('india' matches nothing helpful for 'Indianapolis'-style strings, and 'uk' would match any destination containing those two letters e.g. 'Fukuoka'). Prefer resolving currency from a proper country/currency dataset or Locale, let the user override the destination currency in-app, and when unknown prompt the user rather than defaulting to home currency.

- **Data-Services — Exchange rate cache TTL is 6h but comment/header claims 'daily refresh' — stale rates for expenses** (ExchangeRateService.rates / ExchangeRates.isFresh)
  - The file header says 'Daily refresh' but isFresh uses a 6-hour window (CurrencyModel.swift:23). open.er-api.com's free tier only updates once per day, so refreshing every 6h wastes calls without newer data, and there's no per-currency staleness surfaced to the user. Align the TTL with the provider's daily cadence and expose fetchedAt in the UI so users logging expenses know the rate's age (material for reconciling receipts).

- **Data-Services — Apple Intelligence session ignores conversation history entirely on first turn / provider switch** (AIService.streamFromAppleIntelligence)
  - The Apple path (AIService.swift:127) sends ONLY the new prompt and relies on the LanguageModelSession's internal transcript. But the session is recreated whenever systemPrompt changes (sessionForAppleIntelligence line 144) or after a context-window error (line 135), which silently discards all prior turns — the passed-in `history` array is never replayed. If the user's app was backgrounded and the session dropped, IRIS 'forgets' the conversation even though the ViewModel still holds history. On session (re)creation, seed the new session by replaying `history` so context survives session resets and matches the Claude path's behavior.

- **Data-Services — Calendar event save/remove doesn't call commit and assumes a default calendar exists** (CalendarService.addEvent / removeEvent)
  - addEvent sets event.calendar = eventStore.defaultCalendarForNewEvents (line 90), which is nil when the user has no writable default calendar (common with only subscribed/read-only calendars, or corporate MDM). save() then throws a non-obvious error. Guard for a nil default calendar and surface a clear 'no writable calendar' message, and consider passing commit:true or calling eventStore.commit() to ensure batched writes flush. Also removeEvent uses span:.thisEvent — for recurring itinerary events this only removes one occurrence.

- **DepartureOptimizer — TSA planning uses the midpoint, systematically under-buffering half the time** (DepartureOptimizerService.recommend line 149 (tsaWait.midpoint))
  - Planning to the midpoint of the TSA range means the traveler is late whenever the real wait lands in the upper half of the estimate. For a 'don't miss your flight' tool, plan to the upper bound (or upper bound minus a small margin) and show the range separately, so the safe-by-default recommendation errs toward arriving early rather than exactly-on-average.

- **DepartureOptimizer — Non-US / unknown airports silently get a US-heuristic TSA estimate** (TSAWaitEstimator.AirportTier.of / DepartureOptimizerView (no origin-country awareness))
  - The tier tables are US-only; any international origin airport falls to .unknown → a 10-25 min band with US peak-hour/day multipliers and 'unrated' confidence, presented in the UI with the same authority as a real estimate. Either flag low-confidence estimates prominently in the LIVE CONDITIONS/breakdown card, or skip the security-line component for airports you can't estimate and say so, instead of showing a fabricated number.

- **DepartureOptimizer — Flight parsing assumes a rigid 'ORIGIN → DEST' location string** (DepartureOptimizerView.originAirportIATA/destinationAirportIATA (lines 505-513))
  - IATA extraction depends entirely on splitting item.location by ' → '. Any flight whose location is a full name, uses a different arrow/dash, or omits one leg yields a bad code, and coordinate(for:) returns nil → 'Couldn't read flight details.' with no recovery. Store structured origin/destination IATA on ItineraryItem rather than reparsing a display string, or validate the parsed codes against AirportCoordinates.isKnown and surface a clearer message when unresolvable.

- **DepartureOptimizer — MapKit ETA failure falls back to a flat 30-minute drive with no indication** (DepartureOptimizerService.recommend line 130 (driveSeconds ?? 30*60))
  - When calculateETA throws (offline, no route, overseas), drive time defaults to exactly 30 min and is shown in the breakdown/LIVE CONDITIONS as if it were live traffic ('Drive (live traffic)'). A user far from the airport could badly under-budget. Distinguish the fallback (e.g. straight-line distance × avg speed, and label it 'estimated, offline') so the number isn't presented as live when it isn't.

- **Disruption — bestAlternative advertised as the rebook CTA but the UI never uses it** (DisruptionModel.swift bestAlternative / earliestAlternative)
  - DisruptionEvent.bestAlternative (lowest price) and earliestAlternative are documented as 'preferred for the one-tap rebook CTA', but the dashboard shows no rebook CTA until the user manually taps an alternative (selectedAlt gate at DisruptionDashboardView.swift:404). The advertised one-tap flow silently doesn't exist. Either pre-select bestAlternative (or earliestAlternative for time-critical missed-connection/cancellation cases) so the CTA is immediately actionable, or remove the misleading doc. For a disruption where speed matters, defaulting to earliest-departure rather than cheapest is often the better product choice.

- **Disruption — Hotel email hard-codes delay minutes and omits cancellations** (DisruptionViewModel.openHotelEmail)
  - openHotelEmail (line 130) uses `delayMinutes ?? 0` and states 'estimated delay of {delay} minutes'. FlightSnapshot.delayMinutes is nil for cancellations and gate changes (per the model comment), so a cancelled-flight hotel email reads 'estimated delay of 0 minutes', which is wrong and confusing to the hotel. Branch the email copy on eventType: for cancellations say the flight was cancelled and arrival is uncertain; only mention a minute count when a real delay value exists.

- **Disruption-Services — Alternative-flight search reuses the disrupted leg's scheduled departure date, so a cancellation late in the day yields same-day-only alternatives** (DisruptionResponseEngine.searchAlternativeFlights / handleDisruption (lines 150-154, 197-243))
  - Alternatives are searched for exactly event.originalFlight.scheduledDeparture's date (departureDate=YYYY-MM-DD, UTC). For an evening cancellation there may be no remaining same-day flights, returning an empty list and 'no alternatives'. Also the date is computed in UTC (dateOnlyString), which can shift the search to the wrong calendar day for departures near midnight local. Search a window (same day + next morning) and derive the date in the origin airport's timezone.

- **Disruption-Services — Currency mismatch: search requests USD but displays whatever currency the offer returns; price shown without conversion** (DisruptionResponseEngine.searchAlternativeFlights (line 215) / mapAlternativeFlight (line 279))
  - currencyCode=USD is requested, but mapAlternativeFlight stores offer.price.currency verbatim. Amadeus may return prices in a different currency (or the sandbox uses EUR). The AlternativeFlight then carries a price+currency the UI likely renders as-is, so a $/€ mismatch can mislead the traveler on cost. Either enforce/convert to the user's locale currency, or make the currency prominent in the UI. Do not assume USD.

- **Disruption-Services — availableSeats is fabricated pseudo-random data presented as a real availability number** (DisruptionResponseEngine.mapAlternativeFlight (lines 261-267, 280))
  - availableSeats is a deterministic hash 2-10, not real inventory (Amadeus shopping offers omit seat counts). Presenting '5 seats left' style scarcity from fabricated data is misleading and, if surfaced as urgency, arguably deceptive. Either omit the seat count from the UI when unknown, label it as unavailable, or fetch real availability via a seatmap/pricing call before showing a number.

- **Disruption-Services — Poll only runs via BGAppRefreshTask (~10 min, best-effort) — no foreground/active-trip immediacy** (DisruptionMonitorService background scheduling (lines 86-109))
  - BGAppRefreshTask is throttled by iOS heuristics and frequently does not fire near the advertised 10-minute cadence (can be hours, or never for infrequently-used apps). For a disruption product this means alerts may arrive far too late to act on. Complement background polling with (a) a foreground refresh when the app becomes active during an active trip, and (b) server-side push (FlightAware Alerts/webhooks to your backend -> APNs) so time-critical cancellations/gate changes are delivered even when the app is fully suspended.

- **DocumentVault — No expiry notifications despite expiry being the core alerting model** (DocumentVaultViewModel.addDocument (line 136 TODO))
  - VaultDocument has a full ExpiryUrgency model (critical/warning/notice) but nothing schedules a local notification. A passport-expiry vault whose entire point is to warn you before travel that your passport is within 6 months of expiry silently never warns you unless you happen to open the screen. Schedule UNUserNotificationRequests at the 180/90/30-day thresholds when a document with an expiryDate is added/updated, and cancel them on delete.

- **DocumentVault — Entry-requirement passportValidityMonths is stored but never evaluated against the user's passport** (EntryRequirement + DocumentVaultViewModel.entryRequirements)
  - The requirements table encodes passportValidityMonths (e.g. 6 months for Australia/Thailand) — the single most common reason travelers get denied boarding — but no code compares it to the user's stored passport expiryDate versus their trip date. entryRequirements(for:) is also not called anywhere in this feature's views. Wire the checklist into the trip destination and compute 'your passport expires X, which is < 6 months after your return — you may be denied entry', which would be genuinely differentiating and safety-relevant.

- **Expense-Providers — OAuth expense payloads always send amount in cents regardless of currency exponent** (RampProvider/BrexProvider/DivvyProvider payload + OAuthExpenseProvider.payload (round(amount*100)))
  - Every provider computes minor units as Int(round(amount*100)). Zero-decimal currencies (JPY, KRW, VND) have no cents; multiplying by 100 sends 100x the true value to Ramp/Brex/Divvy, and three-decimal currencies (BHD, KWD) are also wrong. Map the currency to its ISO 4217 minor-unit exponent and scale accordingly (JPY -> *1, most -> *100).

- **Expense-Providers — ISO8601 date sent for transaction date drops the local calendar day near midnight** (OAuth payloads transaction_date/purchased_at (e.g. RampProvider.swift:35))
  - ISO8601DateFormatter() defaults to UTC. An expense created at 11pm local on the 4th serializes as the 5th in UTC, so the expense lands on the wrong calendar day in the accounting system — a real problem for per-diem and trip-date reconciliation. For date-only fields (Ramp transaction_date, Divvy transaction_date, Expensify 'created' already uses yyyy-MM-dd but with the device's default timezone), format the day using the trip's or the user's timezone explicitly, not UTC.

- **Expense-Providers — Expensify submit reports every expense as submitted based only on a 200 responseCode** (ExpensifyProvider.submit (ExpensifyProvider.swift:126-137))
  - On responseCode == 200 the code marks ALL expenses .submitted with a fabricated remoteID (their own UUID). Expensify's create job can partially reject individual transactions and returns per-row status; treating the whole batch as success can hide silently-dropped expenses. Parse the response's per-transaction results and map real outcomes/remote IDs, or at minimum surface the count Expensify reports as created versus submitted.

- **ExpenseExport — Non-mock users never see the success confirmation overlay** (ExpenseExportView.submit (ExpenseExportView.swift:327-334))
  - The rich SuccessAnimationView with a reference number is gated behind MockDataService.isEnabled && !(provider is EmailPDFProvider), so a real customer who successfully submits to Expensify/Ramp only gets a 3-second text banner and no reference/confirmation, while the demo build gets the celebratory overlay. Real submissions are exactly where a durable confirmation (and the provider's real remote IDs, which are already in perExpense) matter most. Show a confirmation for real submissions too, and prefer surfacing the actual remoteID from the result rather than a random 'JS-####' number that has no meaning to the expense platform.

- **ExpenseTracker — OCR/comment says Google Vision but UI claims Apple Intelligence; extraction has no currency detection** (ExpenseViewModel.scanReceipt (comment line 111) vs VisionOCRService; ScanReceiptView currency default (line 28-30))
  - The scanReceipt doc comment says 'Google Vision OCR' while the code calls VisionOCRService and the confirmation footer claims 'Suggested by Apple Intelligence' — clarify which is real to avoid a privacy/marketing mismatch (receipts may be sent off-device). Separately, OCR extracts only amount and merchant; currency defaults to the traveler's preferred currency (line 30). A receipt scanned abroad is very likely in the local currency, so the default is usually wrong and, combined with the mixed-currency total bug, compounds errors. Detect currency symbol/code from rawText during OCR and pre-select it.

- **Flight-Services — Carry-on-only bag wait of exactly 0 min tells the ride to arrive before the passenger deplanes** (BagDeliveryEstimator.swift:38)
  - For hasCheckedBag == false the estimate is 0-0 min. But even carry-on passengers need time to deplane, walk to the curb, and clear any arrivals hall — realistically 10-20+ min at a large hub. A literal 0 fed into ride timing means the car is dispatched at wheels-down. Return a small non-zero deplane+walk floor (scaled by hub size) even for carry-on, and rename the basis to reflect 'walk to curb' rather than 'no wait'.

- **Flight-Services — Bag estimator has no data for the airport code it's given and silently falls back to 'typical'** (BagDeliveryEstimator.swift:47)
  - Any code not in the 28-entry largeHubs set — including many busy mid-size and all regional/foreign airports — returns the same 12-25 'Typical airport' band. The basis string ('first bags usually within ~15 minutes') asserts confidence the model doesn't have. Consider a mid-tier bucket, and have the basis acknowledge lower confidence for unrecognized codes so IRIS can widen its ride-timing buffer accordingly.

- **Flight-Services — Live Activity staleDate/lifecycle never keyed to actual arrival — card can persist or expire wrongly** (FlightLiveActivityService.swift:65)
  - start() sets staleDate to scheduledDeparture + 4h. For a long-haul flight the user wants the card through arrival, not 4h after departure; for a short flight 4h is excessive lingering. The activity is only end()ed when InFlightTrackingService detects .arrived (which, per the bugs above, frequently never fires without GPS). Tie staleDate to a real arrival estimate and add a fallback auto-end (e.g. scheduled arrival + buffer) so the card neither expires mid-flight nor lingers indefinitely.

- **Flight-Services — Loved-ones takeoff/landing prompts fire without confirming the tracked flight matches the active context** (InFlightTrackingService.swift:334)
  - promptLovedOnes reads activeFlightNumber/activeDestinationCity which are set/cleared by InFlightView's onAppear/onDisappear. If phase transitions fire while the view isn't active (tracking started elsewhere, or context cleared on navigate-away), the loved-ones text goes out with nil flight number/destination, or a takeoff detected during a demo session could message real contacts. Gate the loved-ones notification on having valid, consented flight context and on tracking being real (not demo mode) so family isn't texted spurious or context-free milestones.

- **FlightBoard — User flight is pinned first regardless of its departure time, breaking the chronological board illusion** (FlightBoardData.generate / loadUserFlightRow)
  - The board is presented as a realistic Solari departures board, but generate() always prepends the user flight (line 16-18) ahead of sample departures that are strictly time-ordered from now. A user flight departing in 4 hours will sit above sample flights departing in 20 minutes, which reads as wrong for a 'Departures' board. Either merge the user flight into the time-sorted list (and visually highlight it via isUserFlight styling, which already exists) or make it an explicit 'YOUR FLIGHT' pinned section separated from the live board.

- **FlightBoard — Board never refreshes — times and statuses freeze at first render** (FlightBoardView.task / FlightBoardData)
  - Rows are generated once in `.task` (FlightBoardView.swift:102) from `now` at load. The 'LIVE' indicator and status thresholds (finalCall/boarding/onTime based on minutesAway) imply a live board, but nothing recomputes as time passes, so a flight sitting in 'BOARDING' will never advance to 'FINAL CALL'/'DEPARTED', and the header clock is a one-shot static string (boardDateString). Add a Timer/TimelineView to periodically regenerate rows (or at least re-evaluate statuses and drop departed flights) so the board actually behaves live.

- **FlightTracker — 'Updated X ago' timestamp never re-renders while the screen is open** (FlightTrackerView.swift:108-112, 193-198)
  - `relativeTime(from:)` is computed once from `lastUpdated` and only re-evaluates when the view body is re-rendered by some other state change. It shows 'just now' and then stays frozen because nothing ticks. Since a 'LIVE' badge sits right next to it, a stale 'just now' after several minutes is misleading. Drive it with a `TimelineView(.periodic(from:.now, by: 30))` or a Timer so the relative label counts up, or use `Text(date, style: .relative)` which SwiftUI updates automatically.

- **FlightTracker — Detail view never refreshes flight data; live-polling decision is frozen at appear time** (FlightDetailView.swift:58-62)
  - The `flight` is a `let` snapshot captured at navigation time. The `.task` starts live position polling only `if flight.isAirborne` at first appearance, but the flight's status/gate/times/progress are never re-fetched while the detail screen is open. A flight that departs (becomes airborne), gets a gate change, or gets delayed while the user is looking at it shows stale data with no live position. Add a periodic refresh of the flight status itself on the detail screen (or re-evaluate `isAirborne` and start polling when the flight transitions to airborne), not just the position track.

- **GroundTransport — Total failure of both providers surfaces as generic "No rides available"** (GroundTransportViewModel.fetchEstimates (lines 130-138, 165-168, 197-199))
  - Both fetchUberEstimates and fetchLyftEstimates swallow all errors and return []. If Lyft's token fetch fails (missing/invalid client credentials) AND Uber returns [] (bad server token, region unsupported, network down), the user sees "No rides available for this route. Try a different destination." — implying the destination is the problem when it is actually an auth/network failure. Track whether each provider errored vs. genuinely returned zero options, and show a distinct message (e.g. "We couldn't reach Uber/Lyft right now") so users don't waste time editing a perfectly valid destination.

- **GroundTransport — Reverse-geocoded pickup address can be empty and pickup is not re-detected before estimates** (GroundTransportViewModel.reverseGeocode (73-88) and fetchEstimates (100-103))
  - reverseGeocode joins compactMapped [name, locality, administrativeArea]; if all are nil it falls back to coordinateString — fine. But detectCurrentLocation runs once from init and on manual refresh only. A user who opens the screen before location resolves, types a destination, and hits search will get "Pickup location is not available yet" and must know to tap the location button. Consider auto-triggering a location retry inside fetchEstimates when pickupLocation is nil (with a short wait) rather than requiring the user to discover the refresh button.

- **Home — IRIS/Travel-Intelligence de-dup guard and cached queue can disagree** (HomeView.swift:44 vs HomeViewModel.reloadIRISSuggestions)
  - The view hides TravelIntelligenceCardView when IRISTriggers.shared.evaluate() (live, re-decoded) returns non-nil, while the IRIS hero card renders from viewModel.irisSuggestions (a snapshot cached at loadAll time). Because they read state at different moments, the hero card can be empty while the Intelligence card is hidden (or vice-versa) after dismissing a suggestion, producing a blank gap where a card should be. Drive both the hero card and the hide-decision from the same cached queue (topIRISSuggestion) so they stay consistent.

- **Home — Next-flight selection ignores flights currently in progress and multi-leg trips** (HomeViewModel.loadNextFlight)
  - upcoming filters $0.startDate > now, so a flight the user is currently on (departed but not landed) instantly disappears from Home and the whole nextFlight/departure/destination stack vanishes mid-journey. Consider keeping a flight 'current' until its endDate (or a buffer past startDate) so the tracker/check-in context stays visible while boarding/in the air.

- **Home — Departure card fallback shows persona-default numbers as if live** (HomeViewModel.loadDepartureRecommendation:120-126)
  - When no live recommendation is available (no GPS, geocode fail), the card falls back to DepartureBriefing.personaDefault and renders a concrete 'Leave by <time> · N min drive · TSA N min' with no urgencyLabel and no indication it's a canned estimate. A user could miss a flight trusting a generic 'leave by' time that isn't computed from their actual location/traffic. Either label the fallback as an estimate ('Approx.') or omit the specific leaveBy time when it isn't location-derived.

- **IRIS-Core — Budget-pacing nudge compares overspend magnitude across different currencies** (IRISTriggers.evaluateBudgetPacingNudge (IRISTriggers.swift:194-204))
  - Candidate 'worst' categories are compared by raw (tripAvg - learnedAvg) delta across category|currency groups, but those deltas can be in different currencies (e.g. a 5000 JPY overage vs a 20 USD overage); the larger nominal number wins regardless of real magnitude, so IRIS may surface the wrong category as 'running high.' Compare on the ratio tripAvg/learnedAvg (already gated at >1.3), or normalize to a common currency before picking the worst.

- **IRIS-Core — tierAtRisk shows an ambiguous bare weekday and a hardcoded Hyatt renewal line for every program** (IRISTriggers.evaluateTierAtRisk (IRISTriggers.swift:222,234,241))
  - Expiry within 0-7 days is rendered as just a weekday ('expires Monday'), which is ambiguous with the current week's Monday and conveys no urgency; the body also hardcodes 'book Park Hyatt to renew' regardless of program (shown for Delta/Marriott/etc). Use a relative phrase ('in 3 days', 'this Friday, Jul 10') and drop or program-condition the Park Hyatt recommendation.

- **IRIS-Core — rideOnLanding derives the arrival airport IATA from a free-text location string without validation** (IRISTriggers.evaluateRideOnLanding (IRISTriggers.swift:284-288))
  - The destination airport is taken as the substring after ' -> ' in item.location and passed straight into BagDeliveryEstimator.estimate(airportIATA:). If location is a city name or uses a different separator, the estimator gets a non-IATA string and degrades to a default ETA. Extract and validate a 3-letter IATA code (as IRISFlightActionsTool.destinationIATA already does with a regex) before calling the estimator, and drop the ETA line if none is found.

- **IRIS-Feature — Action results are recorded in the transcript but not in the model's conversation context** (IRISChatViewModel.recordActionResult / IRISAgentService session)
  - recordActionResult (line 63) appends an assistant bubble to the UI-only messages array; it never informs the LanguageModelSession. On the next turn IRIS has no idea it just logged an expense or checked the user in, so it may re-offer the same action or contradict itself ('Have you checked in yet?'). Feed a short system/assistant note about the committed action back into the agent session so subsequent replies stay consistent.

- **IRIS-Feature — Home suggestion card evaluates only once on appear and never refreshes** (IRISSuggestionCardView.refresh)
  - refresh() runs only in .onAppear (line 25) and caches the first IRISSuggestion. Triggers are time-sensitive (check-in windows, ride-to-airport, tier-at-risk — see IRISTriggers.evaluate(now:)). If the Home view stays on screen, the card goes stale: a check-in nudge won't appear when its window opens, and a dismissed/expired suggestion won't be replaced by the next-priority one. Re-evaluate on a timer or on scene-active/foreground, and after dismiss re-run evaluate() to surface the next suggestion instead of just hiding the card.

- **IdentityVault — Digital ID state list is a hardcoded snapshot that will silently go stale** (Core/Utilities/DigitalIDStates.swift:25-86)
  - The supported-state list is a hardcoded array with a comment to 'verify periodically'. Apple adds Wallet-ID jurisdictions regularly; a user in a newly-supported state will see their state missing and conclude the app/feature doesn't work for them (a silent no-op from the user's perspective). Consider sourcing this list remotely (config/feature-flag fetch) or at least surfacing a 'don't see your state? tap here for Apple's up-to-date list' row linking to support.apple.com/118313 so the feature degrades gracefully instead of appearing broken.

- **IdentityVault — Apple Wallet hand-off is disabled, reducing the feature to a support-article link** (IdentityVaultView.swift:320-326)
  - openWallet() intentionally opens support.apple.com/id-cards-in-wallet in-app instead of launching Wallet, per the §7.7 in-app-only rule and because a server-signed .pkpass endpoint doesn't exist. The 'Open Apple Wallet' button therefore does NOT open Wallet — it shows a help article, which contradicts its label and subtitle ('Add your ID from the Wallet app'). Until a real hand-off exists, relabel the button to something honest like 'How to add your ID to Wallet' so users aren't misled into expecting the Wallet app to launch.

- **InFlight — Demo fallback route/timezone hard-wired to JFK->NRT/Tokyo regardless of real seeded trip** (InFlightView displayOrigin/Destination + resolvedDestinationTimeZone (InFlightView.swift:121-126, 170-174))
  - When origin/destination/timezone aren't passed (the MoreView entry point, MoreView.swift:191), the screen falls back to a fixed JFK->NRT / Asia-Tokyo demo (lines 122-125, 172) whenever MockDataService.isEnabled. If the mock/seeded trip is ever changed to a different city pair, the map route, destination IATA label, and 'LOCAL TIME' clock will all disagree with the rest of the app's demo data. Derive the fallback from MockDataService's actual seeded flight instead of hard-coding JFK/NRT/Tokyo so the demo stays internally consistent.

- **Intelligence — Dismissals and audio dedup are session-only, so cards and dings reappear on relaunch** (TravelIntelligenceViewModel dismissedKeys (line 28) + AudioAlertService.firedAlerts (line 20))
  - dismissedKeys is an in-memory Set cleared on every app launch, and AudioAlertService.firedAlerts is likewise in-memory. A user who dismisses the 'check in for UA837' card, backgrounds the app, and relaunches will see the identical card again and can hear the gate-closing ding a second time for the same flight. Persist dismissals and fired-alert keys (keyed by the stable dismissIdentifier / flight+timestamp) in UserDefaults so a dismissal survives relaunch, and prune entries once the flight's departure passes.

- **Intelligence — Check-in card links to a generic airline check-in landing page, not the in-app flow** (TravelIntelligenceViewModel.checkInURL + actOnCard (lines 88, 255-273))
  - actOnCard correctly routes .checkInOpen taps to the in-app CheckInFlowView via NotificationCenter (line 88), but the card's actionLabel/actionURL are still populated from checkInURL only when the airline is in a 13-carrier hardcoded map (lines 256-271). For any carrier outside that list, url is nil so actionLabel is nil (line 167) and the 'Check In' button never renders — even though the in-app flow would work regardless of carrier. The external URL is effectively dead for check-in cards (the notification path ignores it). Decouple the button's visibility from checkInURL: always show 'Check In' for .checkInOpen since it invokes the internal flow, and drop the per-airline URL lookup for this card type.

- **Intelligence — Flight-number and IATA parsing relies on fragile title/location string formats** (extractFlightNumber / extractAirlineCode / extractOriginIATA (lines 211-238))
  - The engine derives the flight number from the item title regex and the origin IATA from a `SFO → NRT` location string using the exact ' → ' separator (line 233). Any itinerary whose title lacks a parseable code or whose location uses a different arrow/dash/format silently falls back to 'your flight' / no directions, degrading every downstream signal (check-in URL, maps link, checked-in lookup keyed by that parsed string). Since CheckInStateStore keys on the parsed flightNumber (line 110), a mis-parse also breaks the not-checked-in gating and can cause the gate-closing ding to fire for a flight the user already checked into. Prefer reading a structured flight number / origin field off ItineraryItem rather than reparsing display strings; if none exists, add one to the model.

- **Itinerary — Persistence date strategy is fragile against older saved data** (ItineraryViewModel.loadTrips / saveTrips (lines 35-57))
  - Both encode and decode currently use .iso8601, and Trip.init(from:) honors the decoder's strategy, so current builds round-trip fine. But there is no schema/version marker. If any prior build ever wrote with the default .deferredToDate strategy, loadTrips will silently catch the decode error and reset trips = [] (line 43), wiping the user's entire trip list with no warning. Add a stored schema version and, on decode failure, attempt a fallback decode with .deferredToDate before discarding, and surface errorMessage instead of silently emptying.

- **Itinerary — No validation that itinerary item dates fall within the trip's date range** (AddItineraryItemView (dates) / addItem)
  - The item DatePicker defaults to Date() (now) and is unconstrained, so a user adding an item to a future Tokyo trip gets today's date pre-filled and can save items entirely outside the trip window. Default the item startDate to the trip's startDate and optionally constrain/warn when an item falls outside [trip.startDate, trip.endDate]. This also fixes the common case of items all defaulting to 'now' and sorting above the actual trip.

- **Learning-Engine — leadDays is averaged from tripCompleted signals but never recorded anywhere obvious, and boarding-pass/trip lead time is ignored** (TravelProfileEngine.buildProfile lead-time block (lines 71-75))
  - typicalBookingLeadDays only comes from tripCompleted signals carrying a 'leadDays' attribute. If no feature actually emits that attribute, this field silently stays nil forever (a silent no-op). The engine already has trips with startDate and boarding passes with a date/created_at — derive lead time from the gap between a booking/created timestamp and departure/startDate as a fallback so the 'usually books ~N days ahead' insight can populate from data the app already has.

- **Learning-Engine — Recency half-life of 365 days is too slow for infrequent travelers, diluting the profile with stale preferences** (TravelProfileEngine.halfLifeDays (line 15) and recencyWeight)
  - A 1-year half-life means a preference from 2 years ago still contributes 25% weight. For a user who flew United for years then switched to Delta, United can stay ranked #1 for a long time. Consider making the half-life adaptive to the user's travel cadence (travelCadenceDays is already computed) — e.g. half-life ~= 3-4x typical cadence — so frequent flyers adapt fast and rare travelers don't lose their (sparse) signal.

- **Learning-Engine — seatPreference dominant column can be reported with very low confidence and tiny sample size with no floor** (TravelProfileEngine.seatPreference (lines 161-189) and summaryForPrompt (line 108))
  - With a single seat observation, confidence is 1.0 and sampleSize 1, and summaryForPrompt asserts 'Typical seat: window seat' to IRIS from that one data point — over-claiming on thin data, the exact over-claiming the tripRhythm code deliberately guards against (requiring >=3 trips). Apply a minimum sample size (e.g. >=3 observations) or a confidence floor before surfacing typicalSeat in summaryForPrompt, and/or hedge the wording when sampleSize is small.

- **LocalExperience — openNow flag is captured but never shown or used** (LocalExperienceView.swift card + ExperienceModel.openNow)
  - Experience.openNow is decoded and set in the demo data (e.g. Sukiyabashi Jiro openNow:false) but the card UI never displays open/closed status nor filters/deprioritizes closed venues. Users in the 'Right Now' section may tap a place that is currently closed. Surface an Open/Closed badge and consider excluding openNow==false from the RIGHT NOW bucket.

- **LoyaltyVault — No duplicate-program guard; a user can add the same program twice with conflicting balances** (LoyaltyViewModel.swift:21-43)
  - addOrUpdate keys only on account.id, so adding 'United MileagePlus' twice creates two independent rows in the same section, each contributing to TOTAL MILES — double-counting the user's balance and confusing the summary. Detect an existing account with the same programID (and/or member number) on add and offer to merge/replace instead of silently creating a duplicate.

- **LuggageTracker — refreshAllTrackableBags runs serially and thrashes the shared status flag** (LuggageViewModel.swift:105-110 / trackBag)
  - refreshAllTrackableBags awaits trackBag sequentially, and each trackBag flips isTracking true→false via `defer`, so the shared spinner toggles on/off per bag and the toast statusMessage is overwritten by the last bag only. With several trackable bags this is slow and the UI flickers. Consider a batch mode: set isTracking once around the whole loop, run lookups concurrently with a TaskGroup, and show an aggregate result (e.g. 'Updated 3 bags, 1 not found') instead of only the last bag's message.

- **LuggageTracker — Track updates airline/flight only when nil, and never clears stale location on 'not found'** (LuggageViewModel.swift:84-90 (trackBag success path))
  - On a successful trace the code overwrites status/lastLocation/lastChecked but only fills airline/flightNumber when they are currently nil (:89-90). If WorldTracer reports a corrected airline/flight (e.g. bag rerouted onto a different flight) the app keeps showing the old values. Also, when the response returns a nil lastLocation, `bags[index].lastLocation = result.lastLocation` blanks out a previously known location while stamping a fresh 'Updated just now' — misleadingly implying loss of tracking. Prefer trusting authoritative WorldTracer fields on refresh (or reconcile explicitly), and only overwrite lastLocation when the response actually provides one.

- **Misc-Services — Currency is dropped from RentalVehicle presentation ordering and totals** (Core/Services/RentalCarService.swift:98-210)
  - Each provider's currency is preserved on the vehicle but never used to guard the merge/sort, and totalWithTaxes is computed by naive addition assuming rate and taxes share a currency. Enforce that a search either constrains all providers to one currency (send a currency param) or normalizes on ingest, so cross-provider comparisons and the 'cheapest' badge are meaningful.

- **Misc-Services — TSA MyTSA live data path is documented but never integrated** (Core/Services/TSAWaitEstimator.swift:9)
  - The header promises folding in real MyTSA data 'later' but the estimator is purely heuristic with confidence capped at .medium. For known tier-1 hubs the heuristic can be far off during holidays/irregular ops. Consider wiring the (even rate-limited) MyTSA feed as an override when fresh, and only fall back to the heuristic — the DepartureOptimizer treats tsaWait.midpoint as ground truth for the leave-by math, so heuristic error directly moves the recommended departure time.

- **Misc-Services — Departure optimizer default boarding buffer may be too small for international flights** (Core/Services/DepartureOptimizerService.swift:121)
  - boardingBufferMinutes defaults to 30 and curbBufferMinutes to 10, tuned for domestic US. International departures often require boarding earlier and add immigration/document-check and longer terminal walks. Detect international itineraries (or expose a trip-type input) and raise the default buffers accordingly, otherwise the 'leave by' time is optimistic for exactly the high-stakes long-haul flights.

- **Misc-Services — Packing geocoding takes only the city name and the first geocoder hit** (Core/Services/PackingListService.swift:117)
  - geocode strips everything after the first comma ('Tokyo, Japan' → 'Tokyo') and takes results.first with count=1, ignoring the country the user provided. Ambiguous city names (Portland OR vs ME, San Jose CR vs CA, Springfield) will resolve to the wrong location and thus the wrong forecast, driving an incorrectly cold/hot packing list. Pass the full destination (or use the country component to disambiguate) and prefer the geocoder result whose country matches.

- **More — Local Experiences trip filter drops a trip during its own final day** (JetSetter Pro/Features/More/MoreView.swift:378 (nextOrLatestTrip upcoming filter))
  - upcoming is `trips.filter { $0.endDate >= now }`. Trip dates are typically stored at start-of-day (midnight). On the last day of a trip, endDate (e.g. midnight of the return day) is already < now for most of that day, so the currently-active trip is excluded from `upcoming` and the code falls back to the most-recently-ended trip via the second sort. In the common single-trip case this still returns the right trip, but with a future trip also present it will jump to recommendations for the wrong (later) trip while the user is still on their current one. Compare against end-of-day: filter on `Calendar.current.startOfDay(for: $0.endDate.addingTimeInterval(...)) ` or `$0.endDate >= Calendar.current.startOfDay(for: now)` so a trip stays 'active' through its entire final day.

- **Network-Layer — No handling for HTTP 200 with empty body / Void responses** (APIClient.perform (APIClient.swift:141))
  - perform() always calls decoder.decode(T.self, from: data). For endpoints that legitimately return 204 No Content or an empty 200 body (common for POST actions, token revocation, etc.), the decode throws decodingFailed even though the request succeeded. Add a fast path: if T is an EmptyResponse type (or data.isEmpty and T allows it), return without decoding, or special-case 204.

- **Network-Layer — isConfigured() is documented as required but the client never enforces it** (Endpoints/APIKeys + APIClient (Endpoints.swift:8-22))
  - APIKeys getters return "" when a secret is missing, and the comment tells callers to check AppSecrets.isConfigured(_:) first — but nothing in the network layer enforces it. A missing key produces a live request with an empty 'x-apikey'/'Authorization' header, yielding a confusing 401/403 (or, for Google Vision, a URL with key= empty). Consider having APIClient (or a small guard in each Endpoints group) short-circuit to a clear 'notConfigured' APIError when the relevant key is empty, so misconfiguration is unambiguous instead of masquerading as an auth failure.

- **OfflineKit — Cached 'Weather' is a point-in-time current observation, presented as trip-relevant offline info** (OfflineKitService.cache (weather) OfflineKitService.swift:107-111 / OfflineKitView statusTile 'Weather')
  - WeatherService.fetch returns current conditions at cache time. If cached days before departure, the surfaced '72°F · Clear' is stale and useless for someone landing later. For an offline-prep feature, cache a multi-day forecast covering the trip dates (or at least arrival day), and label it with the observation/forecast date so users understand what they're looking at.

- **OfflineKit — 'nextTrip' selection differs from how the rest of the app picks the active trip and ignores in-progress trips ordering** (OfflineKitView.nextTrip OfflineKitView.swift:250-260)
  - It filters endDate >= now then sorts by startDate ascending. A trip currently in progress (started, not ended) will be selected only if it has the earliest startDate among all not-yet-ended trips — a future trip that starts sooner than an already-started long trip ends could win, showing the wrong 'next trip'. Align this with the app's canonical current/next-trip logic (TravelStore/HomeViewModel) so Offline Kit targets the same trip the user sees everywhere else. Also, this reads UserDefaults only in .task, so adding/editing a trip while the screen is open won't update it.

- **OfflineKit — FX rate preview and detailed exchangeRateSummary are computed but never shown; the rate values themselves aren't cached for offline use** (OfflineKitService FX (lines 117-126, 170) / OfflineKitView FX tile line 101)
  - cache() builds a rich 'EUR/GBP/JPY...' preview string into payload.exchangeRateSummary, but OfflineKitView only displays the count and base currency (e.g. '32 currencies (USD)') and never renders exchangeRateSummary or any actual rate. More importantly, the snapshot stores only summary strings, not the rate table — so an offline user cannot actually look up a conversion. Persist the rate dictionary (at least the high-traffic codes) in the payload and add an offline converter, otherwise the 'FX rates cached' claim is cosmetic.

- **OfflineKit — Refresh silently produces a near-empty snapshot when offline, giving false confidence** (OfflineKitService.cache error handling / OfflineKitView.refresh OfflineKitView.swift:238-248)
  - Weather (try? await) and FX (optional) both fail soft to nil, and encode failures (OfflineKitService.swift:189) are swallowed. If a user taps Refresh while already on poor connectivity, cache() returns and persists a snapshot with weather/FX 'Not cached' and no error surfaced (errorMessage in the view is declared but never set). The user believes their kit refreshed successfully. Report partial failures (e.g. 'Weather & rates unavailable — connect to Wi-Fi to complete') and don't overwrite a previously-complete snapshot with a degraded one.

- **Onboarding — No way to skip the setup step; empty fields are the only escape** (OnboardingView.setupPage / primaryButton)
  - The setup page has no explicit Skip affordance — a user who wants to defer entering name/airport/currency must leave every field blank and tap "Get Started". That works (each field is guarded before save), but it's not discoverable and looks like required data. Add a visible "Skip for now" text button so users understand the fields are optional and can complete onboarding without friction.

- **Onboarding — Home airport entry offers no autocomplete or validation, unlike Settings** (OnboardingView.setupField (home airport))
  - Onboarding collects the home airport with a raw TextField, while SettingsView's airport editor (SettingsView.swift:971) already uppercases and there's an airport-picker pattern elsewhere. First-run is exactly when a bad/empty airport most hurts (it drives the Home leave-by card and flight lookups). Reuse the same airport picker/autocomplete used in Settings, or at minimum constrain to a 3-letter IATA code, so the very first flight-related screens have valid data.

- **PackingList — Advertised weather / activity / baggage-rule inputs are unused in this feature slice** (PackingListModel.swift AirlineBaggageRule + PackingListViewModel.generateList)
  - The UI promises a list based on 7-day weather, activities, airline baggage rules, and duration (SmartPackingListView lines 114, 122-126) and the model ships a 20-airline AirlineBaggageRule table, but nothing here references AirlineBaggageRule and generateList merely forwards the Trip to PackingListService. Confirm PackingListService actually incorporates weather + baggage rules; if not, pass the AirlineBaggageRule lookup and forecast into the generation prompt, or soften the marketing copy. As written the baggage table is dead weight and the claims may be unmet.

- **PackingList — Router next-upcoming-trip selection skips the in-progress trip and has a same-day boundary bug** (SmartPackingListView.PackingListRouterView.body)
  - The router picks trips.first(where: { $0.startDate >= Date() }) (line 369). A trip already in progress (startDate past, endDate future) is skipped for a future trip or falls through to arbitrary trips.first, so the user cannot reach the packing list for the trip they are on. startDate >= Date() also compares full timestamps, so a trip starting earlier today is treated as past by afternoon. Prefer the trip whose startDate...endDate contains today, then the soonest future trip; compare on startOfDay; and sort by startDate before taking .first since ordering is not guaranteed.

- **Platform-Services — DEBUG builds ship Pro unlocked by default; a mis-scoped build reveals paid features for free** (SubscriptionManager.swift:162 / refreshEntitlements() line 138)
  - demoUnlockEnabled defaults to true, so any DEBUG/TestFlight-adjacent build sets isProSubscriber = hasActivePro || demoUnlockEnabled → always Pro, and this masks real StoreKit purchase/entitlement bugs during QA (they never exercise the false path). It's correctly #if DEBUG so Release is safe, but consider defaulting demoUnlockEnabled to false and requiring an explicit unlockForTesting() toggle, so QA validates the real gate and an accidentally-shipped debug build doesn't give away Pro.

- **Platform-Services — deleteAccount deletes rows but cannot delete the GoTrue auth user, leaving an orphaned account** (SupabaseService.swift:212 deleteAccount)
  - The code (and its own comment at 209-211) acknowledges GoTrue has no self-serve auth-user delete over the anon key, so only trips/expenses rows and the local session are wiped. For App Store Guideline 5.1.1(v) compliance the auth identity itself should be removable. Ship the server-side Edge Function / RPC that deletes auth.users for the caller and invoke it here; today an 'account deletion' leaves the account (and its email→uid link) alive on the backend.

- **Platform-Services — Flight/trip reminders are only recomputed on launch + trip-change, so pushes are stale after schedule changes and are never scheduled if permission is granted later** (TravelNotificationScheduler.swift:26 startObservingTripChanges / :41 rescheduleAll)
  - rescheduleAll early-returns when NotificationManager.isAuthorized is false (line 43) and only re-runs on .jetSetterTripsChanged. If the user grants notification permission AFTER trips already exist (common — they add trips first, enable notifications later), no .jetSetterTripsChanged fires, so no reminders get scheduled until they next edit a trip. Also, a flight delay updated by the tracker won't reschedule the 2-hours-before alert unless it re-posts jetSetterTripsChanged. Trigger rescheduleAll() from requestAuthorization() success and from flight-time updates, not just trip mutations.

- **RentalCar — Sort control and filter sheet are hidden when they would be most useful** (RentalCarView.swift toolbar (line 31-45) and results)
  - The Sort menu only appears when hasSearched && !vehicles.isEmpty, but it keys off the raw vehicles array, not sortedVehicles. If a user narrows providers/class down to a non-empty raw set that yields zero filtered results, the sort control still shows over an empty list. Conversely the sort affects nothing the user can see. Gate the sort toolbar on !sortedVehicles.isEmpty and keep the filter button reachable so users can widen filters. Also surface an active-filter indicator (badge on the slider button) so users understand why results shrank.

- **RentalCar — Mixed-currency results are compared and merged as if all USD** (RentalCarService.searchVehicles sort (line 72) and RentalCarViewModel.sortedVehicles (line 50))
  - Each RentalVehicle carries its own currency, but merged results are sorted purely by numeric dailyRate across providers, and 'Price: Low to High' compares raw doubles regardless of currency. For an international rental (the demo itself is Tokyo/NRT) one provider could return JPY and another USD, making a 12000-JPY car sort as 'more expensive' than a 90-USD car. Either normalize to a single display currency before sorting/merging, or scope a search to one currency and reject/annotate mismatches.

- **Security-Services — Merchant name is the first receipt line, which is usually a header, not the merchant** (VisionOCRService.extractMerchant (VisionOCRService.swift:181))
  - The first non-empty >2-char line is frequently a logo tagline, address, phone number, or 'CUSTOMER COPY' rather than the business name. Prefer the line with the largest/boldest text if bounding-box data is available, or skip lines that look like addresses/phone numbers/dates, and fall back to organizationName-style heuristics. At minimum, let the user edit the extracted merchant before saving the expense.

- **Security-Services — Offline cache freshness (24h) is shorter than the 48h auto-cache window** (OfflineKitService.cache expiresAt (OfflineKitService.swift:178-179))
  - The header comment and cache() doc describe auto-caching when a trip enters its '48h-before' window, but expiresAt is only 24h. A trip cached at T-48h shows isFresh=false at T-24h, potentially before the traveler boards / loses connectivity — exactly when the offline kit matters most. Exchange rates and country notes barely change; extend expiry (e.g. 7 days) or key freshness off the trip end date rather than a fixed 24h.

- **Settings — Cabin (red night) mode can never be manually enabled** (SettingsView.swift appearanceSection (lines 209-235); JetThemeStore.autoCabin)
  - The Appearance section only offers Executive and Heritage chips (lines 216-218) and gates Cabin entirely behind autoCabin + being offline in airplane mode. A user who wants the night-vision red UI on the ground (e.g., a red-eye in a dark cabin with Wi-Fi on, so the device is NOT offline) has no way to turn it on. Since Cabin is a genuinely useful low-light mode, add a manual Cabin chip or a 'Force Cabin now' option so it isn't strictly tied to the offline heuristic.

- **Settings — Clear Local Data wipes UserDefaults keys by hardcoded list — new PII stores will silently leak** (SettingsView.swift clearLocalData (lines 874-910))
  - clearLocalData relies on a hand-maintained exactKeys array plus three prefixes. Any future feature that persists PII under a new key (or a key not matching the prefixes) will silently survive a 'Clear All' / account delete, defeating the privacy promise in the alert copy. Centralize the set of PII storage keys (e.g., a registry each store contributes to, mirroring the LovedOnesStore.removeAll() / TravelProfileStore.clearLearnedData() pattern) so wipe coverage can't drift out of sync with what's actually stored. Also confirm the encrypted document vault's Keychain material (passport/ID) is cleared here — the code only removes the UserDefaults 'jetsetter_vault_documents' blob.

- **Subscription — 'BEST VALUE' badge is hardcoded to annual, never computed from actual prices** (SubscriptionPaywallView.swift:148 (isRecommended: product.id == SubscriptionTier.annualID))
  - The annual tier is assumed to be the best value, but nothing verifies annual is actually cheaper per month than monthly*12. If pricing is ever misconfigured in App Store Connect (or a promo makes monthly cheaper), the app will still label annual 'BEST VALUE' and could mislead buyers. Compute the badge from real per-period normalized prices, and ideally surface the savings ('Save 40% vs monthly') by comparing product.price against the monthly product's price*12.

- **Subscription — DEBUG build ships with Pro permanently unlocked and no way to lock it back** (SubscriptionManager.swift:162 demoUnlockEnabled = true; unlockForTesting() only sets true)
  - In DEBUG, demoUnlockEnabled defaults true and refreshEntitlements ORs it in, so isProSubscriber is always true. unlockForTesting() only ever sets it true — there is no lockForTesting()/toggle. This makes it impossible to QA the paywall, PremiumGate overlay, or purchase/restore flows in a debug build without editing source. Add a debug toggle that can set demoUnlockEnabled=false and re-run refreshEntitlements(), wired to the existing Settings dev toggle, so the gated experience can actually be exercised before shipping.

- **Translator — No language-availability / model-download gating despite the comment promising it** (TranslatorView.swift (triggerTranslation / runTranslation, presetLanguages))
  - The doc comment at line 23-24 says the real list comes from LanguageAvailability.supportedLanguages at runtime, but LanguageAvailability is never used. Users can pick any of the 20 hardcoded presets even if that language pack isn't installed or isn't supported on their OS/region; they only find out via a generic 'Couldn't translate' error. Query LanguageAvailability().status(from:to:) to (a) disable/annotate unsupported presets, and (b) show a clear 'downloading language…' state when status is .supported-but-not-installed, which the framework will prompt to download.

- **Translator — Source language is always auto-detected with no override** (TranslatorView.swift:257 (Configuration source: nil))
  - source is hardcoded to nil (auto-detect). Travelers frequently want a fixed source (their own language) or to swap direction (translate the foreign text they scanned back into English). A translator UI without a source-language selector or a swap button is a notable product gap and auto-detect is unreliable for short scanned fragments. Add a source picker (or at least a swap button) and let users translate in both directions.

- **TravelEssentials — needsAdapterForUS wording assumes every user is a US traveler** (electricalCard (lines 116-137) and ElectricalGuide model)
  - The electrical card is hardcoded to a US-origin perspective ('US travelers need a Type X adapter' / 'US plugs work without an adapter'). A user flying from the UK to France, or from the EU to the US, gets misleading advice (e.g. it will say 'US plugs work without an adapter' for a US->Taiwan trip while a UK-origin user sees the same US-centric copy). Derive the comparison from the user's home country (available from their profile/loved-ones/booking data) rather than assuming US, or at least phrase it neutrally ('Type A/B plugs, 120V — compare to your home standard').

- **TravelEssentials — No 'use my current location' path when there is no trip** (TravelEssentialsView initial selection)
  - When there is no upcoming trip, the screen defaults to Japan rather than the user's actual location. A user who opens Travel Essentials while abroad without an app trip logged sees irrelevant data. Consider resolving the current country via CLLocation (with permission) or the device region as a smarter default than an arbitrary catalog entry.

- **TravelWallet — "Add to Apple Wallet" always shows success animation even with no pass data** (TravelWalletView.swift WalletItemDetailView.addToWalletSection (lines 540-544))
  - The button calls addToAppleWallet() then unconditionally sets isShowingAddedToWallet = true (comment: "Always show the success animation for investor demos"). Even when no pkpass_data exists (addToAppleWallet sets pkPassAddResult to "No pass data available"), the user sees a full-screen "Added to Apple Wallet" success. This is misleading in production. Gate the success animation on the pass actually being added; otherwise surface the pkPassAddResult message instead of a success screen.

- **TravelWallet — Class derived from seat row number is often wrong** (BoardingPassCard.classFromSeat (BoardingPassDetailView.swift:376-384))
  - Cabin class is inferred purely from row number (<=4 FIRST, <=10 BUSINESS, <=25 PREMIUM, else ECONOMY). Real aircraft vary wildly (many narrowbodies put economy at row 10; premium cabins can start at row 30 on widebodies). The displayed CLASS will frequently be incorrect. Prefer an explicit cabin_class field (AddWalletItemView already lacks a cabin input, and addItem at WalletViewModel.swift:73 reads rawData["cabin_class"] that is never populated). Add a cabin picker in AddWalletItemView and use it; only fall back to seat-heuristic when truly unknown, and label it as an estimate.

- **TripJournal — ‘DAYS’ stat is a night-count and can be smaller than ‘ACTIVE DAYS’** (TripJournalView.statsCard (lines 91–93) + Trip.durationInDays (ItineraryModel.swift:60))
  - durationInDays uses dateComponents([.day]) which returns the number of full 24h intervals between startDate and endDate (effectively nights). For the demo Atlanta trip (Jul 14 00:00 → Jul 17 12:00) it returns 3, so the header shows ‘3 DAYS’ for a trip a user thinks of as 4 days. Meanwhile daysWithPhotos counts distinct calendar days containing photos and can legitimately return 4, producing the nonsensical ‘ACTIVE DAYS 4 of 3 DAYS’. Compute inclusive calendar-day span for the DAYS stat: dateComponents([.day], from: startOfDay(start), to: startOfDay(end)).day! + 1, so both stats use the same calendar-day basis.

- **TripJournal — Share card ‘MOMENTS’ label counts itinerary items, not photos/moments** (ShareCard statBlock (TripJournalView.swift:412))
  - The on-screen grid section is titled ‘MOMENTS’ and represents photos, but the shared card’s third stat block labeled ‘MOMENTS’ uses trip.items.count (flights/hotels/activities). A trip with 30 photos but 4 itinerary items shares a card reading ‘MOMENTS 4’, which readers will interpret as 4 photos/memories. Either relabel the share stat (e.g. ‘STOPS’ or ‘PLANS’) or make it reflect the photo/day story shown in-app so the shareable artifact isn’t misleading.

- **VisaLookup — Static visa data has no freshness signal and contains time-relative claims** (VisaRequirements.forUSPassport)
  - The dataset is stamped "Updated 2026-Q1" in a comment only, and several notes are time-relative ("ETIAS required from mid-2025", "ETA required from Jan 2025", "Brazil eVisa reinstated 2025-04", "Thailand extended to 60 days as of 2024-Q3"). As of the app's current date (2026) these read as future/stale even though they are now in effect, and there is no visible "data current as of" date for the user. Add a machine-readable lastVerified date per requirement (or a global one) and display it near the disclaimer, and rephrase notes to state the current rule rather than a rollout date.

- **VisaLookup — Feature is hardcoded to US passports with no way to indicate otherwise** (VisaLookupView (entire feature))
  - Everything assumes a US passport ("For US passport holders", `VisaRequirements.forUSPassport`). A non-US user gets confidently wrong entry information with no warning. At minimum detect/ask the user's passport nationality (or make the US assumption explicit and blocking for non-US users) rather than presenting US rules as universal.


### Low impact (79)

- **About — Tour images have no accessibility labels, so VoiceOver reads nothing meaningful for the core marketing content** (JetSetter Pro/Features/About/AboutView.swift:108 (Image(slide.asset)))
  - `Image(slide.asset)` is initialized from an asset name with no label, so VoiceOver announces only 'image' (or the raw asset name). Add `.accessibilityLabel(slide.title)` (and optionally include the caption) so screen-reader users get the same tour narrative sighted users do. The `Image(systemName:)` decorative airplane in the hero should conversely be marked `.accessibilityHidden(true)`.

- **About — Version/build fall back to hardcoded '1.0 (1)' silently if Info.plist keys are missing** (JetSetter Pro/Features/About/AboutView.swift:210 (versionString))
  - If `CFBundleShortVersionString`/`CFBundleVersion` are ever absent the About screen will confidently display 'Version 1.0 (1)', which is misleading in a support/QA context (users report the wrong version). These keys are effectively always present in a shipped app, so this is low impact, but consider omitting the version line entirely when the real values can't be read rather than showing fabricated defaults.

- **AirportMap — estimatedMinutes docstring/comment claims live pedometer pace is used, but it never is** (AirportMapViewModel.estimatedMinutes (246-250) and calculateWayfindingRoute comment (line 121))
  - Comments at lines 121 and 247 state the ETA prefers live pedometer pace and falls back to MapKit, but the method only ever returns route.expectedTravelTime, and (because startTracking is never called) the pedometer path is entirely inert. Either wire up the pedometer (see bug) so the promised live-pace refinement actually happens, or remove the misleading comments so future maintainers don't assume the live-pace feature works.

- **Assistant — Trip context uses medium date style with no year/timezone nuance and no flight-specific detail** (AssistantViewModel.buildSystemPrompt (lines 110-113))
  - The injected context is only destination + start/end dates. Questions like 'When should I leave for the airport?' or 'Any weather risk for my flight?' (both offered as chips) cannot be answered meaningfully because no flight number, departure time, or origin is provided. Consider injecting the user's next flight (time, airport) so these high-intent prompts produce real answers rather than generic advice.

- **Booking — hasSearched is never reset after a search, so clearing/editing keeps the 'No results' framing** (BookingViewModel.swift:34-40 / clearSearch)
  - hasSearched stays true after the first search (only reset in clearSearch). If a user runs a search, then just edits the destination without re-searching, the empty-results 'No Hotels Found' placeholder (BookingView.swift:102) remains instead of returning to the neutral 'Find Your Stay' prompt. Consider resetting hasSearched when the destination text changes, so stale result framing doesn't persist.

- **Booking — Check-in defaults to 'now' allowing past-time check-ins; no max on check-out** (BookingModel.swift:12-13 defaults + BookingView datePickerField)
  - checkInDate defaults to Date() (current instant) and the check-in DatePicker has no lower bound, so a user can pick a past date; check-out only enforces >= check-in with no reasonable upper bound. Constrain check-in to today...(some horizon) and cap the stay length, matching what the booking API will actually accept, to avoid submitting invalid date ranges.

- **Carbon — Great-circle distance underestimates real routed/tracked distance** (distanceKm computed property (lines 18-24))
  - distance uses CLLocation great-circle, but real flights fly airways, holding, and detours that add roughly 5-10%. Since this drives the CO2 headline and offset cost, apply a small routing correction factor (e.g. *1.08, matching ICAO's distance correction bands) so the estimate does not systematically under-report emissions.

- **CheckIn — No guard against re-checking-in an already-checked-in flight** (CheckInFlowView entry / CheckInStateStore)
  - CheckInStateStore.isCheckedIn already exists but the flow never consults it on entry. A user can re-run the whole seat-selection flow for a flight they already checked into, re-posting notifications and (per the onAppear bug) potentially re-starting a Live Activity. Consider short-circuiting to the success/boarding-pass step when isCheckedIn is already true for this flight+departure.

- **CheckIn-Services — CheckInStateStore has no capacity bound or pruning of past flights** (CheckInStateStore (whole file))
  - The checked-in set grows unbounded in UserDefaults — every flight the user ever checks into stays forever, keyed by departure timestamp. Over years this array balloons and slows every isCheckedIn read (used on the Home screen and triggers). Prune identifiers whose departure timestamp is more than, say, 7 days in the past on each write, since past flights never need the checked-in flag.

- **CurrencyTracker — Cached FX rate freshness (6h) can produce silently stale conversions offline** (ExchangeRates.isFresh / ExchangeRateService.rates (model lines 22-24; service lines 37-48))
  - On offline failure the service returns arbitrarily old cached rates with no age indicator, and the UI never shows fetchedAt. For expense records that are stored permanently, surface the rate timestamp on each expense (or in the converter) so users know a conversion may be stale, and consider re-converting historical expenses if desired.

- **Data-Services — Weather windspeed is fetched in km/h but nothing localizes to the user's unit; Fahrenheit is hardcoded** (WeatherService.fetch)
  - The request hardcodes temperature_unit=fahrenheit and wind_speed_unit=kmh (WeatherService.swift:85). A traveler is by definition often in a metric region, and the app mixes an imperial temp with a metric wind speed. Derive units from Locale.current.measurementSystem (or a user setting) so displayed weather matches expectations, especially since this feeds the Home destination card for international trips.

- **Disruption — Resolved list capped at 5 with no way to see the rest** (DisruptionDashboardView.disruptionList)
  - The resolved section renders only resolvedDisruptions.prefix(5) (line 144) with no 'See all' affordance. Users who resolved more than 5 disruptions across trips silently lose access to their history (useful later for insurance/reimbursement claims). Add a 'Show all resolved' expansion or a dedicated history screen rather than truncating silently.

- **Disruption — Deduplication keeps only the most-severe event, discarding others' data** (DisruptionDashboardView.dedupedActiveDisruptions)
  - When multiple active events exist for one flight, dedup keeps only the highest-ranked event and drops the rest from the view. But the dropped events may carry distinct actionable data (e.g. a gate-change event holds the updated gate/uberDeepLink while a majorDelay event is shown). The surviving card can therefore lack the gate info the user needs. Consider merging responseActions/fields across same-flight events into the winning card rather than discarding the losers entirely.

- **Disruption — Empty-state promises background monitoring 'every 10 minutes' unconditionally** (DisruptionDashboardView.emptyView)
  - The empty state states 'We're monitoring your active trips every 10 minutes in the background.' iOS background execution (BGAppRefresh) is best-effort and not guaranteed on a 10-minute cadence, and it requires the user to have active trips and permissions. This is a concrete promise the OS may not keep, which erodes trust when a real disruption is missed. Soften the copy ('we check periodically in the background') or tie it to the actual scheduled task's real behavior.

- **Disruption-Services — Missed-connection detection never fires for the last leg or when the connection isn't an app itinerary item** (DisruptionMonitorService.pollActiveFlights (lines 141-143) / detectDisruption (lines 263-269))
  - nextDeparture is nil for the final flight item, and any connection not captured as a separate flight item in the trip is invisible. Users who book a multi-leg ticket as a single itinerary item, or whose connection is on a different trip record, get no missed-connection warning. Consider deriving connections from the flight legs FlightAware returns, or from segment data, rather than solely from adjacent itinerary items.

- **DocumentVault — Emergency contacts and driver's license/global entry types are never surfaceable via the Add flow** (DocumentVaultView.AddDocumentSheet options (line 310))
  - DocumentType defines emergencyContact, driversLicense, and globalEntry, and EmergencyModeView specifically renders an emergencyContact card — but the Add sheet only offers passport/visa/insurance/vaccination, so a user can never actually create an emergency-contact entry, leaving that Emergency Mode card permanently empty. Once the Add flow is a real form, include all DocumentType cases.

- **Expense-Providers — IRS mileage rate hardcoded to 2024 value with no year awareness** (Expense.irsMileageRatePerMile (ExpenseModel.swift:122) used for mileage expenses exported here)
  - The mileage reimbursement uses a hardcoded 2024 rate of 0.67/mile. Given the app's current date is 2026, mileage expenses are reimbursed at a stale rate. Make the rate lookup date-aware (a small table keyed by year) so mileage amounts exported to providers reflect the correct IRS rate for the expense's year.

- **ExpenseExport — Selection is silently reset / not preserved as expenses or trip change** (ExpenseExportView.load (ExpenseExportView.swift:316) and matchingExpenses)
  - load() pre-selects all matching expenses once at task time. Because the view reads from UserDefaults snapshots and never re-loads, expenses added after this screen appears won't show up, and there is no pull-to-refresh. Also 'Select All' toggles against matchingExpenses only, which is fine, but if the user deselects some items then the count in the summary ('SELECTED') can exceed matchingExpenses if the underlying data changed. Reload on appear/foreground and reconcile selectedExpenseIDs against the current matchingExpenses set.

- **ExpenseExport — Mileage expenses submitted as plain amounts lose distance/rate context** (Provider payload mapping (ExpensifyProvider.swift:71-81, OAuthExpenseProvider.swift:140-150))
  - Expense carries mileageDistance for the .mileage category (ExpenseModel.swift:79) and the app computes amounts from the IRS rate (0.67/mi). When exporting, only the flat amount, merchant and category are sent — the miles driven and rate are dropped, which many expense systems and approvers require for mileage reimbursement. Include mileageDistance and the rate in the comment/notes field (and receipt-audit PDF page) for mileage-category expenses.

- **ExpenseExport — No guard against submitting to a provider that has since disconnected** (ExpenseExportView provider list (ExpenseExportView.swift:59, 207))
  - providers is fetched once via connectedProviders() at task time. If a token expires or the user disconnects in another screen, the stale button remains tappable and submit() will surface a raw 'notConnected' error. This is handled by the error path so it is not a crash, but re-checking isConnected() (or refreshing the provider list) right before submit would give a cleaner 'reconnect' prompt instead of an error banner.

- **ExpenseTracker — OCR category suggestion excluded from manual entry filter, and mileage selectable where it shouldn't be** (ScanReceiptView.confirmationForm category picker (line 193) vs AddExpenseView picker (line 251))
  - ScanReceiptView correctly filters out .mileage from the receipt category picker (line 193) since mileage isn't a receipt, but AddExpenseView's manual picker (line 251) offers all categories including .mileage — a manually-added 'mileage' expense won't have a mileageDistance, so ExpenseRowView's '%.1f mi @ ...' line (line 204-208) is skipped and the entry is inconsistent with real mileage logs. Either filter .mileage out of manual entry too, or route it to the mileage flow.

- **ExpenseTracker — Empty-state gating uses expenses while the list renders sortedExpenses** (ExpenseTrackerView.expenseList (lines 128-141) and analyticsChart gating (line 19))
  - expenseList branches on viewModel.expenses.isEmpty (line 128) but renders viewModel.sortedExpenses (line 132), and the chart is gated on expensesByCategory.isEmpty (line 19). These derived caches are only refreshed in updateDerivedState() on save/load (ExpenseViewModel.swift:53-57). If any future code path mutates `expenses` without calling saveExpenses(), the list would show empty-state while data exists, or vice versa. Drive both the gate and the rows from the same source (sortedExpenses.isEmpty) to keep them consistent.

- **FlightBoard — Terminal filter default of '1' for user flight can hide it under an unrelated terminal** (FlightBoardData.loadUserFlightRow (terminal default))
  - When notes contain no terminal, the user flight defaults to terminal '1' (line 44). If the user then filters to 'TERMINAL 1' they will see their flight grouped with fictional sample flights that happen to share terminal '1', and if the real gate is in another terminal the grouping is simply wrong. Prefer leaving terminal empty/unknown and excluding unknown-terminal flights from terminal-specific filters, or derive terminal from the gate letter when possible.

- **FlightBoard — Fictional sample departures presented under a 'LIVE' badge with real-looking flight numbers** (FlightBoardData.sampleDepartures)
  - sampleDepartures emits real airline/flight-number combos (UA837, BA178, EK202, etc.) with a green 'LIVE' badge and gates/statuses that are entirely fabricated and re-timed relative to now. A traveller could mistake these for real departures from their airport. Either clearly label the board as illustrative, or wire it to a real flight-data source before showing a LIVE indicator.

- **FlightTracker — In-flight mode / progress hidden the moment the flight lands** (FlightDetailView.swift:42, 63-75, FlightModel.swift:63-65)
  - `isAirborne` requires `actualIn == nil`. As soon as arrival is recorded, the in-flight link, progress bar, and live map disappear entirely, even in the minutes right after touchdown when a user most wants arrival gate/baggage info surfaced together with 'just landed' context. Consider a distinct 'landed' state that keeps the route summary and jumps focus to arrival gate + baggage rather than reverting to the pre-departure layout.

- **FlightTracker — Check-in window uses best-departure (may be actual/estimated) so the button can vanish unexpectedly** (FlightDetailView.swift:91-99)
  - `shouldShowCheckInButton` gates on `flight.bestDepartureTime` which is `actualOut ?? estimatedOut ?? scheduledOut`. Airlines open check-in relative to *scheduled* departure. If a flight is delayed, `bestDepartureTime` shifts to the later estimate, so the 24h window opens later than the airline actually allows check-in — the button appears too late. Gate the eligibility window on `scheduledOut` specifically, while still displaying the best-known departure time elsewhere.

- **GroundTransport — Mock demo book() confirms a ride for a provider the user may not have; surge/price info dropped on confirmation** (GroundTransportViewModel.book (270-309) and RideConfirmationSheet)
  - In demo mode book() fabricates driver/plate/vehicle/ETA but discards the option's priceRange and isSurging, so the confirmation sheet never shows what the ride costs — the single most important detail at booking time. Include the selected option's price (and a surge note if isSurging) on RideConfirmationSheet so the demo confirmation reflects the choice the user actually made.

- **Home — parsedFlightNumber regex and airline map are US/major-carrier biased** (HomeViewModel.parsedFlightNumber / airlineNames)
  - The flight-number regex [A-Z]{2,3}\d{1,4} and the airlineNames dictionary cover ~24 carriers; any other airline falls back to '<code> Airlines' and numeric-only or 3-letter ICAO codes won't parse, degrading the check-in identity used by CheckInStateStore.isCheckedIn (flightNumber becomes 'Flight'), which keys check-in state. Two unparseable flights would share the 'Flight' identifier + departure key, risking cross-flight check-in state collisions. Persist a real flight identifier on ItineraryItem instead of re-parsing the title, and key check-in state on that.

- **Home — cityName falls back to homeAirport code as a 'city' and feeds it to the photo service** (HomeViewModel.loadLocationData:182-186)
  - When reverse-geocoding fails, cityName is set to the raw home-airport IATA code (e.g. 'JFK') and then passed to CityPhotoService.photoURL(for:) and shown under the location pin. Users see an airport code where a city name belongs and get a likely-irrelevant photo. Map the airport code to a city name before display, or show 'Your City' rather than the raw code.

- **IRIS-Core — rideToAirport over-states the hours-remaining figure in its body copy** (IRISTriggers.evaluateRideToAirport (IRISTriggers.swift:265))
  - The guard requires hours < 12, but the body prints 'leaves in under Int(hours.rounded() + 1) hours', which can say 'under 13 hours' when the true value is under 12. Use Int(hours.rounded(.up)) or clamp to the 12h ceiling so the stated number never exceeds the trigger window.

- **IRIS-Core — OpenScreenTool synonym ordering silently routes 'rebook'/'cancel' and generic 'car' to unintended screens** (IRISActionTools.OpenScreenTool.resolve (IRISActionTools.swift:53-64))
  - resolve() is first-match over broad keyword sets: 'rebook'/'cancel'/'delay' map to .disruption before any flight check, and the ground-transport bucket claims 'car'/'rental car' so 'rent a car' opens Ground Transport. Since navigation runs immediately with no confirmation, a mis-mapped phrase silently navigates the user unexpectedly. Tighten keyword sets (require 'rental car' as a phrase, scope 'cancel'/'delay' to flight context) or fall through to asking when ambiguous.

- **IRIS-Core — Demo fallback responses assert a fixed fake persona regardless of the user's real data** (IRISDemoResponses (IRISDemoResponses.swift))
  - The canned fallbacks return fully specified fake data (Ritz-Carlton confirmation RC-8842193, $1,812.75 spend, DL 1423 gate C22 seat 3A). streamDemoResponse fires whenever isAvailable is false in mock mode irrespective of the user's actual trips/expenses, so a real user on a device without Apple Intelligence sees confidently stated details that don't match what they entered. Gate this behind an explicit demo-persona flag rather than the general 'not available + mock enabled' condition.

- **IRIS-Feature — Greeting preference count and 'preferences vs preference' count only explicit memory, ignoring the learned profile** (IRISChatViewModel.composeGreeting)
  - composeGreeting (lines 79-86) counts only IRISMemory.preferences. A user who enabled the learning layer and has a rich inferred TravelProfile (seats, airlines, cities) but zero explicitly-stated preferences is greeted with the cold 'Tell me about your next trip' first-run copy, as if IRIS knows nothing. Factor TravelProfileStore.shared.profile.isEmpty into the greeting branch so returning users with learned context get the warm 'Welcome back' variant.

- **IRIS-Feature — Dismiss records negative feedback keyed only by suggestion kind, penalizing an entire category** (IRISSuggestionCardView cardBody dismiss button)
  - The 'Not now' button records recordSuggestionFeedback(kind:accepted:false) (line 94) using card.kind.rawValue. 'Not now' for one trip's packing nudge is dismissing this instance, not expressing dislike of packing suggestions in general; over-weighting it will suppress a genuinely useful category. Distinguish 'snooze this instance' from 'I don't want this kind of nudge' — e.g. only record negative category feedback after repeated dismissals, or add an explicit 'stop suggesting this' affordance.

- **IdentityVault — isLive flag is dead logic — every state is marked live** (Core/Utilities/DigitalIDStates.swift:25-86 + IdentityVaultView.swift:91,349)
  - All 12 entries in DigitalIDStates.all have isLive:true, so the 'LIVE' badge (line 91) always renders and the picker filter (line 349) never excludes anything. The section header 'Live in Apple Wallet' and the badge therefore convey no information. Either remove the isLive branching to simplify the UI, or actually populate announced-but-not-yet-live states (e.g. states Apple has announced but not shipped) as isLive:false so the two-tier UI carries real meaning.

- **IdentityVault — Default state 'Arizona' is a poor guess vs. the device region** (IdentityVaultView.swift:17-21)
  - On first launch (no persisted value) the picker defaults to Arizona for every user. Locale.current.region or the device's configured region would let you default to the user's actual state when it is in the supported list, making the very first screen correct for most US users instead of showing an Arizona DMV info link to, say, a Californian.

- **IdentityVault — Enrollment/pricing copy is hardcoded and will drift** (IdentityVaultView.swift:198)
  - CLEAR pricing is hardcoded as '$199/year, free 2-month trial'. Pricing and promo terms change and vary by partner/airline status; a stale price is misleading and a potential compliance concern for a paid third-party service. Either remove the specific price (say 'See pricing') or drive it from remote config so it can be corrected without an app release.

- **InFlight — Destination time-zone difference is computed for 'now', mislabeled as a fixed offset** (InFlightView.timeZoneDifferenceNote (InFlightView.swift:217-227))
  - diffSeconds uses tz.secondsFromGMT() and TimeZone.current.secondsFromGMT() with no date, i.e. the offset at the present instant. This is correct for 'right now' but the label '+Xh vs home' implies a stable trip-long value. If home or destination crosses a DST boundary during the flight, the shown offset silently changes mid-flight. Pass the arrival date (or the flight's landing time) to secondsFromGMT(for:) so the offset reflects the moment that actually matters to the traveler, and consider labeling it 'on arrival'.

- **InFlight — Battery disclaimer and GPS lock-time claims are hard-coded, not measured** (InFlightView.disclaimers / gpsCard (InFlightView.swift:319, 373))
  - The UI states 'Continuous tracking uses ~15% battery per hour' and 'Locking typically takes 2-5 minutes at altitude' as facts. With desiredAccuracy = kCLLocationAccuracyBest plus best-accuracy GPS + accelerometer + altimeter all running (service lines 124, 242), real drain can exceed this and varies by device. These are marketing-adjacent claims presented as guarantees; soften the wording or gate the battery figure, and consider dropping desiredAccuracy from Best to a lower tier to actually reduce drain, since 100m distanceFilter (line 125) already limits update frequency.

- **InFlight — GPS ground speed shows raw noise near zero and heading disappears when stationary** (InFlightTrackingService location handler (InFlightTrackingService.swift:355-356))
  - groundSpeedMps = max(0, location.speed) and heading = course only when course >= 0. On the ground / during slow taxi, CLLocation.speed is frequently reported as slightly negative-invalid or jittery, and course is -1 when stationary, so the HEADING tile flickers to '—' and GROUND SPEED jitters. Smooth ground speed and hold the last valid heading briefly instead of dropping it to '—' on every stationary sample, so the big-readable numbers don't flicker distractingly for the passenger.

- **Intelligence — recentTriggers grows unbounded and is never surfaced** (TravelIntelligenceViewModel.recentTriggers (lines 24, 76, 94))
  - Every dismiss/act appends to recentTriggers with no cap and no consumer (the History screen uses hardcoded demoHistory instead). Over a long session this array only grows. Either cap it (keep last N) and wire it into IntelligenceHistoryView so the history is real, or remove it. Today the 'Recent Actions' list in IntelligenceHistoryView is entirely static demo data (HistoryEntry.demoHistory, lines 120-145) and reflects nothing the user actually did.

- **Itinerary — AddItineraryItemView location/notes are not trimmed and empty-check ignores whitespace** (AddItineraryItemView.saveItem (lines 88-96))
  - location and notes use `location.isEmpty ? nil : location` — a value of one space '  ' is stored as a non-nil whitespace string, and location is never trimmed (unlike title). Trim both and treat whitespace-only as nil so the itinerary row and shareText don't render a blank '· ' location segment (ItineraryModel.swift:93).

- **Itinerary — Duplicate packing items and no calendar-sync in-flight guard** (ItineraryViewModel.addPackingItem / syncItemToCalendar (lines 88-93, 111))
  - addPackingItem does not de-duplicate, so repeated submits create duplicate 'Passport' entries. Also, the sync button (ItineraryView.swift:348) can be tapped repeatedly while isLoading is true, allowing a second addEvent for the same item and creating duplicate calendar events; the button should be disabled while viewModel.isLoading, and addEvent should early-return if calendarEventIdentifier is already set.

- **Learning-Engine — peakTravelMonths derives seasonality from trip startDate only, ignoring multi-month and hemisphere-spanning trips** (TravelProfileEngine.tripRhythm month-count block (lines 121-129))
  - Seasonality buckets each trip solely by its start month. A trip Dec 28 -> Jan 20 counts entirely as December. For 'travels most in' insights consider counting each month the trip spans (or weighting by nights per month) so long trips near month boundaries are attributed correctly.

- **LocalExperience — 'Reserve' button label is wrong for non-restaurant bookings** (LocalExperienceView.swift:239)
  - The book button is hardcoded to 'Reserve' regardless of category/source. For an attraction ticket, event (Eventbrite), or bar with a bookingUrl, 'Reserve' is misleading — it should read 'Book Tickets', 'Get Tickets', or 'View' based on category/ExperienceSource. Drive the label off experience.source/category.

- **LocalExperience — Coming Soon copy promises location activation the engine can't deliver yet** (LocalExperienceView.swift:66 / notAtDestinationView:88)
  - In non-mock mode the VM always sets isComingSoon=true and never checks location, yet the copy says experiences will appear 'once you arrive' and 'activate automatically when within 50km'. Since no location check exists, this over-promises. Either soften the copy until the CLLocation match ships, or gate on a feature flag so the promise matches actual behavior.

- **LocalExperience — errorMessage alert binding is effectively dead and fragile** (LocalExperienceView.swift:36 + ViewModel)
  - errorMessage is never assigned anywhere in the ViewModel, so the error path is currently unreachable dead code, and the alert uses .constant(vm.errorMessage != nil) which is a one-way binding. When the live engine starts setting errorMessage, verify the constant-binding dismissal works (the OK handler sets it nil, but a constant isPresented binding is a known SwiftUI foot-gun). Prefer binding isPresented to a real Bool or a computed Binding tied to errorMessage.

- **LoyaltyVault — Tier-expiration warning uses raw 90*86400 seconds, drifting across DST** (LoyaltyVaultView.swift:161)
  - The 'expiring soon' orange highlight uses `Date().addingTimeInterval(90 * 86400)`. Adding fixed 86400-second days ignores DST transitions and is a coarse way to express '90 days'. Use Calendar.current.date(byAdding: .day, value: 90, to: Date()) so the threshold lands on the correct calendar day. Also consider only comparing calendar days (tier expiration is a date, not an instant) so a tier expiring 'today' isn't already treated as past because of the time-of-day component.

- **LoyaltyVault — loyaltyAdded learning signal is only recorded on first add, never on program change during edit** (LoyaltyViewModel.swift:22-41)
  - The brand-affinity signal to TravelProfileStore is emitted only in the `else` (new append) branch. If a user creates an account and later edits it to a different program (e.g. switches airline), the new brand affinity is never recorded, and the old brand's signal stays. If the learning layer treats loyalty as a strong brand-preference input, edits that change programID should re-emit (or supersede) the signal so the profile reflects the current program set.

- **LoyaltyVault — Balance and tier accept no validation; empty/garbage balance silently becomes 0** (LoyaltyVaultView.swift:295)
  - canSave only requires a non-empty member number; balance is `Int(balance) ?? 0`. A user who leaves balance blank or whose paste includes non-digits gets a silent 0 with no feedback. Consider validating the balance field (show it as invalid rather than coercing to 0) and rejecting negative pasted values, since a 0 balance is indistinguishable from 'not entered' in the summary totals.

- **LuggageTracker — Bag tag / flight number stored without normalization** (LuggageTrackerView.swift:364-375 (AddBagView.save))
  - save() trims only the nickname. bagTagNumber is stored verbatim (spaces the user typed are kept, though traceBag strips them at lookup time — but the stored/displayed 'Tag: ...' chip shows the unclean value), and airline/flightNumber are stored with raw casing/whitespace despite the field forcing uppercase entry only in the UI. Trim and normalize tag (strip spaces) and flight number (uppercase, trim) on save so persisted/displayed data is clean and consistent with what's actually sent to WorldTracer.

- **Misc-Services — Loved-ones landing message hardcodes 'safely' with no delay/diversion awareness** (Core/Services/LovedOnesMessenger.swift:42)
  - message(for:.landing) always says 'Just landed safely in <destinationCity>'. If the composer is triggered on a diversion or the destinationCity is stale, the text asserts arrival at the wrong place. Pass the actual arrival airport and consider omitting the city when it isn't confirmed, so loved ones aren't told the traveler landed somewhere they didn't.

- **Misc-Services — Airline baggage detection only recognizes airlines already in the rules table** (Core/Services/PackingListService.swift:239)
  - detectAirlineIATA returns a code only if it exists in AirlineBaggageRule.rules (20 airlines). For any other carrier the prompt says 'Unknown airline — assume standard carry-on and one checked bag', which may over/under-estimate allowances (e.g. basic-economy no-checked-bag fares). Consider surfacing the detected-but-unmapped code to the prompt so Claude at least knows the carrier, and expand the rules table for common low-cost carriers where baggage limits most affect packing.

- **Misc-Services — Audio alert dedup is process-lifetime and cleared on relaunch** (Core/Services/AudioAlertService.swift:18)
  - firedAlerts is in-memory only, so a 'gate closing' ding already dismissed this session will fire again after an app relaunch or if the singleton is recreated. For genuinely once-only alerts (missed check-in window), persist the fired keys (with an expiry tied to the flight) so the user isn't re-alarmed on cold start for an event they already acknowledged.

- **More — nextOrLatestTrip is duplicated across features and can drift from the canonical TravelStore** (JetSetter Pro/Features/More/MoreView.swift:372-381)
  - This nextOrLatestTrip implementation (with inline UserDefaults read + JSONDecoder .iso8601) is byte-for-byte duplicated in CurrencyExpenseView.swift:314 and similar readers elsewhere, while TravelStore exists specifically as the single source of truth for the jetsetter_trips key and ISO-8601 coding. If the storage key or encoding ever changes, this copy will silently return nil (empty menu -> 'No trip selected'). Route this through a shared TravelStore.loadTrips()/nextOrLatestTrip() helper so the More menu can't drift from the writers.

- **Network-Layer — POST bodies use a throwaway JSONEncoder with default (non-snake_case) key strategy** (APIClient.post (APIClient.swift:87))
  - The decoder is configured with .convertFromSnakeCase and .iso8601, but the encoder on line 87 is a bare JSONEncoder() with default settings. Any POST body whose target API expects snake_case keys or ISO-8601 dates will be mis-serialized (camelCase keys, epoch-double dates). Given the decoder assumes snake_case for these same APIs, the asymmetry is a latent bug for POST endpoints (Expedia availability, Claude messages, Vision annotate). Configure a shared encoder with matching keyEncodingStrategy/dateEncodingStrategy, or make each service pass its own encoder.

- **Network-Layer — Expedia Debug base URL points at test host while auth points at production** (Endpoints.Expedia (Endpoints.swift:78-83))
  - In DEBUG the data base URL is test.api.expediagroup.com but tokenURL always uses the production authBaseURL. A Bearer token minted against production auth may not be accepted by the test data host (or vice versa), causing 401s only in Debug builds that are hard to diagnose. Confirm Expedia's sandbox accepts production-issued tokens; if not, gate the auth host on DEBUG too.

- **Onboarding — Appearance preference is applied live and cannot be reverted to the intended default within the flow** (OnboardingView.appearanceChip / completeOnboarding)
  - Tapping an appearance chip writes `preferences.colorSchemePreference` immediately (line 258), unlike name/airport/currency which are staged in @State and only committed on completion. This is inconsistent: if the user backs out or abandons onboarding, the appearance change already persisted while the other fields didn't. Stage the appearance choice in local @State and commit it in `completeOnboarding()` alongside the others for consistent, atomic setup.

- **PackingList — Add-item allows unlimited duplicates and cannot set quantity** (PackingListViewModel.commitAddItem + AddPackingItemSheet)
  - commitAddItem (line 170) appends with no duplicate check and hardcodes quantity to 1, though the model supports quantity and AI items use it (e.g. Socks x5). Re-adding Passport yields two rows and a user wanting 3 chargers cannot express it. Dedupe by case-insensitive name within category (or bump quantity on match) and expose a quantity stepper in AddPackingItemSheet.

- **Platform-Services — Gate reminders are defined but never scheduled by the coordinator, so the boarding push never fires in production** (TravelNotificationScheduler.swift:56 / NotificationManager.scheduleGateReminder:129)
  - scheduleGateReminder (a 30-min boarding nudge with a custom chime) is implemented but the scheduler intentionally skips it (comment lines 55-57: itinerary items lack boarding time + gate). The net effect is a fully-built feature that is dead in normal use — users never get the boarding reminder. Either wire it up once gate/boarding data is available (e.g. from the live tracker where gate is known), or drop the dead code path to avoid the impression the feature works.

- **Platform-Services — extractFlightNumber falls back to the raw itinerary title as a 'flight number', creating garbage notification IDs and mismatched cancellation** (TravelStore.swift:88 extractFlightNumber (used at TravelNotificationScheduler:59 and nextUpcomingFlight:81))
  - When the regex finds no IATA code, callers use `?? item.title` as the flightNumber. That free-text title then flows into notification identifiers ('flight_<whole title>_...') and into CheckInStateStore keys. Cancellation via cancelFlightAlerts(flightNumber:) later matches on prefix 'flight_<number>_' and won't match the title-derived id, so those alerts can't be cancelled, and check-in state can't be reconciled against the watch's normalized flight number. Prefer returning nil and skipping notification scheduling (or clearly tagging it as unparsed) rather than treating an arbitrary title as a flight number.

- **RentalCar — Same-day return is silently disallowed and drop-off is force-bumped a day** (RentalCarView datePicker onChange (line 99-101) + dropoffMinimumDate (RentalCarViewModel.swift:155))
  - The search guard requires dropoffDate > pickupDate and the drop-off picker's minimum is pickup+1 day, so same-day rentals (common for airport day trips) are impossible and, when the user moves pickup forward, drop-off is auto-pushed without visible explanation. Consider allowing same-day (dropoff >= pickup with a minimum hours span) and, when auto-adjusting drop-off, briefly surface why it changed.

- **RentalCar — Vehicle-class mapping falls back to Mid-Size, mislabeling unknown/sport/exotic cars** (RentalCarService.mapVehicleClass / mapSippToClass (line 216-227, 374-389))
  - Any description or SIPP code that does not match a keyword defaults to .midsize (e.g. the demo Mustang convertible is forced to .fullsize per the inline note because there is no sport class). This makes the class filter chips lie for those cars and can hide a car from a class filter it should arguably appear in. Add an .other/.sport bucket or map from the provider's authoritative class field (National sends carClass; Hertz sends the full SIPP) rather than string-sniffing make+model.

- **Security-Services — Screenshot/burst filtering is inconsistent with the stated intent** (PhotoLibraryService.assets (PhotoLibraryService.swift:49-56))
  - The comment says it excludes screenshots and bursts, but includeAssetSourceTypes=[.typeUserLibrary] only excludes iTunes-synced/cloud-shared sources, and only .photoScreenshot is filtered in code — bursts (and Live Photo stills, panoramas, etc.) are still included. Either filter mediaSubtypes for bursts explicitly, or update the comment. Also consider excluding very-low-resolution images so the journal stays 'clean' as intended.

- **Security-Services — extractAirportCode only understands the ' → ' arrow format** (OfflineKitService.extractAirportCode (OfflineKitService.swift:203-210))
  - Destination airport (and therefore the weather snapshot) is only extracted when a flight item's location is exactly 'AAA → BBB' with a Unicode arrow and spaces. Any other formatting ('SFO-NRT', 'SFO to NRT', codes on separate fields) yields no weather in the offline kit, silently. Parse the location more defensively (regex for 3-letter IATA codes) or derive the destination code from structured trip fields instead of a display string.

- **Security-Services — Boarding-pass detection relies on substring heuristics and localizedName** (PassKitService.walletItem (PassKitService.swift:40-45))
  - isBoardingPass matches 'boarding' in the pass type identifier OR the localized name. Legitimate boarding passes whose passTypeIdentifier is a generic 'pass.com.airline.pass' and whose localizedName is translated (non-English) will be rejected with 'Only boarding passes can be imported here'. Prefer inspecting whether the pass is a PKBoardingPass (pass.passType == .boardingPass on supported OS) rather than string matching.

- **Settings — IRIS per-source learning toggles hidden when master switch is off, so their state is invisible** (SettingsView.swift appearanceSection (lines 250-270); UserPreferences learnFrom* defaults)
  - The three per-source toggles (receipts/trips/check-ins) default ON (UserPreferences.swift:128-130) but the master learningEnabled defaults OFF (line 127), and the sub-toggles are only shown when learningEnabled is true. A privacy-conscious user who turned off, say, 'Learn From Receipts' previously cannot see or confirm that setting while the master is off. Consider showing the sub-toggles in a disabled/greyed state (or persisting a visible summary) so users can audit exactly what IRIS is allowed to learn even before flipping the master on.

- **Settings — Home airport accepts any text as an IATA code with no validation** (SettingsView.swift EditProfileSheet (lines 950, 971))
  - The airport field only uppercases the input on Save (line 971); it does not validate that it's a real/3-letter IATA code. Since homeAirport feeds the profile tag and (per app memory) Home leave-by / departure features, a typo like 'ATLL' or a city name silently produces a broken home airport. Validate against the app's airport list (or at least enforce a 3-letter A–Z pattern) and reject/hint on invalid input.

- **Subscription — Pending (Ask-to-Buy / deferred) purchases give the user no acknowledgement** (SubscriptionManager.swift:91 purchase() .pending case)
  - On .pending, the code breaks silently. The paywall shows no message, so a child/managed user who triggered Ask-to-Buy sees nothing happen and may retry or think it failed. Set a user-facing info message (e.g. 'Purchase pending approval') so the state is understood; the transaction listener will still finalize entitlement when approved.

- **Subscription — No 'subscribe-then-stays-open' handling if entitlement refresh lands while paywall isn't top-most** (SubscriptionPaywallView.swift:54 onChange(of: isProSubscriber) dismiss)
  - The paywall auto-dismisses when isProSubscriber flips true, which relies on the background transaction listener updating state. This is fine, but the PremiumGate sheet (PremiumGate.swift:29) presents the paywall via its own environment injection; if a purchase completes via the listener while the gate's blur is showing, the underlying gated content un-blurs correctly, but consider also verifying deep-linked/nested presentations dismiss cleanly. Low priority — mainly confirm on multi-sheet navigation paths.

- **Translator — English is offered as a target even though there is no source-language control** (TranslatorView.swift:45 (presetLanguages includes English))
  - With source fixed to auto-detect, selecting English as the target when the input is already English produces a no-op / identity result that looks broken. Either drop English from the target presets or, better, pair it with the source selector recommended above so English-as-target is meaningful (e.g. translating scanned foreign menus back to English).

- **Translator — Clearing source does not reset error or translating state** (TranslatorView.swift:162-165 (clear button))
  - The clear (x) button resets sourceText and translatedText but leaves errorMessage and isTranslating untouched. After a failed translation, clearing the input still shows the red error text and, if a stuck spinner is present, the spinner. Also reset errorMessage = nil and isTranslating = false when clearing so the card returns to a clean placeholder state.

- **TravelEssentials — Country picker search only matches name, not ISO code or common city** (CountryPickerSheet.filtered (lines 289-294))
  - Search filters solely on `name.contains`. Typing an ISO code ('JP'), an alternate/old name ('Turkey' when the entry is 'Türkiye', which won't match a plain 'Turkey' search due to the diacritic on the umlaut u—actually 'turkey' is a substring of 'türkiye'? no, 'ü' != 'u'), or a city yields no results. Also 'Türkiye' won't match a user typing 'Turkey'. Fold diacritics and also match on `id` and a small set of aliases so 'Turkey'/'Holland'/'UAE'/'UK' resolve.

- **TravelWallet — cabin_class learning signal is never captured on manual add** (WalletViewModel.addItem (line 73) + AddWalletItemView.saveItem (TravelWalletView.swift:757-766))
  - addItem records a TravelProfile cabinHint from item.rawData["cabin_class"], but the manual Add form never writes cabin_class (no field exists), and PassKit import doesn't set it either. So the cabinHint branch is effectively dead for manually-added passes. Add a cabin field to the boarding-pass section of AddWalletItemView so the learning signal actually fires.

- **TravelWallet — Status is completed the instant the item's date passes for non-ranged items** (WalletItem.status (WalletModel.swift:86-93))
  - For items without an end_date (boarding passes, car pickups, event tickets), endDate falls back to date, so status becomes .completed the moment the departure/pickup/event start time passes — a boarding pass moves to the collapsed, dimmed "Past" section (opacity 0.6) exactly at scheduled departure, while the traveler is still flying and most needs it. Give time-of-use documents a grace window (e.g., treat boarding passes as active for several hours after departure, or until arrival if an arrival time is known) before marking completed.

- **TripJournal — Share card silently drops photos and shows black filler when fewer than a full row is available** (ShareCard top-photos grid (TripJournalView.swift:418–439) + topShareImages (324–333))
  - topShareImages picks up to 6 assets but only appends images that successfully load (iCloud/degraded loads can return nil). If, say, 2 of 6 load, the 3xN grid pads missing cells with solid black rectangles (line 432), producing an ugly half-empty share card. Also if a trip has 1–2 photos it still renders a 3-wide row mostly black. Consider laying out only the images that actually loaded, choosing a column count based on count (1–2 photos → single row sized to fit), and skip the photo grid entirely if zero load rather than emitting black tiles.

- **TripJournal — ‘Active days’ and photo journal counts screenshots-excluded but still include non-trip photos already on device from that date range** (PhotoLibraryService.assets (PhotoLibraryService.swift:40–61))
  - The journal treats every non-screenshot user-library photo in the date window as a ‘trip moment’, but for a trip in the user’s home city (or a staycation) this sweeps in ordinary daily photos, inflating PHOTOS/ACTIVE DAYS. If location metadata is available, optionally filter to assets whose CLLocation is beyond a threshold from the user’s home coordinates (already known via MockDataService.mockHomeLat/Lon / home airport), or let the user curate/exclude, so the journal reflects actual travel rather than any photo taken during the window.

- **TripJournal — Router treats any in-progress/last/upcoming trip as journal-worthy with no recency bound** (TripJournalRouterView.nextOrLatestTrip (TripJournalView.swift:494–509))
  - When no active or upcoming trip exists, it falls back to the single most recently completed trip regardless of how long ago it ended, so a user with only a trip from years ago lands on that stale journal with no indication it’s old. Consider bounding the ‘completed’ fallback (e.g. ended within the last N weeks) or, when the best candidate is far in the past, presenting a chooser so the user can pick which trip to journal rather than defaulting to an ancient one.

- **VisaLookup — Fee and stay values are display strings, losing structure and currency** (VisaRequirement.entryFee)
  - `entryFee` is a free-form String ("CAD $7", "IDR 500,000 (~$32)", "$80.90 USD"). This can't be localized, converted to the user's home currency (the app has a CurrencyTracker feature), or summed/compared. Model fee as amount + ISO currency code and format at display time so it can integrate with the existing currency conversion and budgeting features.


## Rejected Claims (false positives, for the record)

- **AirportMap** — Layover error path shows a stale/wrong walk time with no error because the pedometer fallback is a nil stub
  - Why rejected: The claim's specific causal chain is internally contradictory and does not hold as described.

The claim asserts (file JetSetter Pro/Features/AirportMap/AirportMapViewModel.swift): in the catch block of calculateLayoverRoute(), line 158 sets estimatedWalkMinutes = estimatedMinutesFromPedometer(); be

- **DocumentVault** — Emergency Mode is reachable without any authentication, bypassing the vault lock
  - Why rejected: The line reference is accurate: DocumentVaultView.swift:75 is an unguarded "Emergency Mode" button in the auth gate (shown while !vm.isAuthenticated), which sets showEmergencyMode = true and presents EmergencyModeView(documents: vm.documents) via the .sheet at line 32. However, the claimed defect — 

- **Security-Services** — Race in loadOrCreateKey can silently destroy all vault ciphertext
  - Why rejected: The code description is accurate: VaultCrypto (JetSetter Pro/Core/Services/VaultCrypto.swift) is an enum with unsynchronized static functions. loadOrCreateKey (line 62) does a check-then-act (loadKey -> generate -> storeKey), and storeKey (line 90) does SecItemDelete then SecItemAdd, so the primitiv

- **Security-Services** — PhotoKit continuation can leak/hang if no non-degraded image is ever delivered
  - Why rejected: The line references are accurate: PhotoLibraryService.swift:76 is the requestImage call in thumbnail() (guard at line 85: `guard !isDegraded, !didResume`), and line 102 is the equivalent in fullImage() (guard at line 109). Both resume the continuation only on a non-degraded callback. The batch-load 

- **Security-Services** — ExpediaAuthService is not thread-safe; concurrent token refresh races
  - Why rejected: The source text matches the claim (final class at line 9, mutable cachedToken/tokenExpiryDate read at 25-28, written at 80-81, async validToken), and line references are accurate. But the claimed data race / undefined behavior does NOT exist under this project's build configuration. The pbxproj sets
