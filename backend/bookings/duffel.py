"""Thin Duffel REST client. https://duffel.com/docs/api

The token is a full-account credential (it can spend the balance and cancel
real flights), so this module is the only place that ever sees it.
"""
import logging

import requests
from django.conf import settings

log = logging.getLogger(__name__)


class DuffelError(Exception):
    """A failed Duffel call.

    `definite` is True when Duffel told us (a 4xx) that the request was
    rejected, so nothing happened upstream. It is False for timeouts and 5xx,
    where an order may or may not exist. Callers must treat those differently.
    """

    def __init__(self, message: str, status: int | None = None, code: str = "", definite: bool = False):
        super().__init__(message)
        self.message = message
        self.status = status
        self.code = code
        self.definite = definite

    @property
    def offer_gone(self) -> bool:
        return self.code in {"offer_no_longer_available", "offer_expired"} or self.status == 404


class DuffelClient:
    def __init__(self):
        self.session = requests.Session()

    @property
    def configured(self) -> bool:
        return bool(settings.DUFFEL_ACCESS_TOKEN)

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {settings.DUFFEL_ACCESS_TOKEN}",
            "Duffel-Version": settings.DUFFEL_API_VERSION,
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _request(self, method: str, path: str, *, json=None, params=None, timeout=None) -> dict:
        url = f"{settings.DUFFEL_BASE_URL}{path}"
        try:
            resp = self.session.request(
                method, url, json=json, params=params, headers=self._headers(),
                timeout=timeout or settings.DUFFEL_TIMEOUT_SECONDS,
            )
        except requests.RequestException as exc:
            log.warning("Duffel %s %s transport error: %s", method, path, exc)
            raise DuffelError("The airline service didn't respond.", definite=False) from exc

        if resp.status_code >= 400:
            code, message = "", ""
            try:
                err = (resp.json().get("errors") or [{}])[0]
                code, message = err.get("code", ""), err.get("message", "")
            except ValueError:
                pass
            if resp.status_code >= 500:
                log.error("Duffel %s %s -> %s", method, path, resp.status_code)
            raise DuffelError(
                message or "The airline service rejected the request.",
                status=resp.status_code, code=code, definite=resp.status_code < 500,
            )
        try:
            return resp.json()["data"]
        except (ValueError, KeyError) as exc:
            raise DuffelError("The airline service sent an unreadable response.", definite=False) from exc

    # ── Search ───────────────────────────────────────────────────────────────
    def create_offer_request(self, slices: list, passengers: list, cabin_class: str) -> dict:
        return self._request(
            "POST", "/air/offer_requests",
            params={"return_offers": "true", "supplier_timeout": 20000},
            json={"data": {"slices": slices, "passengers": passengers, "cabin_class": cabin_class}},
            timeout=60,
        )

    def get_offer(self, offer_id: str) -> dict:
        return self._request("GET", f"/air/offers/{offer_id}", params={"return_available_services": "false"})

    # ── Orders ───────────────────────────────────────────────────────────────
    def create_order(self, offer_id: str, passengers: list, amount: str, currency: str, metadata: dict) -> dict:
        return self._request(
            "POST", "/air/orders",
            json={"data": {
                "type": "instant",
                "selected_offers": [offer_id],
                "payments": [{"type": "balance", "amount": amount, "currency": currency}],
                "passengers": passengers,
                "metadata": metadata,
            }},
            timeout=settings.DUFFEL_ORDER_TIMEOUT_SECONDS,
        )

    def get_order(self, order_id: str) -> dict:
        return self._request("GET", f"/air/orders/{order_id}")

    # ── Cancellation ─────────────────────────────────────────────────────────
    def create_cancellation(self, order_id: str) -> dict:
        return self._request("POST", "/air/order_cancellations", json={"data": {"order_id": order_id}})

    def confirm_cancellation(self, cancellation_id: str) -> dict:
        return self._request(
            "POST", f"/air/order_cancellations/{cancellation_id}/actions/confirm",
            timeout=settings.DUFFEL_ORDER_TIMEOUT_SECONDS,
        )


client = DuffelClient()
