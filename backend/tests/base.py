from unittest import mock

from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

DUFFEL_ON = dict(DUFFEL_ACCESS_TOKEN="duffel_test_abc", FLIGHTS_TEST_MODE=True)
STRIPE_ON = dict(
    STRIPE_SECRET_KEY="sk_test_x", STRIPE_WEBHOOK_SECRET="whsec_x", PAYMENTS_ENABLED=True,
    ALLOW_UNPAID_TEST_BOOKINGS=False, PUBLIC_BASE_URL="https://api.example.com",
)
NO_STRIPE = dict(PAYMENTS_ENABLED=False, ALLOW_UNPAID_TEST_BOOKINGS=True, STRIPE_SECRET_KEY="")


class APITestCase(TestCase):
    def setUp(self):
        cache.clear()  # throttle counters live in the cache
        self.client = APIClient()
        resp = self.client.post("/api/v1/devices/register", {}, format="json")
        assert resp.status_code == 201, resp.content
        self.device_id = resp.json()["device_id"]
        self.token = resp.json()["token"]
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token}")

    def other_client(self):
        c = APIClient()
        r = c.post("/api/v1/devices/register", {}, format="json")
        c.credentials(HTTP_AUTHORIZATION=f"Token {r.json()['token']}")
        return c
