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

const app = express()
app.use(express.json())

const duffel = new Duffel({
  token: process.env.DUFFEL_ACCESS_TOKEN,
})

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

const port = process.env.PORT || 8080
app.listen(port, () => {
  console.log(`Duffel proxy listening on :${port}`)
})
