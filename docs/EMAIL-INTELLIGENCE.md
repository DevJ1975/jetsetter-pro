# Email Intelligence — AI email → itinerary/calendar/tasks

_Added 2026-07. iOS-first; designed to port to Android (Gemini Nano) — see
[Portability](#android-portability)._

Forward (or paste) a travel email — flight confirmation, hotel booking, car rental, meeting
invite, or an airline delay/cancellation notice — and AI extracts the details and files them
into the app: **Travel Wallet**, **Itinerary** (trip auto-matched or created), **Calendar**
(meetings), **notifications** (departure alerts), and the **Disruption dashboard** (delay/
cancellation notices — feeding the rebooking wedge).

## Privacy stance (a selling point — market it)

- **On-device first.** On Apple-Intelligence devices (iOS 26+), parsing runs locally via
  FoundationModels guided generation — **the email never leaves the phone.**
- Cloud fallback (Claude) only on devices without Apple Intelligence, and only when the
  Anthropic key is configured; demo mode returns a sample parse.
- Forwarded emails are held server-side **only until first parse** — the app deletes the raw
  row immediately after processing. Nothing auto-commits: the user reviews every extracted
  item before it's saved (v1).

## Architecture

```
 paste / .eml / .txt / .ics ──┐
 PDF (PDFKit, on-device) ─────┤                                ┌→ WalletItem (+ Supabase sync)
 image (Vision OCR, on-device)┼→ TravelEmailParsingService ──→ review UI ─→ TravelEmailCommitService
 forwarding inbox ────────────┘   (FoundationModels @Generable │            ├→ Trip/ItineraryItem (auto-match or create)
   provider webhook               │  or Claude JSON contract)  │            ├→ Calendar event (meetings)
   → inbound-email fn             └── TravelEmailPrompt = the  │            ├→ DisruptionEvent
   → inbound_emails table             shared contract          │            └→ flight departure notification
```

Key files:
- `Core/Services/EmailIntelligence/ParsedTravelModels.swift` — DTOs + `@Generable` mirrors +
  `TravelEmailPrompt` (the shared prompt/JSON contract).
- `Core/Services/EmailIntelligence/TravelEmailParsingService.swift` — provider routing
  (on-device → Claude → mock, same policy as `AIService`).
- `Core/Services/EmailIntelligence/TravelEmailIngestService.swift` — PDF/image/file intake +
  forwarding-inbox fetch/delete.
- `Core/Services/EmailIntelligence/TravelEmailCommitService.swift` — dedupe (fingerprint
  registry; re-forwarded emails **update** instead of duplicate) + writes.
- `Features/EmailImport/` — UI (More → Email Intelligence). `ParseTravelEmailTool` in
  `IRISTools.swift` exposes the same pipeline to IRIS conversationally.
- `supabase/schema.sql` (`email_aliases`, `inbound_emails` + RLS) and
  `supabase/functions/inbound-email/` — forwarding pipeline.

Notable behaviors:
- **Dedupe / update-vs-create:** fingerprints (confirmation # / flight+date) stored under
  `jetsetter_parsed_email_fingerprints`; a matching flight updates the existing wallet item
  (gate change, seat change) rather than duplicating.
- **Timezones:** times are kept exactly as stated in the email (no cross-timezone math);
  the review UI carries a caveat and low-confidence items get a "CHECK" badge.
- **Trip matching:** items land in the trip whose (±1 day) date range contains them, else a
  trip is created (flights/hotels). Meetings map to `ItineraryItem(.activity)` + calendar.

## Owner setup — forwarding pipeline (one-time)

The paste/PDF/screenshot paths work with **zero setup**. The forwarding address needs:

1. **Pick an inbound email provider** (any one):
   - **Cloudflare Email Routing** + a tiny Email Worker that POSTs `{to, subject, text}` JSON
     to the function (cheapest; you already control DNS), or
   - **Postmark Inbound** (posts JSON natively — the function understands its shape), or
   - **SendGrid Inbound Parse** via a small JSON relay.
2. **DNS:** create the inbound subdomain (e.g. `in.jetsetterpro.app`) and point its **MX**
   records at the provider. If you use a different domain, update the display string in
   `EmailImportView` (forwarding card).
3. **Deploy the function:**
   ```
   supabase secrets set INBOUND_EMAIL_SECRET=<long random string>
   supabase functions deploy inbound-email --no-verify-jwt
   ```
4. **Configure the provider webhook** → `https://<ref>.functions.supabase.co/inbound-email`
   with header `x-inbound-secret: <same secret>`.
5. Run the updated `supabase/schema.sql` in the SQL Editor (idempotent).

Aliases are minted by the app on first visit to the screen when signed in
(`SupabaseService.ensureEmailAlias()` → `u-xxxxxxxx`). Unknown aliases are accepted-and-dropped
by the function (200) so probing can't enumerate users.

## Roadmap / deliberately deferred

- **Share Extension** ("Share → JetSetter" from Mail): requires a new Xcode app-extension
  target — pbxproj target surgery we don't do blind from CI (per `docs/HANDOFF.md`). Add it in
  Xcode when convenient; it should call `TravelEmailIngestService` + the same review flow.
- **Connected mailbox (Gmail/Microsoft OAuth):** fast-follow after beta. Budget for Google
  **restricted-scope verification + annual CASA security audit** before building.
- **Auto-commit mode** (skip review for high-confidence items) once precision is proven.
- **.ics structured parsing** (currently fed through the AI like any text — works, but a
  deterministic parser would be cheaper).

## Android portability

The contract Android must reproduce is small and lives in one place:
- `TravelEmailPrompt.instructions` + `TravelEmailPrompt.jsonContract` (the prompt + JSON
  schema), and the snake_case DTO field names in `ParsedTravelModels.swift`.
- On Android: Gemini Nano via **AICore** on supported devices (Pixel 8+, select Galaxy);
  cloud fallback via the same Claude contract; same review-then-commit UX; write into the
  Android equivalents of wallet/trips once those exist.

## Device coverage note

Apple FoundationModels requires an Apple-Intelligence-eligible device on iOS 26+
(`SystemLanguageModel.default.availability`). Everything else (Vision OCR, PDFKit) works on
the iOS 18 floor. Devices without Apple Intelligence and without a Claude key get demo-mode
sample parses — the UI's provider tag always tells the user which path ran.
