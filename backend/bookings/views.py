import hashlib
import hmac
import json
import logging

import stripe
from django.conf import settings
from django.db import connection
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes, throttle_classes
from rest_framework.generics import get_object_or_404
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle

from . import payments, services
from .models import Booking, WebhookEvent
from .serializers import CancelConfirmSerializer, CheckoutSerializer, SearchSerializer

log = logging.getLogger(__name__)


class SearchThrottle(UserRateThrottle):
    scope = "search"


class CheckoutThrottle(UserRateThrottle):
    scope = "checkout"


class ReadThrottle(UserRateThrottle):
    scope = "read"


def health(_request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
    except Exception:  # noqa: BLE001 - any failure means "not healthy"
        log.exception("Health check failed")
        return JsonResponse({"status": "unhealthy"}, status=503)
    return JsonResponse({"status": "ok"})


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def public_config(_request):
    from .duffel import client as duffel

    base = settings.PUBLIC_BASE_URL
    return Response({
        "flights_enabled": duffel.configured and (settings.PAYMENTS_ENABLED or settings.ALLOW_UNPAID_TEST_BOOKINGS),
        "payments_enabled": settings.PAYMENTS_ENABLED,
        "test_mode": settings.FLIGHTS_TEST_MODE,
        "support_email": settings.SUPPORT_EMAIL or None,
        "privacy_url": f"{base}/privacy/" if base else None,
        "terms_url": f"{base}/terms/" if base else None,
        "support_url": f"{base}/support/" if base else None,
    })


@api_view(["POST"])
@throttle_classes([SearchThrottle])
def flight_search(request):
    serializer = SearchSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    return Response(services.search_flights(serializer.validated_data))


@api_view(["GET"])
@throttle_classes([SearchThrottle])
def flight_offer(_request, offer_id):
    return Response(services.get_offer(offer_id))


@api_view(["POST"])
@throttle_classes([CheckoutThrottle])
def flight_checkout(request, offer_id):
    serializer = CheckoutSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    booking, checkout_url = services.start_checkout(request.user, offer_id, serializer.validated_data)
    return Response(
        {"booking": booking.to_api(), "checkout_url": checkout_url}, status=status.HTTP_201_CREATED,
    )


@api_view(["GET"])
@throttle_classes([ReadThrottle])
def booking_list(request):
    bookings = Booking.objects.filter(user=request.user)
    return Response({"bookings": [b.to_api() for b in bookings]})


def _own_booking(request, booking_id) -> Booking:
    return get_object_or_404(Booking.objects.filter(user=request.user), pk=booking_id)


@api_view(["GET"])
@throttle_classes([ReadThrottle])
def booking_detail(request, booking_id):
    booking = _own_booking(request, booking_id)
    if request.query_params.get("refresh", "").lower() in {"1", "true", "yes"}:
        booking = services.refresh_booking(booking)
    return Response(booking.to_api())


@api_view(["POST"])
@throttle_classes([CheckoutThrottle])
def cancel_quote(request, booking_id):
    return Response(services.quote_cancellation(_own_booking(request, booking_id)))


@api_view(["POST"])
@throttle_classes([CheckoutThrottle])
def cancel_confirm(request, booking_id):
    booking = _own_booking(request, booking_id)
    serializer = CancelConfirmSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    result = services.confirm_cancellation(booking.pk, serializer.validated_data["cancellation_id"])
    return Response(result.to_api())


# ── Webhooks ─────────────────────────────────────────────────────────────────
def _begin_event(provider: str, event_id: str, event_type: str, object_id: str):
    """Returns the WebhookEvent to process, or None if it was already handled."""
    event, _created = WebhookEvent.objects.get_or_create(
        provider=provider, event_id=event_id,
        defaults={"event_type": event_type[:128], "object_id": object_id[:128]},
    )
    return None if event.processed_at else event


@csrf_exempt
@require_POST
def stripe_webhook(request):
    if not settings.STRIPE_WEBHOOK_SECRET:
        return HttpResponse("Stripe webhook secret not configured", status=503)
    try:
        event = payments.construct_event(request.body, request.META.get("HTTP_STRIPE_SIGNATURE", ""))
    except (ValueError, stripe.SignatureVerificationError):
        return HttpResponse("Invalid signature", status=400)

    event = event.to_dict() if hasattr(event, "to_dict") else event
    record = _begin_event("stripe", event["id"], event["type"], (event["data"]["object"].get("id") or ""))
    if record is None:
        return HttpResponse("ok")
    try:
        services.handle_stripe_event(event)
    except Exception:  # noqa: BLE001
        log.exception("Stripe event %s failed", event["id"])
        return HttpResponse("handler error", status=500)  # Stripe retries
    record.processed_at = timezone.now()
    record.save(update_fields=["processed_at"])
    return HttpResponse("ok")


def verify_duffel_signature(body: bytes, header: str, secret: str) -> bool:
    """X-Duffel-Signature: t=<unix>,v1=<hex hmac-sha256 of "<t>.<body>">."""
    parts = dict(item.split("=", 1) for item in header.split(",") if "=" in item)
    timestamp, signature = parts.get("t"), parts.get("v1")
    if not timestamp or not signature:
        return False
    expected = hmac.new(secret.encode(), f"{timestamp}.".encode() + body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


@csrf_exempt
@require_POST
def duffel_webhook(request):
    if not settings.DUFFEL_WEBHOOK_SECRET:
        return HttpResponse("Duffel webhook secret not configured", status=503)
    if not verify_duffel_signature(request.body, request.META.get("HTTP_X_DUFFEL_SIGNATURE", ""), settings.DUFFEL_WEBHOOK_SECRET):
        return HttpResponse("Invalid signature", status=400)
    try:
        event = json.loads(request.body)
    except ValueError:
        return HttpResponse("Bad JSON", status=400)

    object_id = ((event.get("data") or {}).get("object") or {}).get("id") or ""
    record = _begin_event("duffel", str(event.get("id") or f"{event.get('type')}-{object_id}-{event.get('created_at')}"),
                          str(event.get("type", "")), object_id)
    if record is None:
        return HttpResponse("ok")
    try:
        services.handle_duffel_event(event)
    except Exception:  # noqa: BLE001
        log.exception("Duffel event failed")
        return HttpResponse("handler error", status=500)
    record.processed_at = timezone.now()
    record.save(update_fields=["processed_at"])
    return HttpResponse("ok")


def checkout_return(request):
    """Where Stripe sends the traveler afterwards. The app also watches the
    booking, so this page only has to hand the traveler back to it."""
    result = request.GET.get("result", "success")
    booking_id = request.GET.get("booking", "")
    try:
        import uuid
        booking_id = str(uuid.UUID(booking_id))
    except ValueError:
        booking_id = ""
    deep_link = f"{settings.APP_URL_SCHEME}://booking/{booking_id}" if booking_id else f"{settings.APP_URL_SCHEME}://bookings"
    return render(request, "checkout_return.html", {"result": result, "deep_link": deep_link})
