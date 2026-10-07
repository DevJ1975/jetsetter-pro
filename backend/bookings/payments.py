"""Stripe, used only to take the traveler's payment and to refund it.

Hosted Checkout means no card data and no Stripe SDK in the app: the app opens
a URL, Stripe shows Apple Pay or a card form, and our webhook hears the result.
"""
import logging
from datetime import timedelta

import stripe
from django.conf import settings
from django.utils import timezone

from . import pricing

log = logging.getLogger(__name__)


class PaymentError(Exception):
    pass


def _configure():
    stripe.api_key = settings.STRIPE_SECRET_KEY


def create_checkout_session(booking, description: str, customer_email: str = ""):
    """A one-payment Checkout Session for exactly `booking.total_amount`."""
    _configure()
    base = settings.PUBLIC_BASE_URL
    expires = int((timezone.now() + timedelta(minutes=settings.STRIPE_CHECKOUT_MINUTES)).timestamp())
    try:
        return stripe.checkout.Session.create(
            mode="payment",
            line_items=[{
                "quantity": 1,
                "price_data": {
                    "currency": booking.currency.lower(),
                    "unit_amount": pricing.to_minor_units(booking.total_amount, booking.currency),
                    "product_data": {"name": description},
                },
            }],
            client_reference_id=str(booking.id),
            metadata={"booking_id": str(booking.id)},
            payment_intent_data={"metadata": {"booking_id": str(booking.id)}},
            success_url=f"{base}/checkout/return/?booking={booking.id}&result=success",
            cancel_url=f"{base}/checkout/return/?booking={booking.id}&result=cancelled",
            expires_at=expires,
            **({"customer_email": customer_email} if customer_email else {}),
            idempotency_key=f"checkout-{booking.id}",
        )
    except stripe.StripeError as exc:
        log.error("Stripe checkout session failed: %s", exc)
        raise PaymentError("We couldn't start the payment. Please try again.") from exc


def refund(payment_intent_id: str, amount, currency: str, booking_id: str, reason: str):
    """Refund `amount` (Decimal) against a payment. Idempotent per booking+reason."""
    _configure()
    try:
        return stripe.Refund.create(
            payment_intent=payment_intent_id,
            amount=pricing.to_minor_units(amount, currency),
            metadata={"booking_id": booking_id, "reason": reason},
            idempotency_key=f"refund-{booking_id}-{reason}",
        )
    except stripe.StripeError as exc:
        log.error("Stripe refund failed for booking %s: %s", booking_id, exc)
        raise PaymentError("The refund couldn't be issued.") from exc


def construct_event(payload: bytes, signature: str):
    _configure()
    return stripe.Webhook.construct_event(payload, signature, settings.STRIPE_WEBHOOK_SECRET)
