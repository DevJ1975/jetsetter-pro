from decimal import Decimal

from unittest import mock

from django.test import override_settings

from bookings.duffel import DuffelError, client

from . import fixtures
from .base import DUFFEL_ON, NO_STRIPE, APITestCase

BODY = {
    "slices": [{"origin": "las", "destination": "atl", "departure_date": "2026-11-02"}],
    "passengers": {"adults": 1},
    "cabin_class": "economy",
}


@override_settings(**DUFFEL_ON, **NO_STRIPE)
class SearchTests(APITestCase):
    def test_returns_normalised_offers_cheapest_first(self):
        raw = {"id": "orq_1", "offers": [fixtures.offer("off_b", "300.00"), fixtures.offer("off_a", "245.30")]}
        with mock.patch.object(client, "create_offer_request", return_value=raw) as call:
            resp = self.client.post("/api/v1/flights/search", BODY, format="json")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual([o["id"] for o in data["offers"]], ["off_a", "off_b"])
        self.assertEqual(data["search_id"], "orq_1")
        # codes are upper-cased before they reach Duffel
        slices, passengers, cabin = call.call_args.args
        self.assertEqual(slices, [{"origin": "LAS", "destination": "ATL", "departure_date": "2026-11-02"}])
        self.assertEqual(passengers, [{"type": "adult"}])

    def test_offer_shape_matches_the_contract(self):
        with mock.patch.object(client, "create_offer_request", return_value={"id": "orq", "offers": [fixtures.offer()]}):
            offer = self.client.post("/api/v1/flights/search", BODY, format="json").json()["offers"][0]
        self.assertEqual(offer["total_amount"], "245.30")
        self.assertEqual(offer["total_currency"], "USD")
        self.assertEqual(offer["airline"]["iata_code"], "DL")
        self.assertEqual(offer["cabin_class"], "economy")
        self.assertEqual(offer["passengers"], [{"id": "pas_1", "type": "adult"}])
        self.assertFalse(offer["requires_identity_documents"])
        sl = offer["slices"][0]
        self.assertEqual(sl["stops"], 0)
        self.assertEqual(sl["origin"]["time_zone"], "America/Los_Angeles")
        seg = sl["segments"][0]
        self.assertEqual(seg["flight_number"], "DL1423")
        self.assertEqual(seg["departing_at"], "2026-11-02T09:05:00")
        self.assertEqual(seg["origin_terminal"], "1")
        self.assertEqual(seg["aircraft"], "Boeing 737-900")
        self.assertEqual(offer["baggage"], [{"type": "checked", "quantity": 1}, {"type": "carry_on", "quantity": 1}])
        self.assertTrue(offer["conditions"]["refund_before_departure"]["allowed"])

    def test_connecting_itinerary_counts_stops(self):
        o = fixtures.offer()
        o["slices"][0]["segments"].append(dict(o["slices"][0]["segments"][0]))
        with mock.patch.object(client, "create_offer_request", return_value={"id": "orq", "offers": [o]}):
            offer = self.client.post("/api/v1/flights/search", BODY, format="json").json()["offers"][0]
        self.assertEqual(offer["slices"][0]["stops"], 1)

    @override_settings(SERVICE_FEE_PERCENT=Decimal("10"))
    def test_service_fee_is_included_in_the_price_shown(self):
        with mock.patch.object(client, "create_offer_request", return_value={"id": "orq", "offers": [fixtures.offer(total="100.00")]}):
            offer = self.client.post("/api/v1/flights/search", BODY, format="json").json()["offers"][0]
        self.assertEqual(offer["total_amount"], "110.00")
        self.assertEqual(offer["fee_amount"], "10.00")

    def test_unreadable_offers_are_skipped_not_fatal(self):
        bad = {"id": "off_bad"}
        with mock.patch.object(client, "create_offer_request", return_value={"id": "orq", "offers": [bad, fixtures.offer()]}):
            data = self.client.post("/api/v1/flights/search", BODY, format="json").json()
        self.assertEqual(len(data["offers"]), 1)

    def test_validation(self):
        for body in (
            {},
            {"slices": []},
            {"slices": [{"origin": "LAS", "destination": "LAS", "departure_date": "2026-11-02"}]},
            {"slices": [{"origin": "LASX", "destination": "ATL", "departure_date": "2026-11-02"}]},
            {"slices": [{"origin": "LAS", "destination": "ATL", "departure_date": "nope"}]},
            {**BODY, "passengers": {"adults": 0}},
            {**BODY, "passengers": {"adults": 1, "infants": 2}},
            {**BODY, "cabin_class": "steerage"},
        ):
            resp = self.client.post("/api/v1/flights/search", body, format="json")
            self.assertEqual(resp.status_code, 400, body)
            self.assertEqual(resp.json()["error"], "validation_error")

    def test_requires_auth(self):
        from rest_framework.test import APIClient
        self.assertEqual(APIClient().post("/api/v1/flights/search", BODY, format="json").status_code, 401)

    @override_settings(DUFFEL_ACCESS_TOKEN="")
    def test_503_when_duffel_not_configured(self):
        resp = self.client.post("/api/v1/flights/search", BODY, format="json")
        self.assertEqual(resp.status_code, 503)
        self.assertEqual(resp.json()["error"], "flights_unavailable")

    def test_upstream_outage_is_a_502_without_leaking_details(self):
        with mock.patch.object(client, "create_offer_request", side_effect=DuffelError("secret internal detail", status=500)):
            resp = self.client.post("/api/v1/flights/search", BODY, format="json")
        self.assertEqual(resp.status_code, 502)
        self.assertEqual(resp.json()["error"], "upstream_error")
        self.assertNotIn("secret", resp.content.decode())

    def test_duffel_rejection_surfaces_the_reason(self):
        err = DuffelError("departure_date must be in the future", status=422, code="validation_error", definite=True)
        with mock.patch.object(client, "create_offer_request", side_effect=err):
            resp = self.client.post("/api/v1/flights/search", BODY, format="json")
        self.assertEqual(resp.status_code, 422)
        self.assertIn("future", resp.json()["message"])

    def test_get_offer(self):
        with mock.patch.object(client, "get_offer", return_value=fixtures.offer()):
            resp = self.client.get("/api/v1/flights/offers/off_1")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["id"], "off_1")

    def test_get_offer_gone(self):
        with mock.patch.object(client, "get_offer", side_effect=DuffelError("gone", status=404, definite=True)):
            resp = self.client.get("/api/v1/flights/offers/off_1")
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.json()["error"], "offer_expired")
