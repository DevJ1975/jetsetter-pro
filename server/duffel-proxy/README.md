# Duffel proxy

Thin server-side proxy so the **Duffel access token never ships in the iOS app**.
The token is a full-account credential (it can book and cancel real flights), so
it lives only here, in the `DUFFEL_ACCESS_TOKEN` env var. The app authenticates to
this proxy with a separate shared secret (`PROXY_APP_KEY`).

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `GET` | `/health` | none | Liveness probe |
| `GET` | `/duffel/aircraft/:id` | Bearer `PROXY_APP_KEY` | Quickstart smoke test (confirms the Duffel token works) |
| `GET` | `/duffel/orders/:orderId/eligibility` | Bearer `PROXY_APP_KEY` | Rebooking eligibility — consumed by `DisruptionResponseEngine.checkRebookingEligibility` |

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
