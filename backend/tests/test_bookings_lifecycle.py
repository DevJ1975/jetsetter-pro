import hashlib
import hmac
import json
from types import SimpleNamespace
from unittest import mock

from django.test import override_settings
from rest_framework.test import APIClient

from accounts.models import Device
from bookings import payments
from bookings.duffel import DuffelError, client
from bookings.models import Booking

from . import fixtures
from .base import DUFFEL_ON, NO_STRIPE, STRIPE_ON, APITestCase


class LifecycleBase(APITestCase):
    def make_booking(self, **over):
        user = Device.objects.get(pk=self.device_id).user
        fields = dict(
            user=user, offer_id="off_1", status=Booking.Status.CONFIRMED, duffel_order_id="ord_1",
            booking_reference="ABC123", total_amount="245.30", duffel_amount="245.30", currency="USD",
            stripe_payment_intent_id="pi_1",
        )
        fields.update(over)
        return Booking.objects.create(**fields)


@override_settings(**DUFFEL_ON, **NO_STRIPE)
class RefreshTests(LifecycleBase):
    def test_refresh_pulls_airline_schedule_change(self):
        b = self.make_booking()
        changed = fixtures.order(changes=[{"id": "ace_1"}])
        changed["slices"][0]["segments"][0]["departing_at"] = "2026-11-02T11:30:00"
        with mock.patch.object(client, "get_order", return_value=changed):
            data = self.client.get(f"/api/v1/bookings/{b.id}?refresh=true").json()
        self.assertEqual(data["slices"][0]["segments"][0]["departing_at"], "2026-11-02T11:30:00")
        self.assertTrue(data["has_airline_changes"])

    def test_without_refresh_flag_duffel_is_not_called(self):
        b = self.make_booking()
        with mock.patch.object(client, "get_order") as get_order:
            self.assertEqual(self.client.get(f"/api/v1/bookings/{b.id}").status_code, 200)
        get_order.assert_not_called()

    def test_refresh_failure_serves_the_saved_booking(self):
        b = self.make_booking()
        with mock.patch.object(client, "get_order", side_effect=DuffelError("down")):
            resp = self.client.get(f"/api/v1/bookings/{b.id}?refresh=true")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["booking_reference"], "ABC123")

    def test_list_is_newest_first(self):
        a = self.make_booking(duffel_order_id="ord_a")
        b = self.make_booking(duffel_order_id="ord_b")
        ids = [x["id"] for x in self.client.get("/api/v1/bookings").json()["bookings"]]
        self.assertEqual(ids, [str(b.id), str(a.id)])


@override_settings(**DUFFEL_ON, **STRIPE_ON)
class CancellationTests(LifecycleBase):
    def quote(self, b, refund="120.00"):
        q = {"id": "ore_1", "refund_amount": refund, "refund_currency": "USD", "expires_at": "2026-10-07T20:00:00Z"}
        with mock.patch.object(client, "create_cancellation", return_value=q):
            return self.client.post(f"/api/v1/bookings/{b.id}/cancel/quote")

    def test_quote_shows_refund_before_anything_happens(self):
        b = self.make_booking()
        resp = self.quote(b)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["refund_amount"], "120.00")
        self.assertEqual(resp.json()["cancellation_id"], "ore_1")
        b.refresh_from_db()
        self.assertEqual(b.status, Booking.Status.CONFIRMED)

    def test_confirm_cancels_and_refunds_the_airline_amount_to_the_card(self):
        b = self.make_booking()
        self.quote(b)
        done = {"id": "ore_1", "refund_amount": "120.00", "refund_currency": "USD"}
        with mock.patch.object(client, "confirm_cancellation", return_value=done), \
             mock.patch.object(payments.stripe.Refund, "create", return_value=SimpleNamespace(id="re_9", status="succeeded")) as refund:
            resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/confirm", {"cancellation_id": "ore_1"}, format="json")
        self.assertEqual(resp.status_code, 200, resp.content)
        data = resp.json()
        self.assertEqual(data["status"], "cancelled")
        self.assertEqual(data["refund"], {"amount": "120.00", "currency": "USD", "status": "succeeded"})
        self.assertEqual(refund.call_args.kwargs["amount"], 12000)

    def test_zero_refund_cancels_without_touching_stripe(self):
        b = self.make_booking()
        self.quote(b, refund="0.00")
        with mock.patch.object(client, "confirm_cancellation", return_value={"id": "ore_1", "refund_amount": "0.00", "refund_currency": "USD"}), \
             mock.patch.object(payments.stripe.Refund, "create") as refund:
            resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/confirm", {"cancellation_id": "ore_1"}, format="json")
        self.assertEqual(resp.json()["status"], "cancelled")
        self.assertIsNone(resp.json()["refund"])
        refund.assert_not_called()

    def test_refund_cannot_exceed_what_was_paid(self):
        b = self.make_booking()
        self.quote(b, refund="999.00")
        with mock.patch.object(client, "confirm_cancellation", return_value={"id": "ore_1", "refund_amount": "999.00", "refund_currency": "USD"}), \
             mock.patch.object(payments.stripe.Refund, "create", return_value=SimpleNamespace(id="re", status="pending")) as refund:
            self.client.post(f"/api/v1/bookings/{b.id}/cancel/confirm", {"cancellation_id": "ore_1"}, format="json")
        self.assertEqual(refund.call_args.kwargs["amount"], 24530)

    def test_card_refund_failure_still_cancels_but_flags_for_a_human(self):
        import stripe
        b = self.make_booking()
        self.quote(b)
        with mock.patch.object(client, "confirm_cancellation", return_value={"id": "ore_1", "refund_amount": "120.00", "refund_currency": "USD"}), \
             mock.patch.object(payments.stripe.Refund, "create", side_effect=stripe.APIConnectionError("x")):
            resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/confirm", {"cancellation_id": "ore_1"}, format="json")
        self.assertEqual(resp.json()["status"], "cancelled")
        b.refresh_from_db()
        self.assertTrue(b.needs_attention)
        self.assertEqual(b.refund_status, "failed")

    def test_confirm_requires_the_quoted_id(self):
        b = self.make_booking()
        self.quote(b)
        with mock.patch.object(client, "confirm_cancellation") as confirm:
            resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/confirm", {"cancellation_id": "ore_other"}, format="json")
        self.assertEqual(resp.status_code, 409)
        confirm.assert_not_called()

    def test_confirm_without_quote_is_refused(self):
        b = self.make_booking()
        resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/confirm", {"cancellation_id": "ore_1"}, format="json")
        self.assertEqual(resp.status_code, 409)

    def test_only_confirmed_bookings_can_be_cancelled(self):
        for status in (Booking.Status.PENDING_PAYMENT, Booking.Status.FAILED, Booking.Status.CANCELLED):
            b = self.make_booking(status=status, duffel_order_id=None)
            resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/quote")
            self.assertEqual(resp.status_code, 409, status)
            self.assertEqual(resp.json()["error"], "not_cancellable")

    def test_airline_refusal_is_a_409(self):
        b = self.make_booking()
        err = DuffelError("Order not cancellable", status=422, definite=True)
        with mock.patch.object(client, "create_cancellation", side_effect=err):
            resp = self.client.post(f"/api/v1/bookings/{b.id}/cancel/quote")
        self.assertEqual(resp.status_code, 409)

    def test_cannot_cancel_someone_elses_booking(self):
        b = self.make_booking()
        other = self.other_client()
        self.assertEqual(other.post(f"/api/v1/bookings/{b.id}/cancel/quote").status_code, 404)


@override_settings(**DUFFEL_ON, **NO_STRIPE, DUFFEL_WEBHOOK_SECRET="whsec_duffel")
class DuffelWebhookTests(LifecycleBase):
    def send(self, event, secret="whsec_duffel"):
        body = json.dumps(event).encode()
        sig = hmac.new(secret.encode(), b"1700000000." + body, hashlib.sha256).hexdigest()
        return APIClient().post("/webhooks/duffel/", data=body, content_type="application/json",
                                HTTP_X_DUFFEL_SIGNATURE=f"t=1700000000,v1={sig}")

    def test_airline_change_event_refreshes_and_flags_booking(self):
        b = self.make_booking()
        order = fixtures.order(changes=[{"id": "ace_1"}])
        with mock.patch.object(client, "get_order", return_value=order):
            resp = self.send({"id": "eve_1", "type": "order.airline_initiated_change_detected",
                              "data": {"object": {"id": "ord_1"}}})
        self.assertEqual(resp.status_code, 200)
        b.refresh_from_db()
        self.assertTrue(b.has_airline_changes)
        self.assertTrue(b.needs_attention)

    def test_bad_signature_rejected(self):
        resp = self.send({"id": "eve_1", "type": "order.created", "data": {"object": {"id": "ord_1"}}}, secret="wrong")
        self.assertEqual(resp.status_code, 400)

    def test_unknown_order_is_ignored(self):
        resp = self.send({"id": "eve_2", "type": "order.created", "data": {"object": {"id": "ord_none"}}})
        self.assertEqual(resp.status_code, 200)

    @override_settings(DUFFEL_WEBHOOK_SECRET="")
    def test_unconfigured_secret_refuses(self):
        self.assertEqual(self.send({"id": "x", "type": "order.created", "data": {}}).status_code, 503)


class HandoffTests(APITestCase):
    def test_flights(self):
        resp = self.client.get("/api/v1/handoff/flights", {
            "origin": "las", "destination": "atl", "depart": "2026-11-02", "return": "2026-11-05", "adults": 2, "airline": "DL"})
        self.assertEqual(resp.status_code, 200, resp.content)
        providers = resp.json()["providers"]
        by_id = {p["id"]: p for p in providers}
        self.assertEqual(by_id["kayak"]["url"], "https://www.kayak.com/flights/LAS-ATL/2026-11-02/2026-11-05?adults=2")
        self.assertIn("google.com/travel/flights", by_id["google_flights"]["url"])
        self.assertEqual(by_id["dl"]["url"], "https://www.delta.com")
        self.assertEqual(providers[2]["id"], "dl")  # the airline the traveler was looking at comes first
        self.assertEqual(len({p["id"] for p in providers}), len(providers))

    def test_one_way_has_no_return_leg(self):
        resp = self.client.get("/api/v1/handoff/flights", {"origin": "LAS", "destination": "ATL", "depart": "2026-11-02"})
        kayak = next(p for p in resp.json()["providers"] if p["id"] == "kayak")
        self.assertEqual(kayak["url"], "https://www.kayak.com/flights/LAS-ATL/2026-11-02?adults=1")

    def test_return_before_depart_is_rejected(self):
        resp = self.client.get("/api/v1/handoff/flights", {
            "origin": "LAS", "destination": "ATL", "depart": "2026-11-05", "return": "2026-11-02"})
        self.assertEqual(resp.status_code, 400)

    def test_hotels_encode_destination(self):
        resp = self.client.get("/api/v1/handoff/hotels", {
            "destination": "Dallas/Fort Worth", "check_in": "2026-11-02", "check_out": "2026-11-05", "guests": 2})
        self.assertEqual(resp.status_code, 200)
        kayak = next(p for p in resp.json()["providers"] if p["id"] == "kayak")
        self.assertIn("Dallas%2FFort%20Worth", kayak["url"])
        self.assertTrue(any(p["kind"] == "hotel" for p in resp.json()["providers"]))

    def test_hotel_dates_validated(self):
        resp = self.client.get("/api/v1/handoff/hotels", {"destination": "X", "check_in": "2026-11-05", "check_out": "2026-11-02"})
        self.assertEqual(resp.status_code, 400)

    def test_cars_list_brands_and_airport_search(self):
        resp = self.client.get("/api/v1/handoff/cars", {"pickup": "LAS", "pickup_date": "2026-11-02", "dropoff_date": "2026-11-05"})
        ids = [p["id"] for p in resp.json()["providers"]]
        self.assertIn("hertz", ids)
        self.assertEqual(ids[0], "kayak")
        resp = self.client.get("/api/v1/handoff/cars", {"pickup": "Las Vegas", "pickup_date": "2026-11-02", "dropoff_date": "2026-11-05"})
        self.assertNotIn("kayak", [p["id"] for p in resp.json()["providers"]])

    def test_unknown_kind_and_auth(self):
        self.assertEqual(self.client.get("/api/v1/handoff/boats").status_code, 404)
        self.assertEqual(APIClient().get("/api/v1/handoff/cars").status_code, 401)
