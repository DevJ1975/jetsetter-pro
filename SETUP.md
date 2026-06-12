# JetSetter Pro — Phase 1 Setup

This guide covers the Xcode UI and external account work needed to finish Phase 1 of shipping JetSetter Pro. The source code refactor (centralizing API key reads via `AppSecrets`) is already done.

---

## 1. Wire up `Secrets.xcconfig`

1. In Xcode, **File → Add Files to "JetSetter Pro"…**
   - Select `JetSetter Pro/JetSetter Pro/Config/Secrets.xcconfig`
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

Add each of these as a User-Defined Setting on the target. The value is the variable reference exactly as shown, so xcconfig values flow through.

| Key | Value |
|---|---|
| `INFOPLIST_KEY_API_FLIGHTAWARE` | `$(API_FLIGHTAWARE)` |
| `INFOPLIST_KEY_API_ANTHROPIC` | `$(API_ANTHROPIC)` |
| `INFOPLIST_KEY_API_EXPEDIA_CLIENT_ID` | `$(API_EXPEDIA_CLIENT_ID)` |
| `INFOPLIST_KEY_API_EXPEDIA_CLIENT_SECRET` | `$(API_EXPEDIA_CLIENT_SECRET)` |
| `INFOPLIST_KEY_API_UBER_SERVER_TOKEN` | `$(API_UBER_SERVER_TOKEN)` |
| `INFOPLIST_KEY_API_LYFT_CLIENT_ID` | `$(API_LYFT_CLIENT_ID)` |
| `INFOPLIST_KEY_API_LYFT_CLIENT_SECRET` | `$(API_LYFT_CLIENT_SECRET)` |
| `INFOPLIST_KEY_API_GOOGLE_VISION` | `$(API_GOOGLE_VISION)` |
| `INFOPLIST_KEY_API_SITA_WORLDTRACER` | `$(API_SITA_WORLDTRACER)` |
| `INFOPLIST_KEY_API_ENTERPRISE` | `$(API_ENTERPRISE)` |
| `INFOPLIST_KEY_API_HERTZ` | `$(API_HERTZ)` |
| `INFOPLIST_KEY_API_NATIONAL` | `$(API_NATIONAL)` |
| `INFOPLIST_KEY_API_AMADEUS_CLIENT_ID` | `$(API_AMADEUS_CLIENT_ID)` |
| `INFOPLIST_KEY_API_AMADEUS_CLIENT_SECRET` | `$(API_AMADEUS_CLIENT_SECRET)` |
| `INFOPLIST_KEY_API_DUFFEL` | `$(API_DUFFEL)` |
| `INFOPLIST_KEY_API_SUPABASE_URL` | `$(API_SUPABASE_URL)` |
| `INFOPLIST_KEY_API_SUPABASE_ANON_KEY` | `$(API_SUPABASE_ANON_KEY)` |

## 3. Wire `Products.storekit` to the run scheme

1. **File → Add Files…** → select `JetSetter Pro/JetSetter Pro/Config/Products.storekit`. Add to the **JetSetter Pro target**.
2. **Product → Scheme → Edit Scheme…**
3. Select **Run** in the sidebar → **Options** tab.
4. Set **StoreKit Configuration** to **Products.storekit**.
5. Run the app and verify the paywall shows "Pro Monthly $9.99" / "Pro Annual $69.99" with a 7-day free trial.

When you create the real products in App Store Connect, use the same product IDs:
- `DevJ.JetSetter-Pro.subscription.pro.monthly`
- `DevJ.JetSetter-Pro.subscription.pro.annual`

Grouped under a single subscription group named "Jetsetter Pro".

## 4. Set up Supabase

1. Create a project at https://supabase.com.
2. **Settings → API** → copy **Project URL** and **anon public** key into `Secrets.xcconfig`:
   ```
   API_SUPABASE_URL = https:/$()/yourid.supabase.co
   API_SUPABASE_ANON_KEY = eyJ...
   ```
   The `$()` is a no-op needed because xcconfig treats `//` as a comment delimiter.
3. **SQL Editor → New query** → paste and run the schema below.
4. **Authentication → Providers** → enable **Email** (or **Apple** if you want Sign in with Apple).

### Schema

```sql
-- Expenses
CREATE TABLE expenses (
  id uuid PRIMARY KEY,
  user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
  title text, amount float8, category text,
  date timestamptz, receipt_text text, created_at timestamptz DEFAULT now()
);
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_expenses" ON expenses FOR ALL USING (auth.uid() = user_id);

-- Trips
CREATE TABLE trips (
  id uuid PRIMARY KEY,
  user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
  name text, destination text, start_date timestamptz, end_date timestamptz,
  items jsonb, created_at timestamptz DEFAULT now()
);
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_trips" ON trips FOR ALL USING (auth.uid() = user_id);

-- Wallet items
CREATE TABLE wallet_items (
  id uuid PRIMARY KEY,
  user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
  type text NOT NULL,
  title text,
  subtitle text,
  payload jsonb,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE wallet_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_wallet" ON wallet_items FOR ALL USING (auth.uid() = user_id);

-- Packing lists
CREATE TABLE packing_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
  trip_id uuid NOT NULL,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE packing_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_packing" ON packing_lists FOR ALL USING (auth.uid() = user_id);

-- Disruption events
CREATE TABLE disruption_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
  trip_id uuid NOT NULL,
  event_type text NOT NULL,
  original_flight jsonb NOT NULL,
  alternatives jsonb DEFAULT '[]'::jsonb,
  response_actions jsonb DEFAULT '{}'::jsonb,
  resolved boolean DEFAULT false,
  rebooking_url text,
  hotel_contact text,
  uber_deep_link text,
  insurance_document_id uuid,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE disruption_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_disruptions" ON disruption_events FOR ALL USING (auth.uid() = user_id);
```

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
