# JetSetter Pro — Investor Pitch Deck: Claude Design Prompt

This file contains a ready-to-use prompt for generating an investor pitch deck with
Claude (claude.ai, the Claude app, or Claude Code's design tooling).

## How to use it

1. Open a new Claude conversation (or use the **Claude in Chrome / Artifacts** canvas).
2. **Attach the 8 screen PNGs** from `pitch-deck/screens/` (`cover, home, disruption,
   iris, wallet, expenses, inflight, paywall`) — or the `_contact-sheet.png` overview.
3. Copy everything below the `=== COPY FROM HERE ===` line and paste it as your message.
4. Fill in every `[BRACKETED]` placeholder first — those are the only facts Claude can't
   infer (raise size, real metrics, team, legal entity, market source). Leave a placeholder
   blank only if you want Claude to draft a sensible stand-in and clearly mark it `[TBD]`.
5. Iterate slide-by-slide ("tighten slide 6", "make the market math more conservative").

> **Honesty note:** JetSetter Pro is a built, **pre-launch / TestFlight-stage** product.
> The prompt is written to *not* fabricate traction. Don't let a generated deck assert
> users/revenue you don't have — keep those as roadmap + clearly-labeled targets until real.

---

=== COPY FROM HERE ===

You are a senior pitch-deck designer and startup storyteller. Build me a **seed-stage
investor pitch deck** for **JetSetter Pro** as a **single self-contained HTML file** —
one full-bleed **16:9** slide per section, navigable with arrow keys, using only inline
CSS and the image files I've attached (reference them by filename). No external assets or
fonts beyond system fonts. Make it look like it was designed by a top product studio.

Treat the **FACTS PACK** below as ground truth — do not invent product capabilities beyond
it. Treat every `[BRACKETED]` value as founder-supplied; if one is blank, insert a
conservative placeholder and render it visibly as `[TBD]` so I know to replace it. Do not
invent traction, revenue, or user numbers.

### BRAND & VISUAL DIRECTION (match the actual app)
- Mood: premium, calm, executive. "Bloomberg terminal meets a private travel concierge."
- Background: deep navy near-black. Primary canvas `#10131E`; hero gradient
  `#06070D → #0D1425 → #091530` (diagonal).
- Surfaces: glass cards `#161929` with a hairline `rgba(59,158,240,.14)` border, 18px
  radius, soft shadow.
- Accent: sky blue `#3B9EF0` (and a brighter `#5BBAFF`); brand gradient
  `#1A72E8 → #5BBAFF → #3A9AF0`. Use it sparingly for emphasis, numbers, CTAs.
- Status semantics: success `#1DB97D`, warning `#E8A020`, danger `#E84040`.
- Text: primary `#ECEEF4`, secondary `#8B92A8`.
- Type: a clean rounded-ish sans (system-ui / SF Pro). Big bold numbers, generous spacing,
  tight letter-spacing on display headings. Lots of negative space. No clip-art, no emoji
  as icons, no stock-photo collages.
- Each slide: small "JetSetter Pro ✈" wordmark + slide number in a corner. Consistent
  margins. One idea per slide.
- The attached PNGs are real product screens — present them inside subtle device framing,
  never stretched, with a soft glow.

### NARRATIVE SPINE (the argument the deck must make)
Frequent business travelers live inside a $X-trillion travel system that is excellent at
*selling* trips and terrible at *protecting* them. When a flight breaks — delay, gate
change, cancellation, missed connection — the traveler becomes their own travel agent at
the worst possible moment: rebooking on hold, re-hailing a car, re-notifying the hotel,
and (almost always) leaving owed compensation on the table. Existing apps each own one
slice — Flighty tracks, TripIt organizes, Navan/Concur handle corporate booking & expense
— but **nobody closes the loop from disruption → rebook → compensation** for the
individual traveler. JetSetter Pro does, with an **agentic AI concierge (IRIS, powered by
Claude)** that already did the work before you've finished reading the alert.

### SLIDE-BY-SLIDE (13 slides — use these exact beats)

1. **Cover.** Wordmark, tagline "Your executive travel companion," one line:
   "The AI co-pilot for the modern business traveler." Use `cover.png`. Footer:
   `[Company legal name]` · `[Founder name]` · `[month year]` · `[contact email]`.
2. **The problem.** 3 stat-blocks on traveler pain: flight disruption frequency, hours
   lost per disrupted trip, and the share of eligible **EU261/DOT compensation that goes
   unclaimed** (~`[VERIFY: large majority]`). Land the emotional truth: *the system helps
   you book, then abandons you when it breaks.*
3. **Why now.** Converging tailwinds: business travel back above pre-2020 `[VERIFY]`;
   record disruption rates; airline NDC/aggregator APIs (Duffel) finally make programmatic
   rebooking possible; and frontier LLMs (Claude) make a true agentic concierge real for
   the first time.
4. **Solution.** One sentence + the home screen (`home.png`): "One app that monitors every
   trip and acts for you." Three pillars: **Anticipate · Act · Recover.**
5. **The wedge — the Disruption Engine.** The hero slide. Use `disruption.png`. Show the
   closed loop as a 4-step flow: **Detect** (background flight monitoring) → **Rebook**
   (live alternatives via Duffel/Amadeus) → **Re-coordinate** (hotel, ride, insurance) →
   **Reclaim** (auto-file EU261/DOT compensation). Headline: "No competitor automates the
   claim. We do." Call out the take-rate opportunity on recovered compensation.
6. **IRIS — agentic AI concierge.** Use `iris.png`. "Powered by Claude." Emphasize it's
   *grounded in the live itinerary* and **acts** (rebook, check in, submit expenses, stage
   a ride), with memory of preferences. Contrast with generic chatbots that only answer.
7. **One trip, fully handled.** A 2×2 of the remaining screens (`wallet.png`,
   `expenses.png`, `inflight.png`, `paywall.png`) showing breadth: Travel Wallet,
   expense OCR → one-tap submit (Brex/Ramp/Expensify/Concur), live in-flight tracking,
   monetization. Caption: "8+ integrated features, one native iOS app."
8. **The moat.** Why this compounds and is hard to copy: (a) the closed loop spans 6+
   integrations most rivals don't hold together; (b) IRIS's per-traveler memory and trip
   graph deepen with use; (c) agent-of-record booking (Duffel + IATA TIDS) + the
   compensation flow create a data + economic flywheel. 2×2 vs. Flighty / TripIt / Navan /
   generic AI — only JetSetter fills every cell.
9. **Market.** TAM/SAM/SOM as concentric rings, conservative + sourced: TAM `[VERIFY:
   global business travel spend]`, SAM `[VERIFY: frequent/road-warrior travelers ×
   willingness to pay]`, SOM `[your 3-yr reachable]`. Keep math legible and defensible.
10. **Business model.** Today: consumer subscription — **$9.99/mo or $69.99/yr**, 7-day
    free trial (show unit economics: `[ARPU]`, `[gross margin]`, `[CAC target]`,
    `[payback]`). Tomorrow: **booking commissions** (agent of record), a **take rate on
    recovered compensation**, and **B2B/teams** seats for SMBs underserved by Navan/Concur.
11. **Go-to-market.** Land where road-warriors already are: frequent-flyer & points
    communities, premium-card / lounge partnerships, targeted social proof, then expand
    consumer → prosumer → team. `[Name any pilots, design partners, or waitlist here]`.
12. **Roadmap & milestones.** Honest stage marker: **product built (native iOS, 153
    files), TestFlight-ready.** Timeline: TestFlight → App Store → disruption-loop GA →
    teams. Mark `[current real metrics, or "pre-launch"]` — do not imply traction we don't
    have.
13. **The ask.** Raising **`[$amount]`** to `[use of funds: ship to App Store, turn on
    live travel APIs, build the rebook↔compensation loop, first GTM]`. Team: `[founders +
    relevant edge]`. Close on the one-liner from the cover + `[contact]`.

### OUTPUT RULES
- Deliver the full HTML in one artifact/file. Each slide is a `<section>` sized to the
  viewport (16:9), keyboard-navigable, print-to-PDF clean (one slide per page).
- Prefer real numbers and crisp verbs over adjectives. No buzzword soup, no "revolutionary."
- Keep body copy to ~20–35 words per slide; let the screens and one big number carry each.
- After the deck, output a short **"founder fill-in list"** of every `[BRACKET]` you used
  so I can complete it.

=== END COPY ===

---

## FACTS PACK (paste this with the prompt — it's the ground truth Claude should use)

**Product.** JetSetter Pro — a native iOS (SwiftUI) app for business / frequent travelers.
~153 Swift files, 8+ integrated feature modules, Firebase (Auth + Firestore) backend.
Tabs: Home · Itinerary · IRIS · Expenses · More. Dark, premium design system.

**Core capabilities (real, in-codebase):**
- **Disruption Engine** — background flight monitoring (FlightAware), and a response engine
  that surfaces alternative flights, notifies the hotel, re-stages an Uber/Lyft, and
  surfaces travel insurance. Rebooking eligibility via Duffel; alternatives via
  Amadeus/Expedia. The intended closed loop: **detect → rebook → re-coordinate → reclaim
  EU261/DOT compensation.**
- **IRIS** — an agentic AI travel concierge **powered by Claude**, grounded in the user's
  live trip + expense context, with per-traveler memory (dietary, seating, airline, hotel
  prefs). Designed to *act*: rebook, check in, submit expenses, stage rides.
- **Travel Wallet** — boarding passes, hotel reservations, car rentals, insurance, loyalty
  accounts (PassKit); check-in.
- **Expenses** — multi-currency tracking, receipt **OCR**, and **one-tap submit** to
  connected providers (Brex, Ramp, Expensify, Divvy, BILL) or a PDF to an approver.
- **Luggage tracker** — AirTag/Find My + SITA WorldTracer carrier data.
- Plus: live in-flight tracking, airport maps, visa lookup, local-experience discovery,
  document vault (AES-GCM encrypted), itinerary, ground transport, rental cars, Apple Watch
  + Live Activity support.

**Integrations referenced in code:** FlightAware (flight data), Anthropic **Claude** (IRIS +
ranking), Duffel (booking/rebooking, agent of record + free IATA **TIDS**), Amadeus,
Expedia, Uber/Lyft, Google Vision (OCR), SITA WorldTracer (baggage), Enterprise/Hertz/
National (rental).

**Positioning (locked):** business / frequent traveler. In-app booking via Duffel (NDC
aggregator — no full IATA accreditation).

**Monetization (live in app):** Pro **$9.99/month** or **$69.99/year**, **7-day free trial**
(StoreKit). Subscription group "Jetsetter Pro."

**Stage:** built product, **TestFlight-ready**; not yet publicly launched. Live travel APIs
are gated behind keys/contracts the founder is provisioning. **No public traction metrics
yet** — keep the deck honest about this.

**Competitive frame:** Flighty (flight tracking), TripIt (itinerary), App in the Air
(assistant), Navan/TravelPerk/Concur (corporate booking + expense). None close the
individual traveler's disruption → rebook → compensation loop end-to-end.

**Brand tokens:** bg `#10131E`; accent `#3B9EF0` / `#5BBAFF`; success `#1DB97D`; warning
`#E8A020`; danger `#E84040`; text `#ECEEF4` / `#8B92A8`; gradient `#1A72E8 → #5BBAFF →
#3A9AF0`; tagline "Your executive travel companion"; "Powered by Claude."

## Founder fill-in checklist (replace before sending, or let Claude mark [TBD])
- [ ] `[Company legal name]`, `[Founder name(s)]`, `[contact email]`, deck date
- [ ] `[$amount]` raising + `[use of funds]`
- [ ] Market sources: business-travel TAM, traveler counts, disruption + unclaimed-comp stats `[VERIFY]`
- [ ] Unit economics: `[ARPU]`, `[gross margin]`, `[CAC target]`, `[payback]`
- [ ] Any real signals: waitlist, design partners, pilots, TestFlight testers
- [ ] Team slide: founders, relevant travel/AI/iOS edge, advisors
