# JetSetter Pro — Supabase Backend Setup

**The backend is Supabase** — GoTrue auth (`/auth/v1`) + PostgREST data
(`/rest/v1`), called over REST with no SDK (mirrors the app's minimal-dependency
design). This guide covers the keys, the one-time Xcode wiring, the schema, auth,
and the edge functions.

`SupabaseService.swift` is the single backend actor. It reads
`API_SUPABASE_URL` / `API_SUPABASE_ANON_KEY` from `Info.plist` (forwarded from
`Secrets.xcconfig`). If they're blank, the app runs fully on device with demo
data — nothing breaks.

---

## 1. Create the project + copy the keys

1. Create a project at https://supabase.com.
2. **Project Settings → API** → copy **Project URL** and the **anon public** key
   into `Config/Secrets.xcconfig`:
   ```
   API_SUPABASE_URL = https:/$()/YOUR-REF.supabase.co
   API_SUPABASE_ANON_KEY = eyJ...
   ```
   > The `$()` in the URL is a no-op that stops xcconfig from treating `//` as a
   > comment. Copy it exactly.

## 2. One-time Xcode base-config wiring

`SupabaseService` reads the keys from `Info.plist`, which are populated from
`Secrets.xcconfig`. That file only feeds the build once it's set as the project's
base configuration:

1. **File → Add Files to "JetSetter Pro"…** → select `Config/Secrets.xcconfig`,
   **uncheck** "Copy items if needed", add to **no** target.
2. Project (top of navigator) → **Info** tab → **Configurations**.
3. For **both Debug and Release**, set the **project row's** "Based on
   Configuration File" dropdown to **Secrets**.
4. Build once. The `INFOPLIST_KEY_API_SUPABASE_*` forwarders (already in the
   target's build settings) now carry the values into `Info.plist`.

> Without step 3 the keys read `nil` and every Supabase call no-ops to local data.

## 3. Schema + row-level security

> **Privacy note — financial data is moving off the cloud.** Per product
> decision, users' **financial information (expenses, currency amounts, receipt
> text/images) will be stored on-device only in SQLite** and will **not** sync to
> Supabase. The `expenses` table below is retained for now but is being retired
> by a separate workstream; do not build new features against cloud-stored
> expenses. Trips, wallet passes, packing lists, disruption events, and travel
> signals remain cloud-synced.

**SQL Editor → New query** → paste and run:

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

Every table is owner-scoped via RLS (`auth.uid() = user_id`), so the anon key
shipped in the app can only ever read/write the signed-in user's own rows.

## 4. Auth

**Authentication → Providers** → enable **Email** (add **Apple** too if you want
Sign in with Apple). The app is anonymous-first; an email upgrade links the
existing `uid` so on-device data carries over.

## 5. Edge functions

Deploy the two functions the app expects (requires the Supabase CLI, logged in
and linked to this project):

```bash
# Claude proxy — keeps the Anthropic key server-side (see supabase/functions/claude-proxy)
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy claude-proxy
# then set API_CLAUDE_PROXY_URL in Secrets.xcconfig to the function's URL:
#   https://YOUR-REF.supabase.co/functions/v1/claude-proxy

# Account deletion — App Store Guideline 5.1.1(v); service-role wipe of the user's rows + auth account
supabase functions deploy delete-user
```

## 6. Verify

1. Build + run. Sign up with an email → confirm a row appears in `trips` /
   `expenses` after you create one.
2. Install on a second device, sign in → your data restores.
3. Settings → **Delete Account** → the auth user and all their rows are removed.
4. IRIS chat + Smart Packing List stream via the proxy — confirm no Anthropic key
   is in the built `.app` (`strings` it and grep for `sk-ant`).
