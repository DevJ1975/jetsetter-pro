# Jetsetter — Junior Developer Guide
### Learning Xcode & Swift Through Real Feature Work

> **Who this is for:** You're new to iOS development, you know some JavaScript/React, and you want to understand how to make changes to the Jetsetter app without breaking things. This guide maps your existing web dev knowledge to Swift concepts.

---

## Table of Contents

1. [How This Codebase Is Organized](#1-how-this-codebase-is-organized)
2. [Your JavaScript Brain vs Swift Reality](#2-your-javascript-brain-vs-swift-reality)
3. [Xcode Survival Guide](#3-xcode-survival-guide)
4. [SwiftUI Fundamentals](#4-swiftui-fundamentals)
5. [Making Changes — Module by Module](#5-making-changes--module-by-module)
6. [Working with APIs](#6-working-with-apis)
7. [State Management in Swift](#7-state-management-in-swift)
8. [Common Errors & What They Mean](#8-common-errors--what-they-mean)
9. [Git Workflow for iOS Projects](#9-git-workflow-for-ios-projects)
10. [Debugging Like a Pro](#10-debugging-like-a-pro)
11. [Glossary](#11-glossary)

---

## 1. How This Codebase Is Organized

```
Jetsetter/
├── App/
│   ├── JetsetterApp.swift         ← Entry point (like index.js)
│   └── ContentView.swift          ← Root navigation shell
│
├── Features/                      ← One folder per feature module
│   ├── FlightTracker/
│   │   ├── FlightTrackerView.swift
│   │   ├── FlightTrackerViewModel.swift
│   │   └── FlightTrackerModel.swift
│   ├── Itinerary/
│   ├── Expenses/
│   ├── Luggage/
│   ├── Bookings/
│   └── Assistant/
│
├── Core/
│   ├── Network/
│   │   ├── APIClient.swift        ← All HTTP requests live here
│   │   └── Endpoints.swift        ← API URLs and paths
│   ├── Models/                    ← Shared data structures
│   ├── Storage/                   ← Local persistence (CoreData/UserDefaults)
│   └── Extensions/                ← Swift helper utilities
│
├── UI/
│   ├── Components/                ← Reusable UI pieces (like React components)
│   ├── Theme/                     ← Colors, fonts, spacing
│   └── Assets.xcassets            ← Images and icons
│
└── Resources/
    ├── Info.plist                 ← App permissions and metadata
    └── Localizable.strings        ← Text strings
```

### The Pattern: View + ViewModel + Model

Every feature in Jetsetter follows the **MVVM pattern**. Think of it like this:

| MVVM Layer | Web Equivalent | Does What |
|---|---|---|
| **Model** | TypeScript interface/type | Defines the data shape |
| **ViewModel** | React custom hook | Fetches data, handles logic |
| **View** | React component | Renders UI only |

**Rule of thumb:** If you're writing a network call inside a `View` file, stop. Move it to the `ViewModel`.

---

## 2. Your JavaScript Brain vs Swift Reality

You know JavaScript. Here's a direct translation guide.

### Variables

```javascript
// JavaScript
let name = "Jamil";          // can change
const airport = "LAS";       // can't change
var count = 0;               // function-scoped (avoid)
```

```swift
// Swift
var name = "Jamil"           // can change (mutable)
let airport = "LAS"          // can't change (constant)
// Swift has no 'var' with function scope — use let/var
```

**Swift rule:** Use `let` by default. Only switch to `var` when the value needs to change. The compiler will tell you when you're wrong.

### Types

```javascript
// JavaScript — loosely typed
let price = 249;             // number
let airline = "Delta";       // string
let isDelayed = false;       // boolean
```

```swift
// Swift — strongly typed (but often inferred)
var price: Double = 249.00   // explicit
let airline = "Delta"        // inferred as String
var isDelayed = false        // inferred as Bool
```

### Functions

```javascript
// JavaScript
function formatGate(terminal, gate) {
  return `${terminal}-${gate}`;
}

// Arrow function
const formatGate = (terminal, gate) => `${terminal}-${gate}`;
```

```swift
// Swift
func formatGate(terminal: String, gate: String) -> String {
    return "\(terminal)-\(gate)"
}

// Calling it — NOTE: Swift uses argument labels
let result = formatGate(terminal: "C", gate: "22")
```

### Arrays & Loops

```javascript
// JavaScript
const flights = ["DL123", "UA456", "AA789"];
flights.forEach(f => console.log(f));
const delayed = flights.filter(f => f.startsWith("DL"));
const codes = flights.map(f => f.toUpperCase());
```

```swift
// Swift
let flights = ["DL123", "UA456", "AA789"]
flights.forEach { f in print(f) }
let delayed = flights.filter { $0.hasPrefix("DL") }   // $0 = first arg shorthand
let codes = flights.map { $0.uppercased() }
```

### Optionals (The Big One — No JavaScript Equivalent)

This is the concept that trips up web developers most. Swift does not allow `null`/`undefined` by default. Every variable **must** have a value unless you explicitly say it's optional with `?`.

```swift
// This CANNOT be nil:
var flightNumber: String = "DL123"
flightNumber = nil  // ❌ COMPILER ERROR

// This CAN be nil (optional):
var gate: String? = nil   // ✅ fine
gate = "C22"              // ✅ fine

// To USE an optional, you must "unwrap" it
if let actualGate = gate {
    print("Your gate is \(actualGate)")
} else {
    print("Gate not assigned yet")
}

// Or use nil coalescing (like JavaScript's ??)
let displayGate = gate ?? "TBD"

// Or guard (preferred in functions — exits early if nil)
func announceGate() {
    guard let g = gate else {
        print("No gate assigned")
        return
    }
    print("Gate: \(g)")
}
```

**Why this matters in Jetsetter:** API responses have optional fields. A flight may or may not have a gate assigned yet. Swift forces you to handle both cases — this prevents a whole class of crashes.

---

## 3. Xcode Survival Guide

### The Interface (What Each Area Does)

```
┌─────────────────────────────────────────────────────────┐
│  TOOLBAR: Run ▶  Stop ■  Scheme  Device picker          │
├──────────┬──────────────────────────────┬───────────────┤
│          │                              │               │
│ NAVIGATOR│       EDITOR                 │  INSPECTOR    │
│          │                              │               │
│ Project  │  Your code goes here         │ File settings │
│ Search   │                              │ View settings │
│ Issues   │                              │ Attributes    │
│ Debug    │                              │               │
├──────────┴──────────────────────────────┴───────────────┤
│  DEBUG AREA: Console output / Variables                  │
└─────────────────────────────────────────────────────────┘
```

### Keyboard Shortcuts You'll Use Every Day

| Shortcut | Action |
|---|---|
| `⌘ + R` | Build and run the app |
| `⌘ + B` | Build without running |
| `⌘ + .` | Stop the running app |
| `⌘ + /` | Toggle comment on selected lines |
| `⌘ + ⇧ + K` | Clean build folder (fixes weird errors) |
| `⌘ + ⇧ + O` | Open quickly (like VS Code's Cmd+P) |
| `⌘ + click` | Jump to definition |
| `⌃ + I` | Re-indent selected code |
| `⌘ + ⇧ + Y` | Show/hide debug area |
| `⌥ + click` | Show inline documentation |

### Simulators

To run Jetsetter without a physical device:
1. Click the device picker in the toolbar (it shows something like "iPhone 15 Pro")
2. Select any iPhone simulator
3. Press `⌘ + R`

For AirTag features: those require a real device. The simulator cannot access Core Location or FindMy.

### Adding a New File

1. Right-click on the correct folder in the Navigator
2. Choose "New File..."
3. Select "Swift File" (or "SwiftUI View" if it's a UI screen)
4. Name it following the existing convention: `FeatureNameView.swift`

---

## 4. SwiftUI Fundamentals

SwiftUI is Apple's modern UI framework. Think of it like React but compiled.

### A Basic View (Like a React Component)

```swift
import SwiftUI

struct FlightCardView: View {
    // Props (like React props)
    let flightNumber: String
    let destination: String
    let departureTime: String

    // The "render" — must return some View
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(flightNumber)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(destination)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(departureTime)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// Preview (like Storybook)
#Preview {
    FlightCardView(
        flightNumber: "DL 1423",
        destination: "Atlanta, GA",
        departureTime: "7:00 AM"
    )
}
```

### Layout Containers

```swift
// VStack — vertical (like flex-direction: column)
VStack(spacing: 16) {
    Text("Top")
    Text("Bottom")
}

// HStack — horizontal (like flex-direction: row)
HStack(spacing: 12) {
    Text("Left")
    Spacer()   // like flex: 1 / margin-left: auto
    Text("Right")
}

// ZStack — layered (like position: absolute)
ZStack {
    Image("background")
    Text("Overlay text")
}
```

### Common Modifiers (Like CSS Classes)

```swift
Text("Hello")
    .font(.title)              // font-size
    .fontWeight(.bold)         // font-weight
    .foregroundColor(.blue)    // color
    .padding(.horizontal, 16)  // padding
    .background(Color.white)   // background-color
    .cornerRadius(8)           // border-radius
    .opacity(0.8)              // opacity
    .frame(width: 200)         // width
    .lineLimit(2)              // -webkit-line-clamp: 2
```

### State — Making Views Reactive

```swift
struct DelayBannerView: View {
    @State private var isExpanded = false  // like useState(false)

    var body: some View {
        VStack {
            Button("Flight Delayed — Tap for Details") {
                isExpanded.toggle()   // triggers re-render
            }
            
            if isExpanded {
                Text("New departure: 9:45 AM — Gate C22")
                    .padding()
            }
        }
    }
}
```

### Navigation

```swift
// NavigationStack is like React Router
NavigationStack {
    List(flights, id: \.id) { flight in
        NavigationLink(destination: FlightDetailView(flight: flight)) {
            FlightRowView(flight: flight)
        }
    }
    .navigationTitle("My Flights")
}
```

---

## 5. Making Changes — Module by Module

### How to Add a New Field to the Flight Tracker

**Scenario:** You want to add a "Terminal" field that shows on the flight detail screen.

**Step 1 — Update the Model**

Open `Features/FlightTracker/FlightTrackerModel.swift`:

```swift
// BEFORE
struct Flight: Identifiable, Codable {
    let id: String
    let flightNumber: String
    let destination: String
    let departureTime: Date
    let gate: String?
}

// AFTER — add terminal
struct Flight: Identifiable, Codable {
    let id: String
    let flightNumber: String
    let destination: String
    let departureTime: Date
    let gate: String?
    let terminal: String?   // ← add this. Optional because API may not always return it
}
```

**Step 2 — Update the ViewModel**

The ViewModel decodes API responses. If the API already returns `terminal`, Swift's `Codable` will decode it automatically — you just need the property in the model. If the API uses a different key name:

```swift
// In FlightTrackerModel.swift, add CodingKeys enum
struct Flight: Identifiable, Codable {
    // ... existing properties ...
    let terminal: String?
    
    // Only needed if API key name differs from Swift property name
    enum CodingKeys: String, CodingKey {
        case id
        case flightNumber = "flight_number"   // API sends "flight_number"
        case destination
        case departureTime = "departure_time"
        case gate
        case terminal                          // API also sends "terminal" — matches
    }
}
```

**Step 3 — Update the View**

Open `Features/FlightTracker/FlightDetailView.swift`:

```swift
// Find the section that shows gate info and add terminal below it
if let gate = flight.gate {
    InfoRow(label: "Gate", value: gate)
}

// ADD THIS:
if let terminal = flight.terminal {
    InfoRow(label: "Terminal", value: terminal)
}
```

**Step 4 — Build and Test**

Press `⌘ + B` to build. Fix any errors. Then `⌘ + R` to run.

---

### How to Add a New Expense Category

Open `Features/Expenses/ExpenseModel.swift`:

```swift
// BEFORE
enum ExpenseCategory: String, CaseIterable, Codable {
    case airfare = "Airfare"
    case hotel = "Hotel"
    case meals = "Meals"
    case groundTransport = "Ground Transport"
    case rentalCar = "Rental Car"
    case parking = "Parking"
    case misc = "Misc"
}

// AFTER — add internet/roaming
enum ExpenseCategory: String, CaseIterable, Codable {
    case airfare = "Airfare"
    case hotel = "Hotel"
    case meals = "Meals"
    case groundTransport = "Ground Transport"
    case rentalCar = "Rental Car"
    case parking = "Parking"
    case internet = "Internet / Roaming"    // ← new
    case misc = "Misc"
}
```

Because this enum uses `CaseIterable`, the new category will automatically appear in every picker and list in the app that iterates over `ExpenseCategory.allCases`. No other changes needed.

---

### How to Change a Color in the Theme

Open `UI/Theme/JetsetterTheme.swift`:

```swift
struct JetsetterTheme {
    // Brand colors
    static let primary = Color("JetBlue")           // References Assets.xcassets
    static let accent = Color("JetGold")
    static let danger = Color("AlertRed")
    
    // Semantic colors
    static let delayedFlight = Color.orange
    static let cancelledFlight = Color.red
    static let onTimeFlight = Color.green
    
    // CHANGE: make on-time flights a richer green
    // static let onTimeFlight = Color.green          ← old
    static let onTimeFlight = Color(red: 0.1, green: 0.7, blue: 0.4)  // ← new
}
```

To add a custom brand color to Assets.xcassets:
1. Open `UI/Assets.xcassets` in the Navigator
2. Click the `+` button at the bottom
3. Choose "Color Set"
4. Name it (e.g. `JetNavy`)
5. Click the color swatch and set values for Light and Dark appearance

---

### How to Add a New Screen (Route)

**Scenario:** Adding a "Lounge Finder" screen.

1. Create `Features/Lounge/LoungeFinderView.swift`
2. Write the basic view structure
3. Add navigation entry point in the main tab bar or menu

```swift
// In ContentView.swift or your TabView
TabView {
    FlightTrackerView()
        .tabItem { Label("Flights", systemImage: "airplane") }
    
    ItineraryView()
        .tabItem { Label("Itinerary", systemImage: "calendar") }
    
    ExpensesView()
        .tabItem { Label("Expenses", systemImage: "receipt") }
    
    // ADD THIS:
    LoungeFinderView()
        .tabItem { Label("Lounges", systemImage: "sofa") }
    
    MoreView()
        .tabItem { Label("More", systemImage: "ellipsis") }
}
```

---

## 6. Working with APIs

### The API Client Pattern

All network calls go through `Core/Network/APIClient.swift`. Never write `URLSession` calls directly in a View or ViewModel — always add them here first.

```swift
// Core/Network/APIClient.swift

class APIClient {
    static let shared = APIClient()   // Singleton — like a module export
    
    private let baseURL = "https://api.jetsetter.app/v1"
    
    // Generic fetch function
    func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.badResponse
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

### Adding a New API Call

**Scenario:** Adding an endpoint to fetch lounge locations.

Step 1 — Add the endpoint to `Core/Network/Endpoints.swift`:

```swift
struct Endpoints {
    static let flights = "/flights"
    static let hotels = "/hotels"
    static let expenses = "/expenses"
    static let lounges = "/lounges"   // ← add this
}
```

Step 2 — Add the call in the ViewModel:

```swift
// Features/Lounge/LoungeFinderViewModel.swift

@MainActor
class LoungeFinderViewModel: ObservableObject {
    @Published var lounges: [Lounge] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func fetchLounges(airportCode: String) async {
        isLoading = true
        do {
            let result: [Lounge] = try await APIClient.shared.fetch(
                "\(Endpoints.lounges)?airport=\(airportCode)"
            )
            lounges = result
        } catch {
            errorMessage = "Could not load lounges: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
```

Step 3 — Call it from the View:

```swift
struct LoungeFinderView: View {
    @StateObject private var viewModel = LoungeFinderViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Finding lounges...")
            } else {
                List(viewModel.lounges) { lounge in
                    LoungeRowView(lounge: lounge)
                }
            }
        }
        .task {
            await viewModel.fetchLounges(airportCode: "LAS")
        }
    }
}
```

### Handling Async/Await

Swift's `async/await` works just like JavaScript's:

```javascript
// JavaScript
async function fetchFlight(id) {
  try {
    const data = await fetch(`/flights/${id}`);
    return await data.json();
  } catch (e) {
    console.error(e);
  }
}
```

```swift
// Swift
func fetchFlight(id: String) async throws -> Flight {
    // 'throws' = can throw errors (like async functions that can reject)
    return try await APIClient.shared.fetch("/flights/\(id)")
}

// Calling it:
Task {
    do {
        let flight = try await fetchFlight(id: "DL123")
        print(flight.destination)
    } catch {
        print("Error: \(error)")
    }
}
```

---

## 7. State Management in Swift

### The Three Property Wrappers You'll Use Most

| Wrapper | Use When | Like React's |
|---|---|---|
| `@State` | Local UI state inside one view | `useState` |
| `@StateObject` | Creating a ViewModel inside a view | `useState` with a class |
| `@ObservedObject` | Receiving a ViewModel from a parent | Props + context |
| `@EnvironmentObject` | App-wide shared state | React Context |
| `@Published` | Properties in a ViewModel that trigger UI updates | State in a Redux store |

### Example: Flight Tracker Full State Flow

```swift
// 1. ViewModel (the "store")
class FlightTrackerViewModel: ObservableObject {
    @Published var flights: [Flight] = []     // UI re-renders when this changes
    @Published var isLoading = false
    
    func loadFlights() async {
        isLoading = true
        flights = try await APIClient.shared.fetch(Endpoints.flights)
        isLoading = false
    }
}

// 2. Parent View (creates the ViewModel)
struct FlightTrackerView: View {
    @StateObject private var viewModel = FlightTrackerViewModel()
    
    var body: some View {
        FlightListView(viewModel: viewModel)
            .task { await viewModel.loadFlights() }
    }
}

// 3. Child View (receives the ViewModel)
struct FlightListView: View {
    @ObservedObject var viewModel: FlightTrackerViewModel
    
    var body: some View {
        List(viewModel.flights) { flight in
            FlightRowView(flight: flight)
        }
    }
}
```

---

## 8. Common Errors & What They Mean

### "Value of optional type 'String?' must be unwrapped"

```swift
// The problem:
let gate: String? = getGate()
print(gate)   // ❌ ERROR — gate might be nil

// Fix 1 — if let (use when nil is a real possibility)
if let gate = gate {
    print(gate)
}

// Fix 2 — nil coalescing (provide a default)
print(gate ?? "Gate TBD")

// Fix 3 — guard (use in functions, exits early)
guard let gate = gate else { return }
print(gate)
```

### "Cannot use mutating member on immutable value"

```swift
// The problem — struct with 'let'
let flight = Flight(...)
flight.gate = "C22"   // ❌ ERROR — 'flight' is a constant

// Fix — use 'var'
var flight = Flight(...)
flight.gate = "C22"   // ✅
```

### "Extra argument in call" / "Missing argument for parameter"

```swift
// Swift requires argument labels by default
func book(flight: String, seat: String) { ... }

book("DL123", "12A")                       // ❌ ERROR
book(flight: "DL123", seat: "12A")         // ✅ correct
```

### "Property 'X' requires that 'Y' conform to 'Z'"

This usually means a type you're passing doesn't implement a required protocol. Common fix:

```swift
// If your model needs to work in a List:
struct Lounge: Identifiable {   // ← add Identifiable
    let id = UUID()
    let name: String
}

// If your model needs to be saved/decoded from JSON:
struct Lounge: Codable {        // ← add Codable
    let name: String
}

// Often you need both:
struct Lounge: Identifiable, Codable {
    let id: String
    let name: String
}
```

### "No such module 'X'"

A Swift package dependency is missing or not resolved.
1. Go to **File → Packages → Resolve Package Versions**
2. If that doesn't work: **Product → Clean Build Folder** (`⌘⇧K`), then build again

---

## 9. Git Workflow for iOS Projects

### Files to Never Commit

Your `.gitignore` should always exclude:

```
# Xcode build artifacts
*.xcuserstate
DerivedData/
*.xccheckout
*.moved-aside

# Secrets
*.plist with API keys
Secrets.swift
.env

# SPM cache
.swiftpm/
```

### Branch Naming for Jetsetter Features

```
feature/flight-tracker-terminal-field
feature/expense-ocr-improvements
bugfix/gate-display-nil-crash
chore/update-flightaware-sdk
```

### Before Every Commit Checklist

- [ ] App builds without errors (`⌘ + B`)
- [ ] Preview renders in Canvas (for SwiftUI views)
- [ ] New model properties are optional if the API might not return them
- [ ] No hardcoded API keys in the code
- [ ] No `print()` statements left in production paths (use `Logger` instead)

---

## 10. Debugging Like a Pro

### Using Breakpoints

1. Click the line number in the Editor to set a breakpoint (blue arrow appears)
2. Run the app — it will pause at that line
3. In the Debug Area, type `po variableName` to print any variable's value
4. Use the step buttons: Step Over (F6), Step Into (F7), Continue (F5)

### Using the Console

```swift
// Basic print (visible in Xcode debug console)
print("Flight loaded: \(flight.flightNumber)")

// Better: use Logger (filters by category, works in production)
import os
let logger = Logger(subsystem: "com.yourapp.jetsetter", category: "FlightTracker")
logger.info("Flight loaded: \(flight.flightNumber)")
logger.error("API call failed: \(error.localizedDescription)")
```

### View Hierarchy Debugger

If your UI looks wrong:
1. Run the app in simulator
2. In Xcode, click **Debug → View Debugging → Capture View Hierarchy**
3. You'll see a 3D exploded view of every layer — find what's covering what

### The SwiftUI Preview Canvas

Every `#Preview` block lets you see your view without running the app:
- `⌘ + ⌥ + P` — toggle the preview canvas
- Click "Resume" if it shows as paused
- Right-click a preview to "Pin Preview" — keeps it visible while you edit other files

---

## 11. Glossary

| Term | Meaning |
|---|---|
| **Swift** | Apple's programming language (replaced Objective-C) |
| **SwiftUI** | Apple's declarative UI framework (like React for iOS) |
| **Xcode** | Apple's IDE — like VS Code but for iOS/macOS development |
| **Simulator** | Virtual iPhone/iPad that runs on your Mac |
| **Storyboard** | Old way to build UIs (XML-based, avoid for new code) |
| **Protocol** | Like a TypeScript interface — defines required methods/properties |
| **Struct** | Value type — copied when assigned (most models use this) |
| **Class** | Reference type — shared by reference (ViewModels use this) |
| **Optional** | A value that might be nil — written as `Type?` |
| **Codable** | Protocol that auto-generates JSON encode/decode logic |
| **@Published** | Property wrapper that broadcasts changes to the UI |
| **@State** | Local UI state owned by a View |
| **@StateObject** | Like @State but for class instances (ViewModels) |
| **async/await** | Same concept as JavaScript async/await |
| **Bundle ID** | Unique app identifier like `com.trainovate.jetsetter` |
| **Info.plist** | App configuration file — declares permissions, metadata |
| **SPM** | Swift Package Manager — like npm for Swift |
| **Scheme** | Build configuration — defines what gets built and how |
| **Target** | A single build product (your app, a widget, a test suite) |
| **DerivedData** | Xcode's build cache — safe to delete if things get weird |

---

> **Study Order Recommendation:** Start with Chapter 2 (JS→Swift translation) and Chapter 4 (SwiftUI basics). Once those feel solid, jump straight to Chapter 5 to make real changes to the app. Chapters 6 and 7 unlock once you're comfortable with the basics. You'll refer to Chapter 8 on every project — bookmark it.

---

*Jetsetter Junior Dev Guide — Trainovate Technologies*
*Keep this file updated as the app evolves.*
