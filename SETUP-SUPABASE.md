# JetSetter Pro — Supabase Backend Setup

The backend is **Supabase** (Auth + Postgres), accessed over the public REST
APIs — **no Supabase SDK / SPM dependency**. `SupabaseService` (`Core/Services/
SupabaseService.swift`) is the implementation; it replaced the previous
`FirebaseService`.

- **Auth:** GoTrue — `{SUPABASE_URL}/auth/v1/*`
- **Data:** PostgREST — `{SUPABASE_URL}/rest/v1/{table}`
- **Account deletion:** the `delete-user` Edge Function (service-role)

Each per-user collection is one table holding an opaque JSON `payload` (the Swift
model, encoded as-is), keyed by the model's UUID `id` and owned by `user_id`.
Row-Level Security restricts every row to its owner.

| Table | Model | Written by |
|---|---|---|
| `expenses` | `Expense` | `syncExpenses` / `fetchExpenses` |
| `trips` | `Trip` | `syncTrips` / `fetchTrips` |
| `wallet_items` | `WalletItem` | `upsert/delete/fetchWalletItems` |
| `packing_lists` | `PackingListResult` | `upsert/fetchPackingList` |
| `disruption_events` | `DisruptionEvent` | `upsert/fetchDisruptionEvents` |

---

## 1. Add the keys to `Secrets.xcconfig`

Supabase Dashboard → **Project Settings**:
- **Data API → Project URL** → `API_SUPABASE_URL`
- **API Keys → publishable key** (`sb_publishable_…`) → `API_SUPABASE_ANON_KEY`

```
# Config/Secrets.xcconfig   (gitignored — never commit real keys)
API_SUPABASE_URL = https:/$()/<your-ref>.supabase.co
API_SUPABASE_ANON_KEY = sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxx
```

> The `$()` is a no-op that stops xcconfig from treating `//` as a comment.

**One-time Xcode wiring** (so the keys reach `Info.plist`):
1. **File → Add Files…** → select `Config/Secrets.xcconfig` (uncheck "Copy items if needed").
2. Project → **Info** tab → **Configurations** → for **Debug** and **Release**,
   set the project-level config to **Secrets**.
3. Build. The target's `INFOPLIST_KEY_API_SUPABASE_URL` / `…_ANON_KEY`
   forwarders (already in `project.pbxproj`) pull the values into `Info.plist`,
   where `SupabaseService` reads them. Without this step the keys read empty and
   the app stays in local-only mode.

## 2. Create the schema

Supabase Dashboard → **SQL Editor → New query** → paste **`supabase/schema.sql`**
and run it. It creates the five tables, indexes, enables RLS, and adds an
owner-only policy on each. Idempotent.

## 3. Auth settings

The app's sign-up flow expects to be signed in immediately. In
**Authentication → Sign In / Providers → Email**, either:
- **Disable "Confirm email"** (immediate session on sign-up — simplest for MVP), or
- Keep it on — then `signUp` returns "check your email", the user confirms, and
  `signIn` works after. `SupabaseService.signUp` handles both.

## 4. Deploy the account-deletion function (App Store Guideline 5.1.1(v))

```
supabase link --project-ref <your-ref>
supabase functions deploy delete-user      # source in supabase/functions/delete-user/
```

The runtime injects `SUPABASE_URL` / `SUPABASE_ANON_KEY` /
`SUPABASE_SERVICE_ROLE_KEY` automatically — no extra secrets to set. Deleting the
auth user cascades to all of their rows via the schema's foreign keys.

## 5. Verify

1. Build & run. Settings → create an account (sign up).
2. Add a wallet item / expense → confirm a row appears in the Supabase Table Editor.
3. Sign in on a second device/simulator → data restores.
4. Settings → Delete Account → confirm the auth user and rows are gone.

---

## Provisioning notes

- The connected Supabase MCP is scoped to the **Trainovations** org. The project
  in `.env.local` (`bmlbbdyytbdmhizdqwnh`) is **not** in that org, so it can't be
  provisioned through the MCP — run `schema.sql` and deploy the function manually
  (above). If you'd rather host the backend in a Trainovations project, say so and
  it can be created + provisioned via MCP (note: a new project may incur cost).
- `API_SUPABASE_ANON_KEY` is a **publishable** client key — safe to ship in the
  app, but still kept out of git via `Secrets.xcconfig`. The **service-role** key
  lives only in the Edge Function runtime, never in the app.
