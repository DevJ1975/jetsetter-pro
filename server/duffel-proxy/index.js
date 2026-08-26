// JetSetter Pro — Duffel proxy
//
// The iOS app never talks to Duffel directly: a Duffel access token is a
// full-account credential (it can book and cancel real flights), so it must
// live only on the server. This thin proxy holds the token via the
// DUFFEL_ACCESS_TOKEN env var and exposes just the endpoints the app needs.
//
// The app authenticates to THIS proxy with a shared secret (PROXY_APP_KEY),
// sent as `Authorization: Bearer <key>`, so the proxy isn't an open relay to
// your Duffel account.

import express from 'express'
import crypto from 'node:crypto'
import { Duffel } from '@duffel/api'
import Stripe from 'stripe'

const app = express()
app.use(express.json())

const duffel = new Duffel({
  token: process.env.DUFFEL_ACCESS_TOKEN,
})

// Stripe collects the Apple Pay payment. STRIPE_SECRET_KEY is a test key in
// sandbox; Stripe decrypts the Apple Pay token using the Apple Pay Payment
// Processing certificate uploaded to the Stripe account (tied to the Merchant
// ID), so the proxy never handles raw card data.
const stripe = process.env.STRIPE_SECRET_KEY
  ? new Stripe(process.env.STRIPE_SECRET_KEY, { apiVersion: '2024-06-20' })
  : null

const APP_KEY = process.env.PROXY_APP_KEY

// Shared-secret gate for every protected route.
function requireAppKey(req, res, next) {
  if (!APP_KEY) {
    return res.status(500).json({ error: 'PROXY_APP_KEY is not configured on the server' })
  }
  const header = req.get('authorization') || ''
  const token = header.startsWith('Bearer ') ? header.slice(7) : ''
  // Constant-time compare. timingSafeEqual requires equal-length buffers, so
  // guard on length first (a length mismatch is already a non-match anyway).
  const tokenBuf = Buffer.from(token)
  const keyBuf = Buffer.from(APP_KEY)
  if (tokenBuf.length !== keyBuf.length || !crypto.timingSafeEqual(tokenBuf, keyBuf)) {
    return res.status(401).json({ error: 'unauthorized' })
  }
  next()
}

// Maps a Duffel SDK error to an HTTP status the app can reason about.
// Duffel's own 4xx messages are safe to surface (they describe the request),
// but 5xx/unknown errors may leak internal detail — log those server-side and
// return a generic message to the client.
function sendDuffelError(res, e) {
  const status = e?.meta?.status || e?.statusCode || 502
  if (status >= 500) {
    console.error('Duffel request failed:', e)
    return res.status(status).json({ error: 'duffel request failed' })
  }
  res.status(status).json({ error: e?.message || 'duffel request failed' })
}

// Liveness probe (no auth) — for load balancers / uptime checks.
app.get('/health', (_req, res) => res.json({ ok: true }))

// Quickstart smoke test — confirms DUFFEL_ACCESS_TOKEN works end-to-end.
// Mirrors the SDK quickstart: GET a single aircraft by its Duffel ID.
app.get('/duffel/aircraft/:id', requireAppKey, async (req, res) => {
  try {
    const { data } = await duffel.aircraft.get(req.params.id)
    res.json(data)
  } catch (e) {
    sendDuffelError(res, e)
  }
})

// Rebooking eligibility for a Duffel order.
// Consumed by DisruptionResponseEngine.checkRebookingEligibility(tripId:).
app.get('/duffel/orders/:orderId/eligibility', requireAppKey, async (req, res) => {
  try {
    const { data: order } = await duffel.orders.get(req.params.orderId)

    // An order is changeable if the order-level condition allows it, or if any
    // slice can be changed before departure.
    const cond = order.conditions?.change_before_departure
    const sliceChangeable = (order.slices || []).some(
      (s) => s.conditions?.change_before_departure?.allowed
    )
    const changeable = Boolean(cond?.allowed) || sliceChangeable

    res.json({
      changeable,
      order_id: order.id,
      penalty_amount: cond?.penalty_amount ?? null,
      penalty_currency: cond?.penalty_currency ?? null,
    })
  } catch (e) {
    sendDuffelError(res, e)
  }
})

// ── Duffel flight search + booking ──────────────────────────────────────────
//
// Offer ids are ephemeral and priced server-side, so the app never talks to
// Duffel directly: it searches through the proxy, then books an offer id. Order
// creation pays from the org's Duffel Balance (type: 'balance'), so the proxy's
// account must be funded (test-mode balance in sandbox). Docs:
// https://duffel.com/docs/api/orders/create-order

// Search: create an offer request and return its offers (offer ids the app books).
app.post('/duffel/offer-requests', requireAppKey, async (req, res) => {
  try {
    const { slices, passengers, cabin_class } = req.body || {}
    if (!Array.isArray(slices) || !Array.isArray(passengers)) {
      return res.status(400).json({ error: 'slices and passengers are required' })
    }
    // return_offers keeps it a single round-trip for a simple search UI.
    const { data } = await duffel.offerRequests.create({
      slices,
      passengers,
      cabin_class: cabin_class || 'economy',
      return_offers: true,
    })
    res.json({ offer_request_id: data.id, offers: data.offers || [] })
  } catch (e) {
    sendDuffelError(res, e)
  }
})

// Re-fetch a single offer immediately before booking to read the authoritative
// total (list/search offers go stale fast).
app.get('/duffel/offers/:offerId', requireAppKey, async (req, res) => {
  try {
    const { data } = await duffel.offers.get(req.params.offerId, {
      return_available_services: false,
    })
    res.json(data)
  } catch (e) {
    sendDuffelError(res, e)
  }
})

// Create an instant, paid order for an offer. Body: { passengers: [...],
// payment_reference }. The Stripe charge (see /payments/apple-pay/charge) MUST
// succeed first; its PaymentIntent id is passed here as payment_reference and
// stashed in Duffel metadata for reconciliation. The order itself is paid from
// Duffel Balance — never from client-supplied amounts.
app.post('/duffel/offers/:offerId/order', requireAppKey, async (req, res) => {
  try {
    const { passengers, payment_reference } = req.body || {}
    if (!Array.isArray(passengers) || passengers.length === 0) {
      return res.status(400).json({ error: 'passengers are required' })
    }

    // 1. Re-fetch the offer for the authoritative, current total. Never trust a
    //    client-supplied price — a stale/mismatched amount fails validation.
    const { data: offer } = await duffel.offers.get(req.params.offerId)

    // 2. Create the order, paying the exact freshly-read total from Balance.
    const { data: order } = await duffel.orders.create({
      type: 'instant',
      selected_offers: [offer.id],
      payments: [{
        type: 'balance',
        amount: offer.total_amount,      // decimal string, must match offer
        currency: offer.total_currency,
      }],
      passengers,
      metadata: payment_reference ? { payment_reference } : undefined,
    })

    res.json({
      order_id: order.id,                    // ord_… — persist this
      booking_reference: order.booking_reference,
      total_amount: order.total_amount,
      total_currency: order.total_currency,
    })
  } catch (e) {
    // NOTE: a 5xx here does NOT guarantee the order was not created at the
    // airline — do not auto-retry; reconcile via webhook / order lookup.
    sendDuffelError(res, e)
  }
})

// Expedia Rapid (EAN) signature auth header, computed server-side so the shared
// secret never ships inside the app. Rapid Lodging authenticates with
//   Authorization: EAN APIKey=<key>,Signature=<sig>,timestamp=<unix seconds>
// where <sig> = lowercase-hex SHA-512(apiKey + sharedSecret + timestamp). The
// app calls this (with the PROXY_APP_KEY bearer) and forwards the returned
// header on its own Rapid requests. Same treatment as the Duffel token.
function expediaAuthHeader() {
  const apiKey = process.env.EXPEDIA_CLIENT_ID
  const secret = process.env.EXPEDIA_CLIENT_SECRET
  if (!apiKey || !secret) return null
  const timestamp = Math.floor(Date.now() / 1000).toString()
  const signature = crypto.createHash('sha512').update(apiKey + secret + timestamp).digest('hex')
  return `EAN APIKey=${apiKey},Signature=${signature},timestamp=${timestamp}`
}

app.get('/expedia/auth-header', requireAppKey, (_req, res) => {
  const authorization = expediaAuthHeader()
  if (!authorization) {
    return res.status(500).json({ error: 'Expedia credentials are not configured on the server' })
  }
  res.json({ authorization })
})

// ── Expedia Rapid hotel booking (SCAFFOLD — gated follow-on) ─────────────────
//
// Real Rapid booking is NOT enabled by default. It requires: (1) an approved
// Rapid *booking* partner agreement (the search keys alone don't grant it),
// (2) following the tokenized price_check → book link (never hand-built URLs),
// and (3) PSD2/SCA 3DS 2.0 via Rapid's JS 3DS Connector for EEA/JP cards — which
// is a web-checkout pattern, not a native one. Until EXPEDIA_BOOKING_ENABLED is
// set AND that flow is built, this returns 501 so no half-working charge path
// ships. Body would carry: { book_link, affiliate_reference_id, rooms, payments }.
// Docs: https://developers.expediagroup.com/rapid/lodging/booking
app.post('/expedia/properties/:propertyId/book', requireAppKey, async (req, res) => {
  if (process.env.EXPEDIA_BOOKING_ENABLED !== 'true') {
    return res.status(501).json({
      error: 'Expedia booking is not enabled — requires a Rapid booking partner agreement + 3DS/SCA integration.',
    })
  }
  const authorization = expediaAuthHeader()
  if (!authorization) {
    return res.status(500).json({ error: 'Expedia credentials are not configured on the server' })
  }
  try {
    const { book_link, affiliate_reference_id, rooms, payments } = req.body || {}
    if (!book_link || !affiliate_reference_id) {
      return res.status(400).json({ error: 'book_link and affiliate_reference_id are required' })
    }
    // Follow the tokenized book link returned by Price Check — do NOT construct it.
    const upstream = await fetch(book_link, {
      method: 'POST',
      headers: { Authorization: authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ affiliate_reference_id, rooms, payments }),
    })
    const data = await upstream.json().catch(() => ({}))
    res.status(upstream.status).json(data)
  } catch (e) {
    console.error('Expedia book failed:', e?.message || e)
    res.status(502).json({ error: 'expedia booking request failed' })
  }
})

// ── Apple Pay → Stripe charge ────────────────────────────────────────────────
//
// The app forwards the Apple Pay PKPaymentToken.paymentData (base64) plus the
// server-quoted amount/currency. We create a Stripe token from the Apple Pay
// payload, wrap it in a PaymentMethod, and create+confirm a PaymentIntent in one
// call. The returned PaymentIntent id (pi_…) is the payment reference the app
// then passes to the order-creation route — so we only ever book AFTER the
// charge clears. Amount is trusted from the caller here for simplicity, but in
// production it MUST be re-derived server-side from the quoted offer/rate.
// Docs: https://docs.stripe.com/apple-pay
app.post('/payments/apple-pay/charge', requireAppKey, async (req, res) => {
  if (!stripe) {
    return res.status(500).json({ error: 'Stripe is not configured on the server' })
  }
  try {
    const { payment_data, amount, currency } = req.body || {}
    if (!payment_data || !Number.isInteger(amount) || !currency) {
      return res.status(400).json({ error: 'payment_data, integer amount (minor units), and currency are required' })
    }

    // Apple Pay token payload (decoded from the base64 the app forwarded) → a
    // Stripe token. Stripe decrypts it with the uploaded Apple Pay certificate.
    const applePayPayload = Buffer.from(payment_data, 'base64').toString('utf8')
    const token = await stripe.tokens.create({ pk_token: applePayPayload })
    const paymentMethod = await stripe.paymentMethods.create({
      type: 'card',
      card: { token: token.id },
    })

    const intent = await stripe.paymentIntents.create({
      amount,
      currency: String(currency).toLowerCase(),
      payment_method: paymentMethod.id,
      confirm: true,
      confirmation_method: 'manual',
      // The order is created by a separate call only after this succeeds, so no
      // redirect/next-action handoff is needed here.
      automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
    })

    res.json({ payment_reference: intent.id, status: intent.status })
  } catch (e) {
    // Never surface raw card/processor internals; log server-side.
    console.error('Apple Pay charge failed:', e?.message || e)
    res.status(e?.statusCode || 502).json({ error: e?.raw?.message || 'payment failed' })
  }
})

const port = process.env.PORT || 8080
app.listen(port, () => {
  console.log(`Duffel proxy listening on :${port}`)
})
