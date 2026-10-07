from django.contrib import admin

from .models import Booking, WebhookEvent


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = (
        "id", "status", "booking_reference", "total_amount", "currency",
        "needs_attention", "test_mode", "created_at",
    )
    list_filter = ("status", "needs_attention", "test_mode")
    search_fields = ("id", "booking_reference", "duffel_order_id", "stripe_payment_intent_id", "stripe_session_id")
    readonly_fields = [f.name for f in Booking._meta.fields if f.name not in {"needs_attention", "attention_note"}]
    ordering = ("-needs_attention", "-created_at")

    def has_add_permission(self, request):
        return False


@admin.register(WebhookEvent)
class WebhookEventAdmin(admin.ModelAdmin):
    list_display = ("provider", "event_type", "object_id", "received_at", "processed_at")
    list_filter = ("provider",)
