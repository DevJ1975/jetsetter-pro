# Credentials Checklist

Every credential JetSetter Pro can use, what it turns on, where to get it, and
what it costs. Work top-down — the tiers are ordered by how much they change the
app, not by how hard they are.

**Nothing here blocks running the app.** Every feature falls back to seeded or
empty data when its key is missing, and demo mode is fully walkable on a device
with zero credentials (**Settings → App Mode**). Add keys to turn features live
one at a time.

**Where keys go:** `Config/Secrets.xcconfig` (gitignored — copy it from
`Config/Secrets.xcconfig.example`). One `KEY = value` per line, no quotes. The
one-time Xcode wiring step is `SETUP.md` §1; if you skip it every key reads as
empty and the app silently serves mock data. Verify with:

```bash
python3 scripts/preflight.py --app "<built .app>"     # reports "credentials set N/29"
```

Prices below are the pricing *model* plus a link, not quoted figures — check the
linked page for current numbers before committing.

---

## Tier 1 — Do this first

### ☐ Supabase — accounts, sync, account deletion

The active backend. Without it there is no sign-in, no cross-device sync, and no
in-app account deletion (which App Store Guideline 5.1.1(v) requires, so this is
also a submission blocker).

| | |
|---|---|
| **Site** | https://supabase.com/dashboard |
| **Cost** | Free tier covers 2 active projects. Your org (`hludqosqlfsnpnjwcgez`) already has 9 active, so a 10th is **$10/month**. |
| **Keys** | `API_SUPABASE_URL`, `API_SUPABASE_ANON_KEY` |

1. New project → name it, pick a region near your users.
2. **Settings → API**. Copy **Project URL** → `API_SUPABASE_URL`.
3. Same page, copy the **`anon` / `public`** key → `API_SUPABASE_ANON_KEY`.
   **Not** the `service_role` key — that one grants full database access and must
   never ship in an app binary.
4. Apply the schema and the account-deletion function:
   ```bash
   supabase link --project-ref <ref>
   supabase db push                        # supabase/migrations/0001_init.sql
   supabase functions deploy delete-account
   ```
5. Confirm **Advisors → Security** reports no "RLS disabled in public" findings.
   The anon key is extractable from the binary; the RLS policies are the only
   thing keeping one user's trips out of another's account.

> The schema is already written and tested — see `supabase/README.md`. CI proves
> the policies actually isolate users on every push.

---

## Tier 2 — Self-serve, high impact

### ☐ Anthropic — IRIS assistant, smart packing, AI cards

| | |
|---|---|
| **Site** | https://console.anthropic.com |
| **Cost** | Pay-as-you-go per token, no subscription. Pricing: https://www.anthropic.com/pricing |
| **Key** | `API_ANTHROPIC` |

Sign up → **API Keys** → *Create Key*. Add billing before it will serve traffic.
Set a monthly spend cap while you're testing.

### ☐ FlightAware AeroAPI — flight tracking, disruption monitoring, departure board

Powers the background disruption poll, so it's the difference between the app
noticing your flight moved and not.

| | |
|---|---|
| **Site** | https://www.flightaware.com/aeroapi/portal/ |
| **Cost** | Tiered, per-query. A free/personal tier exists with a low monthly cap. Pricing: https://www.flightaware.com/aeroapi/portal/pricing |
| **Key** | `API_FLIGHTAWARE` |

Create an AeroAPI account (separate from a normal FlightAware login) → select a
tier → copy the API key from the portal.

### ☐ Amadeus for Developers — check-in flow, rebooking search

| | |
|---|---|
| **Site** | https://developers.amadeus.com |
| **Cost** | **Free** Self-Service test tier. Production access needs a separate application and is usage-priced. |
| **Keys** | `API_AMADEUS_CLIENT_ID`, `API_AMADEUS_CLIENT_SECRET` |

Register → **My Self-Service Workspace** → create an app → copy **API Key** and
**API Secret**.

> The app already points at `test.api.amadeus.com` in Debug and the production
> host in Release. Test credentials will **not** work against a Release build —
> that's deliberate, not a bug.

### ☐ Google Cloud Vision — receipt OCR

| | |
|---|---|
| **Site** | https://console.cloud.google.com |
| **Cost** | Free monthly allowance of units, then per-1,000 pricing. https://cloud.google.com/vision/pricing |
| **Key** | `API_GOOGLE_VISION` |

Create a project → enable **Cloud Vision API** → **Credentials** → *Create
credentials → API key*. Restrict the key to the Vision API.

---

## Tier 3 — Self-serve, narrower features

### ☐ Duffel — flight booking and rebooking

**This token does not go in the app.** Duffel is reached through
`server/duffel-proxy` so the access token stays server-side; a token shipped in
the binary is extractable and can book flights on your account.

| | |
|---|---|
| **Site** | https://app.duffel.com |
| **Cost** | Free to sign up; test mode is free. Live bookings are commercial — https://duffel.com/pricing |
| **Goes in** | the proxy's `.env`, as `DUFFEL_ACCESS_TOKEN` |
| **App keys** | `API_DUFFEL_PROXY_URL`, `API_DUFFEL_PROXY_KEY` |

1. Duffel dashboard → **Developers → Access tokens**. Start with a **test**
   token (`duffel_test_…`).
2. Deploy `server/duffel-proxy` (Cloud Run, Render, Fly, Heroku — it's a small
   Node service and reads `PORT`). Set `DUFFEL_ACCESS_TOKEN` there.
3. Generate the shared secret the app uses to reach your proxy:
   ```bash
   openssl rand -hex 32
   ```
   Put it in the proxy's `PROXY_APP_KEY` **and** in `API_DUFFEL_PROXY_KEY`.
4. Put the deployed base URL in `API_DUFFEL_PROXY_URL`.

### ☐ Uber — ride estimates and deep links

| | |
|---|---|
| **Site** | https://developer.uber.com |
| **Cost** | Free to register. Ride-request scopes need review. |
| **Keys** | `API_UBER_CLIENT_ID`, `API_UBER_CLIENT_SECRET` |

Create an app → **Auth** tab → copy Client ID and Client Secret. The app mints a
Bearer token via OAuth2 client-credentials.

> `API_UBER_SERVER_TOKEN` is legacy — Uber retired server tokens. Leave it blank.

### ☐ Lyft — ride estimates

| | |
|---|---|
| **Site** | https://developer.lyft.com |
| **Cost** | Free to register. |
| **Keys** | `API_LYFT_CLIENT_ID`, `API_LYFT_CLIENT_SECRET` |

Lyft has restricted new public API access at various points — if the developer
portal won't issue credentials, skip it. The app falls back to a deep link into
the Lyft app and then to `ride.lyft.com`, so the feature degrades cleanly.

### ☐ Expedia — hotel search and booking

| | |
|---|---|
| **Site** | https://partner.expediagroup.com (Rapid / Expedia Partner Solutions) |
| **Cost** | No self-serve tier — requires a partner agreement. |
| **Keys** | `API_EXPEDIA_CLIENT_ID`, `API_EXPEDIA_CLIENT_SECRET` |

Expect a commercial conversation, not a signup form. Reasonable to defer.

---

## Tier 4 — Require a business agreement

None of these are self-serve. Each needs a corporate/partner relationship, so
treat them as post-launch unless you already have one. All the app-side wiring is
in place; only the credential is missing.

| Service | Unlocks | Where to start | Key(s) |
|---|---|---|---|
| ☐ SITA WorldTracer | Luggage tracking | https://www.sita.aero — contact sales | `API_SITA_WORLDTRACER` |
| ☐ Enterprise | Rental car availability | Enterprise business/API partnerships | `API_ENTERPRISE` |
| ☐ Hertz | Rental car availability | Hertz partner/affiliate program | `API_HERTZ` |
| ☐ National | Rental car availability | National business partnerships | `API_NATIONAL` |
| ☐ Ramp | Expense submission | https://docs.ramp.com — partner onboarding | `API_RAMP_CLIENT_ID`, `API_RAMP_CLIENT_SECRET` |
| ☐ Brex | Expense submission | https://developer.brex.com | `API_BREX_CLIENT_ID` |
| ☐ BILL Spend & Expense | Expense submission | https://developer.bill.com | `API_BILL_SPEND_TOKEN` |

---

## Leave blank — declared but unused

These are in `Secrets.xcconfig.example` but no code reads them. Filling them in
does nothing.

| Key | Why |
|---|---|
| `API_FIREBASE_PROJECT_ID` | Firebase was retired in favour of Supabase |
| `API_FIREBASE_API_KEY` | as above |
| `API_EXPENSIFY_PARTNER_KEY` | no Expensify provider implemented |
| `API_DIVVY_CLIENT_ID` | superseded by `API_BILL_SPEND_TOKEN` (Divvy became BILL Spend & Expense) |
| `API_DUFFEL` | **Leave blank deliberately.** The raw Duffel token belongs in the proxy's `.env`, never in the app binary. |

---

## Suggested order

1. **Supabase** — unblocks accounts, sync, and the Guideline 5.1.1(v) submission requirement.
2. **Anthropic** — cheap, instant, and turns on the most visible feature (IRIS).
3. **FlightAware** — makes disruption monitoring real.
4. **Amadeus** (free test tier) — check-in and rebooking.
5. **Google Vision** — receipt OCR.
6. **Duffel + proxy** — only if you want live booking.
7. Everything else as the partnerships land.

After each one, rebuild and re-run `python3 scripts/preflight.py --app "<built .app>"`
— the `credentials set N/29` count should tick up by exactly what you added.
