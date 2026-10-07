# JetSetter Pro API (Django)

Django + DRF service that lets the iOS app **book flights through Duffel**, take payment through **Stripe Checkout**, and **retrieve every booking** made from a device. API contract: [`docs/BACKEND_API.md`](../docs/BACKEND_API.md).

```
iOS app ──▶ Django (Railway) ──▶ Duffel   (search, orders, cancellations)
                │        ▲
                │        └── webhooks ◀── Stripe (payment received) / Duffel (airline changes)
                └──▶ Postgres (bookings, devices)
```

Why Stripe *Checkout* (a hosted page) and not an in-app card form: no card data and no extra SDK in the app, Apple Pay is offered by Stripe's page, and the airline order is created from Stripe's webhook, so a booking completes even if the app is killed mid-payment. Flights are real-world services, so App Store rule 3.1.3(e) lets you take payment outside In-App Purchase.

## Deploy on Railway

1. **New Project → Deploy from GitHub repo** → `DevJ1975/jetsetter-pro`. In the service **Settings → Root Directory** set `/backend` (it picks up `railway.toml`: collectstatic at build, `migrate` before each deploy, gunicorn, `/health/` check).
2. **Add Postgres** (`+ New → Database → PostgreSQL`). In the Django service Variables add `DATABASE_URL` = `${{Postgres.DATABASE_URL}}`.
3. **Variables** (see `.env.example`):

   | Variable | Value |
   |---|---|
   | `DJANGO_SECRET_KEY` | `openssl rand -hex 32` |
   | `DUFFEL_ACCESS_TOKEN` | start with a `duffel_test_…` token |
   | `COMPANY_NAME`, `SUPPORT_EMAIL` | printed on the privacy/terms/support pages (App Store requires a working support contact) |
   | `PUBLIC_BASE_URL` | only if you add a custom domain (defaults to the Railway domain) |
4. **Settings → Networking → Generate Domain.** That URL + `/api/v1` is what goes in the app (`API_BACKEND_URL`).
5. Create an admin login: Railway shell → `python manage.py createsuperuser`; then `/admin/` shows bookings, with anything needing a human at the top (`needs_attention`).
6. **Cron (recommended):** a second service from the same repo/root with start command `python manage.py reconcile_bookings` and a cron schedule of `0 * * * *`. It closes abandoned checkouts and prints bookings that need attention.

At this point (Duffel test token, no Stripe) the whole flow works end to end with fake bookings and no charge: the app shows a "Test booking" banner. Safe to hand to App Review / TestFlight.

## Going live (real money)

1. **Duffel**: switch `DUFFEL_ACCESS_TOKEN` to a `duffel_live_…` token and **fund your Duffel balance**. Orders are paid from the balance; the traveler's Stripe payment is what refills it, so keep a buffer. Add a webhook in Duffel pointing to `https://<domain>/webhooks/duffel/`; copy its secret to `DUFFEL_WEBHOOK_SECRET`.
2. **Stripe**: set `STRIPE_SECRET_KEY` (live) and add a webhook endpoint `https://<domain>/webhooks/stripe/` with events `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`; put its signing secret in `STRIPE_WEBHOOK_SECRET`. Enable Apple Pay in Stripe → Settings → Payment methods.
3. Optional markup: `SERVICE_FEE_PERCENT` / `SERVICE_FEE_FIXED` (added to the airline price, shown to the traveler, non-refundable).
4. **Safety rail:** with a live Duffel token and *no* Stripe key the server refuses to book (`payments_unavailable`), so a half-configured production can never give away tickets.

### Money safety rules built in
- The traveler is charged the price re-read from Duffel at checkout, never a client-supplied number. The app's expected price is only a guard: if it differs, the API answers `price_changed` and books nothing.
- Stripe's paid amount is verified against the booking before ordering; mismatch → refund, no ticket.
- Order creation is claimed with an atomic compare-and-set, so webhook redeliveries can't double-book.
- Airline rejects the order after payment → automatic full refund. A timeout/5xx (outcome unknown) is **not** retried or refunded; it's flagged `needs_attention` for you to check in Duffel (`metadata.booking_id`).
- Personal details (DOB, email, phone, passport) are deleted from the database as soon as the airline order exists. `DELETE /api/v1/account` erases a traveler.

## Local development

```bash
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
export DJANGO_DEBUG=1                 # sqlite, insecure dev key
python manage.py migrate && python manage.py runserver
python manage.py test                 # 77 tests, no network, Duffel/Stripe mocked
```

To try real Duffel sandbox locally: `export DUFFEL_ACCESS_TOKEN=duffel_test_…` (no Stripe key needed).

## Owner checklist before App Store submission
- [ ] `SUPPORT_EMAIL` and `COMPANY_NAME` set; open `/privacy/`, `/terms/`, `/support/` and have counsel review the wording (templates are in `legal/templates/legal/`).
- [ ] Privacy Policy URL (`/privacy/`) and Support URL (`/support/`) entered in App Store Connect.
- [ ] App Privacy answers match the policy: Contact Info (name, email, phone), Sensitive/ID (DOB, passport when required), Purchases, Identifiers (device ID): linked to the user, used for App Functionality, not for tracking.
- [ ] Review notes for Apple: explain bookings use a Duffel *test* environment (or give a live-mode demo), and how to reach each feature.
