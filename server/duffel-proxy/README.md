# Booking proxy (Duffel flights · Expedia auth · Apple Pay via Stripe)

Server-side proxy so **no full-account credential ships in the iOS app**: the
Duffel token, the Expedia (EAN) API key + shared secret, and the Stripe secret
key all live only here as env vars. The app authenticates to this proxy with a
separate shared secret (`PROXY_APP_KEY`, sent as `Authorization: Bearer …`).

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `GET` | `/health` | none | Liveness probe |
| `GET` | `/duffel/aircraft/:id` | Bearer | Quickstart smoke test (Duffel token works) |
| `GET` | `/duffel/orders/:orderId/eligibility` | Bearer | Rebooking eligibility — `DisruptionResponseEngine` |
| `POST` | `/duffel/offer-requests` | Bearer | Flight search → offers (offer ids the app books) |
| `GET` | `/duffel/offers/:offerId` | Bearer | Re-fetch a single offer's authoritative total |
| `POST` | `/duffel/offers/:offerId/order` | Bearer | Create an instant order, paid from **Duffel Balance** |
| `GET` | `/expedia/auth-header` | Bearer | Signed EAN header for Rapid Lodging (secret stays here) |
| `POST` | `/payments/apple-pay/charge` | Bearer | Charge an Apple Pay token via Stripe → PaymentIntent id |
| `POST` | `/expedia/properties/:propertyId/book` | Bearer | **Gated** hotel booking (501 unless `EXPEDIA_BOOKING_ENABLED=true`) |

## Environment

| Var | For | Notes |
|-----|-----|-------|
| `PROXY_APP_KEY` | all | Shared secret the app sends; `openssl rand -hex 32` |
| `DUFFEL_ACCESS_TOKEN` | flights | `duffel_test_…` in sandbox; **fund the Duffel Balance** to pay orders |
| `EXPEDIA_CLIENT_ID` / `EXPEDIA_CLIENT_SECRET` | hotel auth | EAN API key + shared secret (moved off the app) |
| `STRIPE_SECRET_KEY` | payments | `sk_test_…`; upload the Apple Pay cert to Stripe (tied to the Merchant ID) |
| `EXPEDIA_BOOKING_ENABLED` | hotels | Leave unset until a Rapid booking agreement + 3DS/SCA flow exist |

## Order of operations (booking)

Charge first, book second: the app calls `/payments/apple-pay/charge`, then
passes the returned `payment_reference` to `/duffel/offers/:id/order`. The order
route re-fetches the offer server-side for the authoritative total, so a client
can never dictate the price.

## Run locally

```bash
cd server/duffel-proxy
cp .env.example .env          # fill in DUFFEL_ACCESS_TOKEN + PROXY_APP_KEY
npm install
npm start
```

Smoke test (uses the same aircraft ID as the Duffel quickstart):

```bash
curl -H "Authorization: Bearer $PROXY_APP_KEY" \
  http://localhost:8080/duffel/aircraft/arc_00009VMF8AhXSSRnQDI6Hi
```

## Deploy

Any Node host works (Cloud Run, Render, Fly.io, Railway, Heroku). Set two env vars:

- `DUFFEL_ACCESS_TOKEN` — your Duffel token (start with a `duffel_test_...` token)
- `PROXY_APP_KEY` — a random string, e.g. `openssl rand -hex 32`

Then wire the app to the deployed URL by setting these in `Config/Secrets.xcconfig`:

```
API_DUFFEL_PROXY_URL = https://your-proxy-host.example.com
API_DUFFEL_PROXY_KEY = <same value as PROXY_APP_KEY>
```

The app calls `GET {API_DUFFEL_PROXY_URL}/duffel/orders/{id}/eligibility` with
`Authorization: Bearer {API_DUFFEL_PROXY_KEY}`.
