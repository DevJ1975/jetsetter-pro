"""Booking lifecycle.

    start_checkout ─▶ pending_payment ─(Stripe webhook: paid)─▶ processing ─▶ confirmed
                           │                                        │
                           └─▶ expired                              └─▶ failed (+ automatic refund)

Rules this module exists to enforce:
  * the traveler is only ever charged the amount we re-read from Duffel;
  * an airline order is created exactly once per booking (compare-and-set);
  * a charge that can't become a ticket is refunded, automatically;
  * when we genuinely can't tell whether the airline order exists (timeout, 5xx)
    we never retry or refund blindly: the booking is flagged for a human.
"""
import logging
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from . import normalize, payments, pricing
from .duffel import DuffelError, client as duffel
from .errors import APIError
from .models import Booking

log = logging.getLogger(__name__)

TERMINAL = {Booking.Status.CONFIRMED, Booking.Status.FAILED, Booking.Status.CANCELLED, Booking.Status.EXPIRED}


# ── Error mapping ────────────────────────────────────────────────────────────
def require_flights():
    if not duffel.configured:
        raise APIError("flights_unavailable", "Flight booking isn't available right now.", 503)


def upstream_error(exc: DuffelError) -> APIError:
    if exc.offer_gone:
        return APIError("offer_expired", "That fare is no longer available. Please search again.", 409)
    if exc.definite:
        return APIError("rejected", exc.message, 422)
    return APIError("upstream_error", "The airline service is having trouble. Please try again.", 502)


# ── Search ───────────────────────────────────────────────────────────────────
def search_flights(data: dict) -> dict:
    require_flights()
    slices = [
        {"origin": s["origin"].upper(), "destination": s["destination"].upper(),
         "departure_date": s["departure_date"].isoformat()}
        for s in data["slices"]
    ]
    pax = data["passengers"]
    passengers = (
        [{"type": "adult"}] * pax["adults"]
        + [{"type": "child"}] * pax["children"]
        + [{"type": "infant_without_seat"}] * pax["infants"]
    )
    try:
        request = duffel.create_offer_request(slices, passengers, data["cabin_class"])
    except DuffelError as exc:
        raise upstream_error(exc) from exc

    offers = []
    for raw in request.get("offers") or []:
        try:
            total, currency = normalize.duffel_total(raw)
            fee = pricing.service_fee(total, currency)
            offers.append((total + fee, normalize.offer(raw, fee)))
        except (ValueError, KeyError):
            log.warning("Skipping unreadable offer %s", raw.get("id"))
    offers.sort(key=lambda pair: pair[0])
    return {"search_id": request.get("id"), "offers": [o for _, o in offers[: settings.MAX_SEARCH_OFFERS]]}


def get_offer(offer_id: str) -> dict:
    require_flights()
    try:
        raw = duffel.get_offer(offer_id)
    except DuffelError as exc:
        raise upstream_error(exc) from exc
    total, currency = normalize.duffel_total(raw)
    return normalize.offer(raw, pricing.service_fee(total, currency))


# ── Checkout ─────────────────────────────────────────────────────────────────
_PASSENGER_KEYS = (
    "id", "title", "given_name", "family_name", "born_on", "gender", "email",
    "phone_number", "identity_documents", "infant_passenger_id",
)


def _duffel_passenger(p: dict) -> dict:
    out = {k: p[k] for k in _PASSENGER_KEYS if p.get(k) not in (None, "", [])}
    out["born_on"] = p["born_on"].isoformat() if hasattr(p["born_on"], "isoformat") else p["born_on"]
    if out.get("identity_documents"):
        out["identity_documents"] = [
            {**d, "expires_on": d["expires_on"].isoformat() if hasattr(d["expires_on"], "isoformat") else d["expires_on"],
             "issuing_country_code": d["issuing_country_code"].upper()}
            for d in out["identity_documents"]
        ]
    return out


def start_checkout(user, offer_id: str, data: dict):
    """Returns (booking, checkout_url or None)."""
    require_flights()
    if not settings.PAYMENTS_ENABLED and not settings.ALLOW_UNPAID_TEST_BOOKINGS:
        raise APIError("payments_unavailable", "Payments aren't available right now.", 503)

    try:
        raw = duffel.get_offer(offer_id)
    except DuffelError as exc:
        raise upstream_error(exc) from exc

    duffel_amount, currency = normalize.duffel_total(raw)
    if settings.PAYMENTS_ENABLED and not pricing.card_checkout_supported(currency):
        raise APIError("currency_unsupported", f"Card payment in {currency} isn't supported yet.", 409)
    fee = pricing.service_fee(duffel_amount, currency)
    total = duffel_amount + fee
    fresh_offer = normalize.offer(raw, fee)

    expected = data.get("expected_total_amount")
    expected_cur = (data.get("expected_total_currency") or currency).upper()
    if expected is not None and (
        expected_cur != currency or pricing.quantize(expected, currency) != pricing.quantize(total, currency)
    ):
        raise APIError(
            "price_changed", "The fare changed. Please review the new price.", 409, offer=fresh_offer,
        )

    given = [p["id"] for p in data["passengers"]]
    wanted = {p["id"] for p in raw.get("passengers") or []}
    if len(set(given)) != len(given) or set(given) != wanted:
        raise APIError(
            "validation_error", "Enter details for every traveler on this fare.", 400,
            fields={"passengers": ["Traveler ids must match the fare."]},
        )
    if raw.get("passenger_identity_documents_required") and any(not p.get("identity_documents") for p in data["passengers"]):
        raise APIError(
            "validation_error", "This airline needs passport details for every traveler.", 400,
            fields={"passengers": ["identity_documents required"]},
        )

    passengers = [_duffel_passenger(p) for p in data["passengers"]]
    booking = Booking.objects.create(
        user=user,
        offer_id=offer_id,
        test_mode=settings.FLIGHTS_TEST_MODE,
        total_amount=total,
        duffel_amount=duffel_amount,
        fee_amount=fee,
        currency=currency,
        airline=fresh_offer["airline"],
        slices=fresh_offer["slices"],
        conditions=fresh_offer["conditions"],
        baggage=fresh_offer["baggage"],
        first_departure=normalize.first_departure(fresh_offer["slices"]),
        passengers=[
            {"id": p["id"], "type": None, "title": p.get("title"), "given_name": p["given_name"],
             "family_name": p["family_name"], "ticket_number": None, "seat": None}
            for p in passengers
        ],
        passenger_input={"passengers": passengers},
        status_detail="Waiting for payment",
    )

    if not settings.PAYMENTS_ENABLED:
        # Duffel sandbox without Stripe: nothing is charged, so go straight to ordering.
        return fulfil_booking(booking.id), None

    route = " → ".join(
        [fresh_offer["slices"][0]["origin"]["iata_code"] or "", fresh_offer["slices"][-1]["destination"]["iata_code"] or ""]
    ) if fresh_offer["slices"] else "Flight"
    description = f"{fresh_offer['airline'].get('name') or 'Flight'} · {route}"
    try:
        session = payments.create_checkout_session(booking, description, customer_email=passengers[0]["email"])
    except payments.PaymentError as exc:
        booking.status = Booking.Status.FAILED
        booking.status_detail = "Payment couldn't be started"
        booking.passenger_input = {}
        booking.save(update_fields=["status", "status_detail", "passenger_input", "updated_at"])
        raise APIError("upstream_error", str(exc), 502) from exc
    booking.stripe_session_id = session.id
    booking.save(update_fields=["stripe_session_id", "updated_at"])
    return booking, session.url


# ── Fulfilment ───────────────────────────────────────────────────────────────
def _scrub(booking: Booking):
    booking.passenger_input = {}


def _flag(booking: Booking, note: str):
    booking.needs_attention = True
    booking.attention_note = note[:500]
    log.error("Booking %s needs attention: %s", booking.id, note)


def fail_and_refund(booking: Booking, reason: str):
    """Mark failed and return any money taken. Safe to call only when the
    airline order is known not to exist."""
    booking.status = Booking.Status.FAILED
    _scrub(booking)
    if booking.stripe_payment_intent_id:
        try:
            refund = payments.refund(
                booking.stripe_payment_intent_id, booking.total_amount, booking.currency,
                str(booking.id), "fulfilment_failed",
            )
            booking.refund_amount = booking.total_amount
            booking.refund_id = refund.id
            booking.refund_status = getattr(refund, "status", "") or "pending"
            booking.status_detail = f"{reason} Your payment has been refunded."
        except payments.PaymentError:
            booking.status_detail = f"{reason} We're refunding your payment; contact support if it doesn't arrive."
            _flag(booking, "Fulfilment failed AND the automatic refund failed. Refund manually in Stripe.")
    else:
        booking.status_detail = f"{reason} You were not charged."
    booking.save()
    return booking


def fulfil_booking(booking_id, payment_intent_id: str = "") -> Booking:
    """Turn a paid (or test-mode) booking into an airline order. Idempotent."""
    claimed = Booking.objects.filter(pk=booking_id, status=Booking.Status.PENDING_PAYMENT).update(
        status=Booking.Status.PROCESSING,
        status_detail="Confirming with the airline",
        stripe_payment_intent_id=payment_intent_id or "",
        updated_at=timezone.now(),
    )
    booking = Booking.objects.get(pk=booking_id)
    if not claimed:
        return booking  # someone else owns it, or it's already settled

    ordering_started = False
    try:
        raw_offer = duffel.get_offer(booking.offer_id)
        fresh_total, currency = normalize.duffel_total(raw_offer)
        if currency != booking.currency or pricing.quantize(fresh_total, currency) != pricing.quantize(booking.duffel_amount, currency):
            return fail_and_refund(booking, "The fare changed while you were paying.")
        ordering_started = True
        order = duffel.create_order(
            booking.offer_id,
            booking.passenger_input.get("passengers", []),
            pricing.fmt(booking.duffel_amount, currency),
            currency,
            {"booking_id": str(booking.id)},
        )
    except DuffelError as exc:
        if exc.definite or not ordering_started:
            if exc.code in {"insufficient_balance", "insufficient_funds"}:
                _flag(booking, "Duffel balance is too low to pay for orders. Top it up.")
            return fail_and_refund(booking, "The airline couldn't confirm this fare." if not exc.offer_gone else "That fare sold out.")
        # We don't know whether the airline created the order. Do not retry (it
        # could double-book) and do not refund (it could be ticketed).
        booking.status_detail = "We're still confirming this with the airline. You'll see it here shortly."
        _flag(booking, f"Order creation outcome unknown ({exc.message}). Check Duffel for metadata.booking_id={booking.id}.")
        booking.save()
        return booking

    apply_order(booking, order)
    return booking


def apply_order(booking: Booking, order: dict):
    for field, value in normalize.order_fields(order).items():
        setattr(booking, field, value)
    booking.status = Booking.Status.CONFIRMED
    booking.status_detail = "Ticketed" if any(d.get("type") == "electronic_ticket" for d in order.get("documents") or []) else "Confirmed"
    booking.needs_attention = False
    booking.attention_note = ""
    _scrub(booking)
    booking.save()


def refresh_booking(booking: Booking) -> Booking:
    """Re-read the airline order (schedule changes, tickets, baggage)."""
    if not booking.duffel_order_id or booking.status not in {Booking.Status.CONFIRMED, Booking.Status.CANCELLED}:
        return booking
    try:
        order = duffel.get_order(booking.duffel_order_id)
    except DuffelError as exc:
        log.warning("Refresh of booking %s failed: %s", booking.id, exc.message)
        return booking  # serve what we have
    for field, value in normalize.order_fields(order).items():
        setattr(booking, field, value)
    if order.get("cancelled_at") and booking.status == Booking.Status.CONFIRMED:
        booking.status = Booking.Status.CANCELLED
        booking.status_detail = "Cancelled"
    booking.save()
    return booking


# ── Cancellation ─────────────────────────────────────────────────────────────
def _require_cancellable(booking: Booking):
    if booking.status != Booking.Status.CONFIRMED or not booking.duffel_order_id:
        raise APIError("not_cancellable", "Only a confirmed booking can be cancelled.", 409)


def quote_cancellation(booking: Booking) -> dict:
    _require_cancellable(booking)
    try:
        q = duffel.create_cancellation(booking.duffel_order_id)
    except DuffelError as exc:
        if exc.definite:
            raise APIError("not_cancellable", exc.message or "This booking can't be cancelled online.", 409) from exc
        raise upstream_error(exc) from exc
    booking.cancellation_id = q["id"]
    booking.save(update_fields=["cancellation_id", "updated_at"])
    cur = (q.get("refund_currency") or booking.currency).upper()
    return {
        "cancellation_id": q["id"],
        "refund_amount": pricing.fmt(q.get("refund_amount") or "0", cur),
        "refund_currency": cur,
        "expires_at": q.get("expires_at"),
    }


def confirm_cancellation(booking_id, cancellation_id: str) -> Booking:
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=booking_id)
        _require_cancellable(booking)
        if not booking.cancellation_id or booking.cancellation_id != cancellation_id:
            raise APIError("invalid_state", "Request a new cancellation quote first.", 409)
        try:
            result = duffel.confirm_cancellation(cancellation_id)
        except DuffelError as exc:
            if exc.definite:
                raise APIError("not_cancellable", exc.message or "The quote has expired. Request a new one.", 409) from exc
            raise upstream_error(exc) from exc

        booking.status = Booking.Status.CANCELLED
        booking.status_detail = "Cancelled"
        refund_cur = (result.get("refund_currency") or booking.currency).upper()
        refund_amt = Decimal(str(result.get("refund_amount") or "0"))
        if refund_amt > 0 and booking.stripe_payment_intent_id:
            if refund_cur != booking.currency:
                _flag(booking, "Cancellation refund is in a different currency than the charge. Refund manually.")
            else:
                refund_amt = min(refund_amt, booking.total_amount)
                try:
                    refund = payments.refund(
                        booking.stripe_payment_intent_id, refund_amt, booking.currency, str(booking.id), "cancellation",
                    )
                    booking.refund_amount = refund_amt
                    booking.refund_id = refund.id
                    booking.refund_status = getattr(refund, "status", "") or "pending"
                except payments.PaymentError:
                    booking.refund_amount = refund_amt
                    booking.refund_status = "failed"
                    _flag(booking, "Cancelled with the airline but the card refund failed. Refund manually in Stripe.")
        booking.save()
    return booking


# ── Webhooks ─────────────────────────────────────────────────────────────────
def handle_stripe_event(event: dict):
    kind = event["type"]
    obj = event["data"]["object"]
    booking_id = (obj.get("metadata") or {}).get("booking_id") or obj.get("client_reference_id")
    if not kind.startswith("checkout.session.") or not booking_id:
        return
    try:
        booking = Booking.objects.get(pk=booking_id)
    except (Booking.DoesNotExist, ValueError):
        log.warning("Stripe event %s for unknown booking %s", event.get("id"), booking_id)
        return

    if kind in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        if obj.get("payment_status") != "paid":
            return  # delayed method still pending; async_payment_succeeded follows
        payment_intent = obj.get("payment_intent") or ""
        expected = pricing.to_minor_units(booking.total_amount, booking.currency)
        if obj.get("amount_total") != expected or (obj.get("currency") or "").upper() != booking.currency:
            booking.stripe_payment_intent_id = payment_intent
            _flag(booking, "Stripe amount didn't match the booking. Refunded, not ticketed.")
            fail_and_refund(booking, "The payment amount didn't match the fare.")
            return
        if booking.status in {Booking.Status.EXPIRED, Booking.Status.FAILED, Booking.Status.CANCELLED}:
            # Paid after we gave up on it: give the money back.
            booking.stripe_payment_intent_id = payment_intent
            fail_and_refund(booking, "This booking had already closed.")
            return
        fulfil_booking(booking.id, payment_intent)
    elif kind == "checkout.session.expired":
        Booking.objects.filter(pk=booking.pk, status=Booking.Status.PENDING_PAYMENT).update(
            status=Booking.Status.EXPIRED, status_detail="Payment wasn't completed", passenger_input={},
            updated_at=timezone.now(),
        )
    elif kind == "checkout.session.async_payment_failed":
        Booking.objects.filter(pk=booking.pk, status=Booking.Status.PENDING_PAYMENT).update(
            status=Booking.Status.FAILED, status_detail="The payment didn't go through. You were not charged.",
            passenger_input={}, updated_at=timezone.now(),
        )


def handle_duffel_event(event: dict):
    """Any order event is a prompt to re-read the order: the API is the source
    of truth, so we don't depend on event-type names."""
    if not str(event.get("type", "")).startswith("order."):
        return
    obj = (event.get("data") or {}).get("object") or {}
    order_id = obj.get("id") or obj.get("order_id")
    if not order_id:
        return
    booking = Booking.objects.filter(duffel_order_id=order_id).first()
    if booking:
        refresh_booking(booking)
        if booking.has_airline_changes and not booking.needs_attention:
            _flag(booking, "The airline changed this itinerary. Review it in Duffel.")
            booking.save(update_fields=["needs_attention", "attention_note", "updated_at"])


# ── Housekeeping / erasure ───────────────────────────────────────────────────
def anonymise_device_bookings(user):
    Booking.objects.filter(user=user).update(user=None, passenger_input={}, passengers=[])


def expire_stale_bookings(now=None) -> int:
    cutoff = (now or timezone.now()) - timedelta(minutes=settings.STRIPE_CHECKOUT_MINUTES + 60)
    return Booking.objects.filter(status=Booking.Status.PENDING_PAYMENT, created_at__lt=cutoff).update(
        status=Booking.Status.EXPIRED, status_detail="Payment wasn't completed", passenger_input={},
    )
