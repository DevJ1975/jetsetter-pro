from django.test import override_settings
from rest_framework.test import APIClient

from accounts.models import Device
from bookings.models import Booking

from .base import DUFFEL_ON, NO_STRIPE, STRIPE_ON, APITestCase


class AccountTests(APITestCase):
    def test_register_returns_token_and_creates_device(self):
        self.assertTrue(Device.objects.filter(pk=self.device_id).exists())
        self.assertEqual(len(self.token), 40)

    def test_protected_routes_need_a_token(self):
        resp = APIClient().get("/api/v1/bookings")
        self.assertEqual(resp.status_code, 401)
        self.assertEqual(resp.json()["error"], "not_authenticated")

    def test_bad_token_is_401(self):
        c = APIClient()
        c.credentials(HTTP_AUTHORIZATION="Token nope")
        self.assertEqual(c.get("/api/v1/bookings").status_code, 401)

    def test_delete_account_erases_device_and_personal_details_but_keeps_the_record(self):
        from django.contrib.auth import get_user_model

        user = Device.objects.get(pk=self.device_id).user
        b = Booking.objects.create(
            user=user, offer_id="off_1", total_amount="100", duffel_amount="100", currency="USD",
            status=Booking.Status.CONFIRMED, booking_reference="ABC123",
            passengers=[{"given_name": "Ada"}], passenger_input={"passengers": [{"email": "a@b.c"}]},
        )
        resp = self.client.delete("/api/v1/account")
        self.assertEqual(resp.status_code, 204)
        self.assertFalse(Device.objects.filter(pk=self.device_id).exists())
        self.assertFalse(get_user_model().objects.filter(pk=user.pk).exists())
        b.refresh_from_db()
        self.assertIsNone(b.user)
        self.assertEqual(b.passengers, [])
        self.assertEqual(b.passenger_input, {})
        self.assertEqual(b.booking_reference, "ABC123")
        # The old token no longer works.
        self.assertEqual(self.client.get("/api/v1/bookings").status_code, 401)


class PublicPageTests(APITestCase):
    def test_health(self):
        resp = APIClient().get("/health/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"status": "ok"})

    @override_settings(**DUFFEL_ON, **NO_STRIPE)
    def test_config_test_mode(self):
        data = APIClient().get("/api/v1/config").json()
        self.assertTrue(data["flights_enabled"])
        self.assertTrue(data["test_mode"])
        self.assertFalse(data["payments_enabled"])

    @override_settings(DUFFEL_ACCESS_TOKEN="", FLIGHTS_TEST_MODE=False, **NO_STRIPE)
    def test_config_without_duffel_disables_flights(self):
        self.assertFalse(APIClient().get("/api/v1/config").json()["flights_enabled"])

    @override_settings(DUFFEL_ACCESS_TOKEN="duffel_live_x", FLIGHTS_TEST_MODE=False, PAYMENTS_ENABLED=False,
                       ALLOW_UNPAID_TEST_BOOKINGS=False)
    def test_live_duffel_without_stripe_is_not_bookable(self):
        """A live token must never be usable for free bookings."""
        self.assertFalse(APIClient().get("/api/v1/config").json()["flights_enabled"])

    @override_settings(**DUFFEL_ON, **STRIPE_ON)
    def test_config_links_for_app_store(self):
        data = APIClient().get("/api/v1/config").json()
        self.assertEqual(data["privacy_url"], "https://api.example.com/privacy/")
        self.assertEqual(data["terms_url"], "https://api.example.com/terms/")

    def test_legal_pages_render(self):
        for path in ("/", "/privacy/", "/terms/", "/support/"):
            resp = APIClient().get(path)
            self.assertEqual(resp.status_code, 200, path)
        self.assertContains(APIClient().get("/privacy/"), "Delete my data")

    def test_checkout_return_deep_links_into_app(self):
        resp = APIClient().get("/checkout/return/?booking=8b2d2c0e-0d0f-4a8b-9a50-0c7a0f7b2f11&result=success")
        self.assertContains(resp, "jetsetterpro://booking/8b2d2c0e-0d0f-4a8b-9a50-0c7a0f7b2f11")

    def test_checkout_return_ignores_junk_ids(self):
        resp = APIClient().get("/checkout/return/?booking=<script>alert(1)</script>")
        self.assertNotContains(resp, "<script>alert")
        self.assertContains(resp, "jetsetterpro://bookings")
