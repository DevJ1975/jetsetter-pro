import hashlib
import hmac
import json
import time
from types import SimpleNamespace
from unittest import mock

import stripe
from django.test import override_settings
from rest_framework.test import APIClient

from bookings import payments
from bookings.duffel import DuffelError, client
from bookings.models import Booking, WebhookEvent

from . import fixtures
from .base import DUFFEL_ON, NO_STRIPE, STRIPE_ON, APITestCase

BODY = {"expected_total_amount": "245.30", "expected_total_currency": "USD", "passengers": [fixtures.traveler()]}
URL = "/api/v1/flights/offers/off_1/checkout"


@override_settings(**DUFFEL_ON, **NO_STRIPE)
class TestModeCheckout(APITestCase):
    def post(self, body=None):
        return self.client.post(URL, body or BODY, format="json")

    def test_books_without_payment_in_test_mode(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()) as create:
            resp = self.post()
        self.assertEqual(resp.status_code, 201, resp.content)
        data = resp.json()
        self.assertIsNone(data["checkout_url"])
        b = data["booking"]
        self.assertEqual(b["status"], "confirmed")
        self.assertEqual(b["booking_reference"], "ABC123")
        self.assertEqual(b["duffel_order_id"], "ord_1")
        self.assertTrue(b["test_mode"])
        self.assertEqual(b["passengers"][0]["ticket_number"], "006-1234567890")
        self.assertEqual(b["slices"][0]["segments"][0]["flight_number"], "DL1423")
        # Duffel is paid exactly the offer total, with our booking id for reconciliation.
        args = create.call_args.args
        self.assertEqual(args[0], "off_1")
        self.assertEqual(args[2:4], ("245.30", "USD"))
        self.assertIn("booking_id", args[4])
        self.assertEqual(args[1][0]["born_on"], "1990-12-10")

    def test_personal_details_are_wiped_once_ordered(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()):
            self.post()
        b = Booking.objects.get()
        self.assertEqual(b.passenger_input, {})
        self.assertNotIn("ada@example.com", json.dumps(b.to_api()))

    def test_price_change_returns_fresh_offer_and_books_nothing(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer(total="260.00")), \
             mock.patch.object(client, "create_order") as create:
            resp = self.post()
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.json()["error"], "price_changed")
        self.assertEqual(resp.json()["offer"]["total_amount"], "260.00")
        create.assert_not_called()
        self.assertEqual(Booking.objects.count(), 0)

    def test_traveler_ids_must_match_the_offer(self):
        body = {**BODY, "passengers": [fixtures.traveler("pas_other")]}
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()):
            resp = self.post(body)
        self.assertEqual(resp.status_code, 400)

    def test_every_traveler_on_the_fare_is_required(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer(pax=("pas_1", "pas_2"))):
            resp = self.post()
        self.assertEqual(resp.status_code, 400)

    def test_passport_required_when_airline_asks(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer(docs_required=True)):
            resp = self.post()
        self.assertEqual(resp.status_code, 400)
        doc = {"type": "passport", "unique_identifier": "X1", "issuing_country_code": "us", "expires_on": "2032-01-01"}
        body = {**BODY, "passengers": [fixtures.traveler(identity_documents=[doc])]}
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer(docs_required=True)), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()) as create:
            resp = self.post(body)
        self.assertEqual(resp.status_code, 201)
        sent = create.call_args.args[1][0]["identity_documents"][0]
        self.assertEqual(sent["issuing_country_code"], "US")
        self.assertEqual(sent["expires_on"], "2032-01-01")

    def test_field_validation(self):
        for bad in (
            fixtures.traveler(phone_number="4155550123"),
            fixtures.traveler(email="nope"),
            fixtures.traveler(title="sir"),
            fixtures.traveler(born_on="soon"),
        ):
            resp = self.post({**BODY, "passengers": [bad]})
            self.assertEqual(resp.status_code, 400, bad)
            self.assertEqual(resp.json()["error"], "validation_error")

    def test_expired_offer(self):
        with mock.patch.object(client, "get_offer", side_effect=DuffelError("gone", status=404, definite=True)):
            resp = self.post()
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.json()["error"], "offer_expired")

    def test_airline_rejects_order_marks_failed_and_not_charged(self):
        err = DuffelError("sold out", status=422, code="offer_no_longer_available", definite=True)
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", side_effect=err):
            resp = self.post()
        b = resp.json()["booking"]
        self.assertEqual(b["status"], "failed")
        self.assertIn("not charged", b["status_detail"])
        self.assertEqual(Booking.objects.get().passenger_input, {})

    def test_unknown_outcome_is_never_retried_or_refunded(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", side_effect=DuffelError("timeout")) as create:
            resp = self.post()
        b = Booking.objects.get()
        self.assertEqual(b.status, Booking.Status.PROCESSING)
        self.assertTrue(b.needs_attention)
        self.assertEqual(create.call_count, 1)
        self.assertEqual(resp.json()["booking"]["status"], "processing")

    def test_cannot_read_someone_elses_booking(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()):
            bid = self.post().json()["booking"]["id"]
        other = self.other_client()
        self.assertEqual(other.get(f"/api/v1/bookings/{bid}").status_code, 404)
        self.assertEqual(other.get("/api/v1/bookings").json(), {"bookings": []})
        self.assertEqual(len(self.client.get("/api/v1/bookings").json()["bookings"]), 1)

    @override_settings(DUFFEL_ACCESS_TOKEN="duffel_live_x", FLIGHTS_TEST_MODE=False, ALLOW_UNPAID_TEST_BOOKINGS=False)
    def test_live_token_without_stripe_cannot_book(self):
        with mock.patch.object(client, "create_order") as create:
            resp = self.post()
        self.assertEqual(resp.status_code, 503)
        create.assert_not_called()


def stripe_event(booking, kind="checkout.session.completed", paid=True, amount=None, event_id="evt_1"):
    return {
        "id": event_id, "type": kind,
        "data": {"object": {
            "id": "cs_1", "payment_status": "paid" if paid else "unpaid", "payment_intent": "pi_1",
            "amount_total": amount if amount is not None else 24530, "currency": "usd",
            "metadata": {"booking_id": str(booking.id)}, "client_reference_id": str(booking.id),
        }},
    }


@override_settings(**DUFFEL_ON, **STRIPE_ON)
class StripeCheckout(APITestCase):
    def start(self):
        session = SimpleNamespace(id="cs_1", url="https://checkout.stripe.com/c/pay/cs_1")
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(payments.stripe.checkout.Session, "create", return_value=session) as create:
            resp = self.client.post(URL, BODY, format="json")
        self.session_create = create
        return resp

    def send(self, event):
        with mock.patch.object(payments, "construct_event", return_value=event):
            return APIClient().post("/webhooks/stripe/", data=b"{}", content_type="application/json",
                                    HTTP_STRIPE_SIGNATURE="sig")

    def test_checkout_returns_stripe_url_and_waits_for_payment(self):
        resp = self.start()
        self.assertEqual(resp.status_code, 201, resp.content)
        data = resp.json()
        self.assertEqual(data["checkout_url"], "https://checkout.stripe.com/c/pay/cs_1")
        self.assertEqual(data["booking"]["status"], "pending_payment")
        kwargs = self.session_create.call_args.kwargs
        self.assertEqual(kwargs["line_items"][0]["price_data"]["unit_amount"], 24530)
        self.assertEqual(kwargs["line_items"][0]["price_data"]["currency"], "usd")
        self.assertEqual(kwargs["customer_email"], "ada@example.com")
        self.assertIn("/checkout/return/", kwargs["success_url"])
        self.assertTrue(kwargs["metadata"]["booking_id"])

    def test_paid_webhook_creates_the_order_once(self):
        self.start()
        b = Booking.objects.get()
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()) as create:
            self.assertEqual(self.send(stripe_event(b)).status_code, 200)
            # Stripe redelivers (same event id) and also sends a different event for the same payment.
            self.assertEqual(self.send(stripe_event(b)).status_code, 200)
            self.assertEqual(self.send(stripe_event(b, event_id="evt_2")).status_code, 200)
        self.assertEqual(create.call_count, 1)
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.CONFIRMED)
        self.assertEqual(b.stripe_payment_intent_id, "pi_1")
        self.assertEqual(b.passenger_input, {})
        self.assertEqual(WebhookEvent.objects.filter(provider="stripe", event_id="evt_1").count(), 1)

    def test_app_sees_confirmed_booking_after_webhook(self):
        bid = self.start().json()["booking"]["id"]
        b = Booking.objects.get()
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()):
            self.send(stripe_event(b))
        data = self.client.get(f"/api/v1/bookings/{bid}").json()
        self.assertEqual(data["status"], "confirmed")
        self.assertEqual(data["booking_reference"], "ABC123")

    def test_unpaid_session_completion_does_not_book(self):
        self.start()
        b = Booking.objects.get()
        with mock.patch.object(client, "create_order") as create:
            self.send(stripe_event(b, paid=False))
        create.assert_not_called()
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.PENDING_PAYMENT)

    def test_order_failure_after_payment_refunds_in_full(self):
        self.start()
        b = Booking.objects.get()
        err = DuffelError("sold out", status=422, code="offer_no_longer_available", definite=True)
        refund = SimpleNamespace(id="re_1", status="succeeded")
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", side_effect=err), \
             mock.patch.object(payments.stripe.Refund, "create", return_value=refund) as refund_create:
            self.send(stripe_event(b))
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.FAILED)
        self.assertIn("refunded", b.status_detail)
        kwargs = refund_create.call_args.kwargs
        self.assertEqual((kwargs["payment_intent"], kwargs["amount"]), ("pi_1", 24530))
        api = b.to_api()
        self.assertEqual(api["refund"], {"amount": "245.30", "currency": "USD", "status": "succeeded"})

    def test_refund_failure_is_flagged_for_a_human(self):
        self.start()
        b = Booking.objects.get()
        err = DuffelError("sold out", status=422, definite=True)
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", side_effect=err), \
             mock.patch.object(payments.stripe.Refund, "create", side_effect=stripe.APIConnectionError("down")):
            self.send(stripe_event(b))
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.FAILED)
        self.assertTrue(b.needs_attention)

    def test_fare_change_during_payment_refunds_without_ordering(self):
        self.start()
        b = Booking.objects.get()
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer(total="270.00")), \
             mock.patch.object(client, "create_order") as create, \
             mock.patch.object(payments.stripe.Refund, "create", return_value=SimpleNamespace(id="re_1", status="pending")):
            self.send(stripe_event(b))
        create.assert_not_called()
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.FAILED)
        self.assertEqual(b.refund_status, "pending")

    def test_amount_mismatch_refunds_and_does_not_book(self):
        self.start()
        b = Booking.objects.get()
        with mock.patch.object(client, "create_order") as create, \
             mock.patch.object(payments.stripe.Refund, "create", return_value=SimpleNamespace(id="re_1", status="succeeded")):
            self.send(stripe_event(b, amount=100))
        create.assert_not_called()
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.FAILED)
        self.assertTrue(b.needs_attention)

    def test_payment_after_expiry_is_refunded(self):
        self.start()
        b = Booking.objects.get()
        Booking.objects.filter(pk=b.pk).update(status=Booking.Status.EXPIRED)
        with mock.patch.object(client, "create_order") as create, \
             mock.patch.object(payments.stripe.Refund, "create", return_value=SimpleNamespace(id="re_1", status="succeeded")) as refund:
            self.send(stripe_event(b))
        create.assert_not_called()
        refund.assert_called_once()

    def test_expired_session_closes_the_booking_and_drops_personal_details(self):
        self.start()
        b = Booking.objects.get()
        self.send(stripe_event(b, kind="checkout.session.expired", paid=False))
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.EXPIRED)
        self.assertEqual(b.passenger_input, {})

    def test_stripe_session_failure_fails_cleanly(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(payments.stripe.checkout.Session, "create", side_effect=stripe.APIConnectionError("down")):
            resp = self.client.post(URL, BODY, format="json")
        self.assertEqual(resp.status_code, 502)
        self.assertEqual(Booking.objects.get().status, Booking.Status.FAILED)

    def test_webhook_rejects_bad_signature(self):
        resp = APIClient().post("/webhooks/stripe/", data=b"{}", content_type="application/json",
                                HTTP_STRIPE_SIGNATURE="t=1,v1=bad")
        self.assertEqual(resp.status_code, 400)

    def test_webhook_accepts_a_correctly_signed_payload(self):
        self.start()
        b = Booking.objects.get()
        payload = json.dumps(stripe_event(b, kind="checkout.session.expired", paid=False)).encode()
        ts = str(int(time.time()))
        sig = hmac.new(b"whsec_x", f"{ts}.".encode() + payload, hashlib.sha256).hexdigest()
        resp = APIClient().post("/webhooks/stripe/", data=payload, content_type="application/json",
                                HTTP_STRIPE_SIGNATURE=f"t={ts},v1={sig}")
        self.assertEqual(resp.status_code, 200, resp.content)
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.EXPIRED)

    def test_handler_crash_returns_500_so_stripe_retries_and_event_stays_unprocessed(self):
        self.start()
        b = Booking.objects.get()
        with mock.patch("bookings.services.handle_stripe_event", side_effect=RuntimeError("boom")):
            resp = self.send(stripe_event(b))
        self.assertEqual(resp.status_code, 500)
        self.assertIsNone(WebhookEvent.objects.get(event_id="evt_1").processed_at)

    @override_settings(SERVICE_FEE_PERCENT=__import__("decimal").Decimal("10"))
    def test_fee_is_charged_but_airline_gets_its_own_price(self):
        session = SimpleNamespace(id="cs_1", url="https://checkout.stripe.com/x")
        body = {**BODY, "expected_total_amount": "269.83"}
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(payments.stripe.checkout.Session, "create", return_value=session) as create:
            resp = self.client.post(URL, body, format="json")
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertEqual(create.call_args.kwargs["line_items"][0]["price_data"]["unit_amount"], 26983)
        b = Booking.objects.get()
        self.assertEqual(str(b.duffel_amount), "245.300")
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()), \
             mock.patch.object(client, "create_order", return_value=fixtures.order()) as order_create:
            self.send(stripe_event(b, amount=26983))
        self.assertEqual(order_create.call_args.args[2], "245.30")

    def test_three_decimal_currencies_are_refused_for_card_checkout(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer(total="50.000", currency="KWD")):
            resp = self.client.post(URL, {**BODY, "expected_total_amount": "50.000", "expected_total_currency": "KWD"}, format="json")
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.json()["error"], "currency_unsupported")
