# JetSetter Pro — Pitch Deck Assets

Investor-pitch material for **JetSetter Pro**: a set of polished product screenshots and a
ready-to-use Claude prompt for generating the deck itself.

```
pitch-deck/
├── CLAUDE-PITCH-DECK-PROMPT.md   ← paste-into-Claude prompt + facts pack to build the deck
├── screens/                      ← 9 product screenshots (1263×2640, @3x) + contact sheet
│   ├── cover.png        home.png        disruption.png   iris.png
│   ├── wallet.png       expenses.png    inflight.png     paywall.png
│   ├── emailimport.png
│   └── _contact-sheet.png         ← all 9 in one branded overview (good appendix slide)
└── assets/
    ├── mockups.html     ← source for the 9 screens (regenerable)
    └── contact-sheet.html
```

## The screenshots

Nine flagship screens, in the app's signature **dark-navy** theme, populated with the
app's **real seeded demo data** (Boston Pitch Day · DL2244; the Tokyo Summit AA169 typhoon
disruption; loyalty tiers; Tokyo expenses):

| # | File | What it sells |
|---|------|---------------|
| 1 | `cover.png` | Brand / executive positioning |
| 2 | `home.png` | Single active-trip command center |
| 3 | `disruption.png` | **The wedge** — disruption → rebook → EU261/DOT compensation |
| 4 | `iris.png` | IRIS, the agentic AI concierge (powered by Claude) |
| 5 | `wallet.png` | Travel Wallet — boarding pass, hotel, insurance |
| 6 | `expenses.png` | Multi-currency expenses → one-tap submit to Ramp |
| 7 | `inflight.png` | Live in-flight tracking |
| 8 | `paywall.png` | Monetization — $9.99/mo · $69.99/yr |
| 9 | `emailimport.png` | **Email Intelligence** — forward a booking email, parsed on-device → wallet/itinerary |

> **How these were made (transparency):** they are **high-fidelity HTML/CSS mockups**, not
> live iOS-simulator captures — this build environment is Linux with no macOS/Xcode. They
> were hand-built to match the real `JetsetterTheme` design tokens (colors, radii, glass
> cards, typography) and the real view layouts + seeded content, then rendered with
> headless Chromium at 3×. For App Store screenshots you'll still want true simulator/device
> captures; for a pitch deck these are intentionally cleaner than raw captures.

### Regenerating

Requires Node 18+ and `playwright` (plus a Chromium build — one ships under
`/opt/pw-browsers` in this environment). Run from the repo root:

```bash
node pitch-deck/scripts/render-screens.mjs        # → pitch-deck/screens/*.png  (9 screens)
node pitch-deck/scripts/render-contact-sheet.mjs  # → pitch-deck/screens/_contact-sheet.png
```

Edit `assets/mockups.html` to tweak any screen, then re-run. Colors/data live inline so a
non-iOS contributor can adjust them.

## The deck

Open `CLAUDE-PITCH-DECK-PROMPT.md`, fill in the `[BRACKETED]` placeholders, attach the
PNGs, and paste the prompt into Claude to generate a 13-slide, 16:9 HTML deck. The prompt
carries a **facts pack** (real product capabilities, integrations, pricing, brand tokens)
so the output stays accurate, and is written to keep the **pre-launch** stage honest — it
won't fabricate traction.
