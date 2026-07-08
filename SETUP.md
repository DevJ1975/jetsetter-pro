# JetSetter Pro — Phase 1 Setup

This guide covers the Xcode UI and external account work needed to finish Phase 1 of shipping JetSetter Pro. The source code refactor (centralizing API key reads via `AppSecrets`) is already done.

---

## 1. Wire up `Secrets.xcconfig`

1. In Xcode, **File → Add Files to "JetSetter Pro"…**
   - Select `Config/Secrets.xcconfig`
   - **Uncheck** "Copy items if needed"
   - **Add to targets: none** (xcconfig files don't go in a target)
2. Click the project (top of navigator) → **Info** tab.
3. Under **Configurations**, expand both **Debug** and **Release**.
4. For the **project row** in each, click the dropdown under "Based on Configuration File" and choose **Secrets**.
5. Build once — values should now flow into Info.plist via the next step.

`Secrets.xcconfig` is already in `.gitignore`. Real keys go in this file, never committed. The committed `Secrets.xcconfig.example` documents the schema for new team members.

## 2. Add Info.plist keys (via Target Build Settings)

The project uses `GENERATE_INFOPLIST_FILE = YES`, so Info.plist entries are added as `INFOPLIST_KEY_*` build settings on the **JetSetter Pro target** (not the project).

Open **JetSetter Pro target → Build Settings → All / Combined**, click `+` → **Add User-Defined Setting**, and add each of these (paste the key name, then the value):

### Permissions

| Key | Value |
|---|---|
| `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` | `JetSetter Pro uses your location to find nearby airports, transport options, and local experiences.` |
| `INFOPLIST_KEY_NSCameraUsageDescription` | `JetSetter Pro uses the camera to scan receipts and travel documents.` |
| `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` | `JetSetter Pro accesses your photo library to attach receipts and documents to trips.` |
| `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` | `JetSetter Pro saves boarding passes and travel documents to your photo library.` |

### Background flight monitoring

| Key | Value |
|---|---|
| `INFOPLIST_KEY_UIBackgroundModes` | `fetch processing` |
| `INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers` | `com.jetsetter.pro.disruption.poll` |

Then **Signing & Capabilities → + Capability → Background Modes**, and tick **Background fetch** and **Background processing** (these mirror the build setting above and are required for the entitlement).

### API key forwarding (from xcconfig → Info.plist)

**Already wired — no manual step.** Every `INFOPLIST_KEY_API_*` forwarder is baked
into the **JetSetter Pro** target's build settings (both Debug and Release) in
`project.pbxproj`, so `Secrets.xcconfig` values flow into `Info.plist`
automatically. The forwarded keys are: `API_FLIGHTAWARE`, `API_ANTHROPIC`,
`API_CLAUDE_PROXY_URL`, `API_SUPABASE_URL`, `API_SUPABASE_ANON_KEY`,
`API_EXPEDIA_CLIENT_ID`/`_SECRET`, `API_UBER_SERVER_TOKEN`,
`API_LYFT_CLIENT_ID`/`_SECRET`, `API_GOOGLE_VISION`, `API_SITA_WORLDTRACER`,
`API_ENTERPRISE`/`_HERTZ`/`_NATIONAL`, `API_AMADEUS_CLIENT_ID`/`_SECRET`,
`API_DUFFEL`, `API_DUFFEL_PROXY_URL`/`_KEY`, and the expense-provider keys.

Just fill in the values you have in `Secrets.xcconfig`; blank keys fall back to
demo/mock data.

## 3. Wire `Products.storekit` to the run scheme

1. **File → Add Files…** → select `Config/Products.storekit`. Add to the **JetSetter Pro target**.
2. **Product → Scheme → Edit Scheme…**
3. Select **Run** in the sidebar → **Options** tab.
4. Set **StoreKit Configuration** to **Products.storekit**.
5. Run the app and verify the paywall shows "Pro Monthly $9.99" / "Pro Annual $69.99" with a 7-day free trial.

When you create the real products in App Store Connect, use the same product IDs:
- `DevJ.JetSetter-Pro.subscription.pro.monthly`
- `DevJ.JetSetter-Pro.subscription.pro.annual`

Grouped under a single subscription group named "Jetsetter Pro".

## 4. Set up Supabase (backend)

**The backend is Supabase** — GoTrue auth + PostgREST data over REST (no SDK).
The full walkthrough lives in **[SETUP-SUPABASE.md](SETUP-SUPABASE.md)**: the two
keys (`API_SUPABASE_URL`, `API_SUPABASE_ANON_KEY`), the one-time Xcode
base-config step, the SQL schema + row-level-security policies, enabling Email
auth, and deploying the `delete-user` and `claude-proxy` edge functions.

## 5. Obtain API credentials

Drop each into `Secrets.xcconfig` as you get them. Empty values keep the app working with mock data, so partial completion is fine.

| Service | Where to apply | Free tier? |
|---|---|---|
| FlightAware AeroAPI | flightaware.com/aeroapi | Yes (limited) |
| Anthropic Claude | console.anthropic.com | Pay-as-you-go |
| Expedia Rapid | developers.expediagroup.com | Partner approval required |
| Uber | developer.uber.com | Yes |
| Lyft | developer.lyft.com | Yes |
| Google Vision | console.cloud.google.com → Vision API | Yes (1k calls/mo) |
| Amadeus | developers.amadeus.com | Yes (test env) |
| Duffel | duffel.com | Test mode free |
| SITA WorldTracer | developer.sita.aero | Partner approval required |

## 6. Verify

After all of the above:
1. Build and run on a real device (background tasks don't fire in the simulator).
2. Open Settings → toggle dark mode (sanity check).
3. Try the paywall — sandbox purchase should succeed.
4. Create a trip with a flight and confirm Disruption Monitor schedules its first poll (Xcode console logs).
