import uuid

from django.conf import settings
from django.db import models

from . import pricing


class Booking(models.Model):
    class Status(models.TextChoices):
        PENDING_PAYMENT = "pending_payment"
        PROCESSING = "processing"
        CONFIRMED = "confirmed"
        FAILED = "failed"
        CANCELLED = "cancelled"
        EXPIRED = "expired"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # SET_NULL: erasing a traveler keeps the financial record, minus the person.
    user = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="bookings")
    kind = models.CharField(max_length=16, default="flight")
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING_PAYMENT, db_index=True)
    status_detail = models.CharField(max_length=255, blank=True)
    test_mode = models.BooleanField(default=False)

    offer_id = models.CharField(max_length=64)
    duffel_order_id = models.CharField(max_length=64, unique=True, null=True, blank=True)
    booking_reference = models.CharField(max_length=16, blank=True)

    # What the traveler paid, what Duffel charged us, and our fee between them.
    total_amount = models.DecimalField(max_digits=14, decimal_places=3)
    duffel_amount = models.DecimalField(max_digits=14, decimal_places=3)
    fee_amount = models.DecimalField(max_digits=14, decimal_places=3, default=0)
    currency = models.CharField(max_length=3)

    # Display data (no contact details or birth dates).
    airline = models.JSONField(default=dict, blank=True)
    slices = models.JSONField(default=list, blank=True)
    conditions = models.JSONField(default=dict, blank=True)
    baggage = models.JSONField(default=list, blank=True)
    passengers = models.JSONField(default=list, blank=True)
    first_departure = models.DateTimeField(null=True, blank=True)
    has_airline_changes = models.BooleanField(default=False)

    # Full traveler details exist only until the airline order is placed, then
    # they are wiped (see services.scrub_passenger_input).
    passenger_input = models.JSONField(default=dict, blank=True)

    stripe_session_id = models.CharField(max_length=128, blank=True, db_index=True)
    stripe_payment_intent_id = models.CharField(max_length=128, blank=True)
    refund_amount = models.DecimalField(max_digits=14, decimal_places=3, null=True, blank=True)
    refund_status = models.CharField(max_length=32, blank=True)
    refund_id = models.CharField(max_length=128, blank=True)
    cancellation_id = models.CharField(max_length=64, blank=True)

    # Set when a human has to look: a charge we couldn't refund, an order whose
    # outcome we couldn't confirm, an empty Duffel balance. Shown in the admin.
    needs_attention = models.BooleanField(default=False, db_index=True)
    attention_note = models.CharField(max_length=500, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.id} {self.status} {self.booking_reference}"

    # ── Wire format ──────────────────────────────────────────────────────────
    def to_api(self) -> dict:
        cur = self.currency
        refund = None
        if self.refund_amount is not None:
            refund = {
                "amount": pricing.fmt(self.refund_amount, cur),
                "currency": cur,
                "status": self.refund_status or "pending",
            }
        return {
            "id": str(self.id),
            "kind": self.kind,
            "status": self.status,
            "status_detail": self.status_detail,
            "booking_reference": self.booking_reference,
            "duffel_order_id": self.duffel_order_id,
            "total_amount": pricing.fmt(self.total_amount, cur),
            "total_currency": cur,
            "fee_amount": pricing.fmt(self.fee_amount, cur),
            "test_mode": self.test_mode,
            "airline": self.airline,
            "slices": self.slices,
            "passengers": self.passengers,
            "baggage": self.baggage,
            "conditions": self.conditions,
            "has_airline_changes": self.has_airline_changes,
            "refund": refund,
            "created_at": self.created_at.isoformat().replace("+00:00", "Z"),
            "updated_at": self.updated_at.isoformat().replace("+00:00", "Z"),
        }


class WebhookEvent(models.Model):
    """Dedupes webhook deliveries; both Stripe and Duffel retry."""

    provider = models.CharField(max_length=16)
    event_id = models.CharField(max_length=128)
    event_type = models.CharField(max_length=128, blank=True)
    object_id = models.CharField(max_length=128, blank=True)
    received_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["provider", "event_id"], name="uniq_webhook_event")]
