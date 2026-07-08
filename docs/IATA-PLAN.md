# JetSetter Pro — IATA / Industry-Accreditation Plan (Phased)

_Researched 2026-07. Every dollar figure below came from triangulated secondary sources because
iata.org / iatan.org / arccorp.com block automated access — treat amounts as directionally
reliable and **confirm on the official portals before filing anything**._

## The decision

This plan **extends** (does not reverse) the locked decision "Duffel as agent-of-record, no full
IATA accreditation":

- **Phase 1 — now:** obtain a **non-ticketing industry code** (supplier recognition + commissions;
  no bonding, no settlement ops). Duffel keeps issuing tickets as agent of record.
- **Phase 2 — later, trigger-gated:** full **ARC (+ IATAN)** ticketing accreditation, i.e. become
  our own agent of record and cut out Duffel's per-order margin — only when volume justifies the
  bond + ops burden (see [Breakeven trigger](#breakeven-trigger)).

## ⚠️ US flag — "TIDS" is probably not our path

Multiple sources attribute to IATA that **the TIDS program is available globally _except in the
USA_**; for US-registered entities the equivalent is IATA's US arm, **IATAN**, via its
**Non-Ticketing accreditation** (one conflicting source says US entities can use TIDS).
**Action: confirm directly with IATA/IATAN before filing.** Functionally the outcome is the same
either way: a supplier-recognized code + commission eligibility, with no ticketing authority.

## Phase 1 — get a non-ticketing code (do now)

Two US options — pick after the confirmation call above:

| | **IATAN Non-Ticketing** | **ARC Verified Travel Consultant (VTC)** |
|---|---|---|
| Application fee | **$280** (Head Office; $110 ICB, $450 CTD) — 2026 schedule | **~$105** |
| Annual fee | ~ $120–210 (verify) | **~$195** |
| Bond | None | **None** |
| Financial criterion | New/home-based: show **$10,000 available** (bank letter ≤3 months old) | Lighter |
| E&O insurance | Required, **waivable** with 2 yrs experience or a recognized cert (ARC Specialist, CTA, …) | — |
| Timeline | **~4–6 weeks** | Weeks |
| Grants | IATAN code, supplier recognition/commissions, path to IATAN ID card | ARC-recognized identifier, commissions |

### Application checklist (either route)
1. ☐ **Call IATAN** — confirm US routing (TIDS vs IATAN Non-Ticketing) and current fees.
2. ☐ Entity documents: Articles of Incorporation / proof of ownership, business registration +
   tax ID, bank letter or statement **in the business name**.
3. ☐ **Letter of recommendation** from an IATA airline, GDS, or major supplier — _the hard part
   for a new tech company._ Best sources for us: **Duffel** (our NDC partner), Expedia/EPS once the
   Rapid contract exists, or a GDS contact. Line this up first.
4. ☐ Seller-of-Travel registration where required (**CA, FL, WA, HI** have their own laws —
   separate from IATA/ARC and they routinely bite OTAs).
5. ☐ Apply on the IATAN portal (or IATA Customer Portal → TIDS if the US carve-out turns out not
   to apply). TIDS processing is ~3–5 business days; IATAN ~4–6 weeks.
6. ☐ Calendar: **annual revalidation** (TIDS) / annual fees (IATAN/ARC) — missing revalidation
   terminates the code and IATA notifies suppliers.

### What the code does / does not do
- ✅ Unique industry identifier recognized by airlines, hotel chains, car/cruise/rail suppliers.
- ✅ Bookings attributable to us → **supplier commissions & agent rates** (improves hotel-OTA
  economics; useful in Booking.com/Expedia partner negotiations).
- ✅ Credibility for partner applications.
- ❌ **No ticketing authority, no BSP/ARC settlement access** — that's Phase 2. Duffel keeps
  ticketing.
- ❌ Not an inventory/content deal — GDS/API access is still negotiated separately.

## Phase 2 — full ticketing accreditation (later)

For a **US** company the ticketing path is **ARC** (the US settlement system; BSP does not operate
in the US) plus IATAN; the IATA **GoLite/GoStandard/GoGlobal** tiers are BSP programs and would
only matter if we ever ticket in non-US markets.

Requirements (verify current figures with ARC):
- Application **~$3,000** (older sources say $2,300) + **~$206/yr**.
- **Bond / LOC / cash deposit — minimum $20,000** (scales with cash sales; surety premium ≈1%).
- Designated agency manager + an **ARC Specialist** on staff; E&O insurance.
- Real back-office work: weekly ARC settlement/reporting, compliance.

What it buys: issue tickets ourselves (drop Duffel's $3 + 1%/order + $2/ancillary), direct airline
/NDC relationships, agent rates, IATAN ID cards for staff.

## Breakeven trigger

Revisit Phase 2 when, for ~3 consecutive months:

```
Duffel fees  =  orders × ($3 + 1% × avg_order_value) + ancillaries × $2
ARC cost     ≈  ($3,000 amortized /12) + $206/12 + bond premium (~$200/yr /12)
                + E&O premium + ARC-Specialist staffing/ops time
→ trigger when Duffel fees > ARC cost, sustained
```

Example: at $600 avg order, Duffel ≈ $9/order. ARC fixed costs + ops realistically run
$1,500–3,000+/mo once staffing is counted → the conversation starts around **~200–350 orders/mo**
and gets compelling above that. (Fill in real AOV once bookings exist.)

## Notes specific to a software platform / OTA

- An **OTA/app is an eligible category** — no storefront needed; the accredited thing is the
  **legal entity**, not the app.
- White-label / third-party fulfillment (our model: Duffel, Expedia) still qualifies.
- The recommendation letter is the usual failure point — secure a supplier/GDS reference before
  applying.
- A code ≠ ticketing ≠ content: three separate negotiations.

## Sources

IATA TIDS application/FAQ/suppliers pages (iata.org/tids) · IATAN Requirements & Fees + 2026 fee
schedule + ID-card eligibility (iatan.org) · ARC VTC page (arccorp.com) · SuretyBonds ARC guide ·
AltexSoft travel-agency-accreditation & ARC guides · Host Agency Reviews · travelobiz (TIDS/US
carve-out) · Mize (IATA numbers for OTAs) · WisePassenger / SkyBook (Go-tier structure).
_Direct fetches of the official sites were blocked (HTTP 403); figures triangulated from
search-engine summaries of those pages + the secondary sources above._
