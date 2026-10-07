# JetSetter Pro backend API (v1)

Django + DRF service in `backend/`, deployed on Railway. The iOS app talks to it for **Duffel flight booking** and for retrieving every booking the traveler has made through the app. The Duffel token, Stripe keys and all other credentials live only on the server.

- Base URL: `API_BACKEND_URL` (Info.plist key) + `/api/v1`, e.g. `https://jetsetter-api.up.railway.app/api/v1`
- JSON in and out, **snake_case** keys (decode with `.convertFromSnakeCase`; encode with explicit `CodingKeys` or `.convertToSnakeCase`).
- Money is always a **decimal string** plus a 3-letter ISO currency (`"245.30"`, `"USD"`). Never a float.
- Timestamps are ISO-8601 UTC (`2026-11-02T14:05:00Z`). Flight times (`departing_at`, `arriving_at`) are **local wall-clock time at the airport, no zone**, exactly as Duffel returns them (`2026-11-02T09:05:00`); pair them with the airport's time zone, never the device's.
- Auth: every route except `/health/`, `/api/v1/config`, `/api/v1/devices/register` and the webhooks needs `Authorization: Token <token>`.
- Errors: non-2xx responses are `{"error": "<machine_code>", "message": "<sentence safe to show the traveler>"}`, plus extra keys for specific codes.

## Error codes

| HTTP | `error` | Meaning |
|---|---|---|
| 400 | `validation_error` | Bad input. `fields` maps field → messages. |
| 401 | `not_authenticated` | Missing/invalid token → re-register the device. |
| 404 | `not_found` | No such offer/booking for this device. |
| 409 | `price_changed` | Fare moved since the traveler saw it. Body also has `offer` (fresh). Show the new price and re-confirm. |
| 409 | `offer_expired` | Offer is gone. Search again. |
| 409 | `not_cancellable` / `invalid_state` | Action not allowed in the booking's current status. |
| 429 | `throttled` | Slow down. `Retry-After` header set. |
| 502 | `upstream_error` | Duffel/Stripe failed. Safe to retry searches; **never** auto-retry a checkout, fetch the booking instead. |
| 503 | `flights_unavailable` | Server has no Duffel credentials. App falls back to vendor hand-off. |

## Endpoints

### `GET /health/` (no auth)
`{"status":"ok"}` (checks the database).

### `GET /api/v1/config` (no auth)
```json
{
  "flights_enabled": true,
  "payments_enabled": true,
  "test_mode": false,
  "support_email": "support@…",
  "privacy_url": "https://…/privacy/",
  "terms_url": "https://…/terms/",
  "support_url": "https://…/support/"
}
```
`flights_enabled` is false when Duffel isn't configured. `test_mode` is true when the server runs on a `duffel_test_…` token (bookings are fake and cost nothing: the app must show a "Test booking" banner).

### `POST /api/v1/devices/register` (no auth)
Body: `{}` (optional `{"app_version":"1.0","platform":"ios"}`). Creates an anonymous traveler record.
`201 {"device_id":"<uuid>","token":"<opaque>"}`. Store both in the Keychain. Throttled per IP.

### `DELETE /api/v1/account`
Erases the device and its personal data (App Store guideline 5.1.1(v)). Bookings keep only the airline reference, totals and dates needed for accounting/refunds. `204`.

### `POST /api/v1/flights/search`
```json
{
  "slices": [
    {"origin": "LAS", "destination": "ATL", "departure_date": "2026-11-02"},
    {"origin": "ATL", "destination": "LAS", "departure_date": "2026-11-05"}
  ],
  "passengers": {"adults": 1, "children": 0, "infants": 0},
  "cabin_class": "economy"
}
```
`cabin_class`: `economy | premium_economy | business | first`. 1–4 slices; 1–9 adults.
`200 {"search_id": "orq_…", "offers": [Offer…]}` – sorted cheapest first, capped at 40.

### `GET /api/v1/flights/offers/{offer_id}`
Fresh `Offer` straight from Duffel. Use it right before the traveler form so the price and the `passengers[].id` values are current.

### `POST /api/v1/flights/offers/{offer_id}/checkout`
Creates the booking and starts payment. Body:
```json
{
  "expected_total_amount": "245.30",
  "expected_total_currency": "USD",
  "passengers": [{
    "id": "pas_…",
    "title": "mr", "given_name": "Ada", "family_name": "Lovelace",
    "born_on": "1990-12-10", "gender": "f",
    "email": "ada@example.com", "phone_number": "+14155550123",
    "identity_documents": [{"type":"passport","unique_identifier":"X123","issuing_country_code":"US","expires_on":"2032-01-01"}]
  }]
}
```
`id` must be the passenger id Duffel returned on the offer. `identity_documents` is only required when the offer has `requires_identity_documents: true`. `title`: `mr|mrs|ms|miss|dr`; `gender`: `m|f`.

The server re-fetches the offer, compares the price with `expected_total_*` (409 `price_changed` on mismatch), then:

- **Stripe configured:** `201 {"booking": Booking(status="pending_payment"), "checkout_url": "https://checkout.stripe.com/…"}`. Open `checkout_url` in the in-app browser. Stripe's page offers Apple Pay and cards. The server creates the airline order from Stripe's webhook once payment clears, so it completes even if the app is closed. Poll `GET /bookings/{id}` every 2 s (up to ~2 min) after the browser closes.
- **Test mode (`duffel_test_…` token, no Stripe):** `201 {"booking": Booking(status="confirmed"), "checkout_url": null}`. No payment step.

### `GET /api/v1/bookings`
`{"bookings": [Booking…]}` newest first, this device only.

### `GET /api/v1/bookings/{id}?refresh=true`
One `Booking`. `refresh=true` re-reads the order from Duffel (schedule changes, tickets, baggage) before answering.

### `POST /api/v1/bookings/{id}/cancel/quote`
For `confirmed` bookings. `200 {"cancellation_id":"ore_…","refund_amount":"120.00","refund_currency":"USD","expires_at":"…"}`. `refund_amount` may be `"0.00"`.

### `POST /api/v1/bookings/{id}/cancel/confirm`
Body `{"cancellation_id":"ore_…"}`. Cancels with the airline and refunds the card for `refund_amount`. `200 Booking(status="cancelled")`.

### `GET /api/v1/handoff/{flights|hotels|cars}?…`
Vendor hand-off links for searches that finish on the vendor's own site (Delta, Hertz, Kayak, …). Query: flights `origin,destination,depart,return?,adults`, hotels `destination,check_in,check_out,guests`, cars `pickup,pickup_date,dropoff_date`.
`200 {"providers":[{"id":"delta","name":"Delta Air Lines","url":"https://…","kind":"airline"|"agency"|"hotel"|"car_rental"}]}`. After the traveler comes back from a vendor site the app offers **Save your booking** (paste/screenshot capture) so the reservation lands in the itinerary.

### Webhooks (server to server, no token)
`POST /webhooks/stripe/` (verified with `STRIPE_WEBHOOK_SECRET`) and `POST /webhooks/duffel/` (verified with `DUFFEL_WEBHOOK_SECRET`). Not called by the app.

## Objects

### Offer
```json
{
  "id": "off_…",
  "airline": {"name": "Delta Air Lines", "iata_code": "DL", "logo_url": "https://…"},
  "total_amount": "245.30", "total_currency": "USD",
  "cabin_class": "economy",
  "slices": [Slice],
  "passengers": [{"id": "pas_…", "type": "adult"}],
  "requires_identity_documents": false,
  "conditions": Conditions,
  "baggage": [{"type": "checked", "quantity": 1}, {"type": "carry_on", "quantity": 1}],
  "expires_at": "2026-10-07T18:00:00Z"
}
```
`total_amount` is what the traveler pays (Duffel total + any server service fee; the fee is itemised in `fee_amount`).

### Slice
```json
{
  "origin": {"iata_code":"LAS","name":"Harry Reid International","city_name":"Las Vegas","time_zone":"America/Los_Angeles"},
  "destination": {"iata_code":"ATL","name":"…","city_name":"Atlanta","time_zone":"America/New_York"},
  "duration": "PT4H10M",
  "stops": 0,
  "fare_brand_name": "Main Cabin",
  "segments": [{
    "marketing_carrier": {"name":"Delta Air Lines","iata_code":"DL"},
    "flight_number": "DL1423",
    "origin": {…Airport}, "destination": {…Airport},
    "departing_at": "2026-11-02T09:05:00", "arriving_at": "2026-11-02T16:15:00",
    "duration": "PT4H10M",
    "aircraft": "Boeing 737-900",
    "origin_terminal": "1", "destination_terminal": "S"
  }]
}
```
`flight_number` is already the full designator (carrier code + number).

### Conditions
```json
{
  "refund_before_departure": {"allowed": true, "penalty_amount": "50.00", "penalty_currency": "USD"},
  "change_before_departure": {"allowed": true, "penalty_amount": null, "penalty_currency": null}
}
```
Either side can be `null` when the airline didn't say.

### Booking
```json
{
  "id": "<uuid>",
  "kind": "flight",
  "status": "confirmed",
  "status_detail": "Ticketed",
  "booking_reference": "ABC123",
  "duffel_order_id": "ord_…",
  "total_amount": "245.30", "total_currency": "USD",
  "fee_amount": "0.00",
  "test_mode": false,
  "airline": {"name":"Delta Air Lines","iata_code":"DL","logo_url":null},
  "slices": [Slice],
  "passengers": [{"id":"pas_…","type":"adult","title":"mr","given_name":"Ada","family_name":"Lovelace","ticket_number":"006-1234567890","seat":null}],
  "baggage": [{"type":"checked","quantity":1}],
  "conditions": Conditions,
  "has_airline_changes": false,
  "refund": {"amount":"120.00","currency":"USD","status":"succeeded"} ,
  "created_at": "…", "updated_at": "…"
}
```
`status`: `pending_payment` (waiting on Stripe) → `processing` (paid, ordering with the airline) → `confirmed`. Terminal alternatives: `failed` (nothing was charged, or the charge was refunded: see `status_detail`), `cancelled` (traveler cancelled), `expired` (never paid). `refund` is null unless money was returned. `booking_reference` is the airline PNR the traveler uses at check-in; show it prominently.

## What the app does with a confirmed booking
1. Adds a flight `ItineraryItem` per slice (confirmation = `booking_reference`, provider = airline, local times + airport time zones) to the matching trip, creating one if none overlaps.
2. Adds a boarding-pass-type wallet item whose `rawData` carries `duffel_order_id` and `booking_reference` (used by disruption rebooking).
3. Re-syncs `GET /bookings` on launch/foreground and when My Bookings opens, updating times if the airline changed them.
