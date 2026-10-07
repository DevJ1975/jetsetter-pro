"""Duffel objects to the compact shapes documented in docs/BACKEND_API.md.

Everything is read defensively: Duffel omits fields that don't apply, and the
app must never crash (or invent data) because one is absent.
"""
from decimal import Decimal, InvalidOperation

from datetime import timezone as dt_timezone

from django.utils.dateparse import parse_datetime

from . import pricing


def _airport(raw: dict | None) -> dict:
    raw = raw or {}
    return {
        "iata_code": raw.get("iata_code"),
        "name": raw.get("name"),
        "city_name": raw.get("city_name"),
        "time_zone": raw.get("time_zone"),
    }


def _carrier(raw: dict | None) -> dict:
    raw = raw or {}
    return {
        "name": raw.get("name"),
        "iata_code": raw.get("iata_code"),
        "logo_url": raw.get("logo_symbol_url") or raw.get("logo_lockup_url"),
    }


def _condition(raw: dict | None) -> dict | None:
    if not raw:
        return None
    return {
        "allowed": bool(raw.get("allowed")),
        "penalty_amount": raw.get("penalty_amount"),
        "penalty_currency": raw.get("penalty_currency"),
    }


def conditions(raw: dict | None) -> dict:
    raw = raw or {}
    return {
        "refund_before_departure": _condition(raw.get("refund_before_departure")),
        "change_before_departure": _condition(raw.get("change_before_departure")),
    }


def _segment(raw: dict) -> dict:
    carrier = raw.get("marketing_carrier") or {}
    number = raw.get("marketing_carrier_flight_number") or ""
    code = carrier.get("iata_code") or ""
    aircraft = raw.get("aircraft") or {}
    return {
        "marketing_carrier": {"name": carrier.get("name"), "iata_code": code or None},
        "flight_number": f"{code}{number}" if (code or number) else None,
        "origin": _airport(raw.get("origin")),
        "destination": _airport(raw.get("destination")),
        "departing_at": raw.get("departing_at"),
        "arriving_at": raw.get("arriving_at"),
        "duration": raw.get("duration"),
        "aircraft": aircraft.get("name"),
        "origin_terminal": raw.get("origin_terminal"),
        "destination_terminal": raw.get("destination_terminal"),
    }


def slices(raw_slices: list | None) -> list:
    out = []
    for raw in raw_slices or []:
        segments = [_segment(s) for s in raw.get("segments") or []]
        out.append({
            "origin": _airport(raw.get("origin")),
            "destination": _airport(raw.get("destination")),
            "duration": raw.get("duration"),
            "stops": max(len(segments) - 1, 0),
            "fare_brand_name": raw.get("fare_brand_name"),
            "segments": segments,
        })
    return out


def baggage(raw_slices: list | None) -> list:
    """Allowance for the first passenger on the first segment, which is what
    Duffel quotes for the fare. Later segments inherit it on the same ticket."""
    for sl in raw_slices or []:
        for seg in sl.get("segments") or []:
            for pax in seg.get("passengers") or []:
                bags = pax.get("baggages") or []
                if bags:
                    return [{"type": b.get("type"), "quantity": b.get("quantity", 0)} for b in bags]
    return []


def cabin(raw_slices: list | None) -> str | None:
    for sl in raw_slices or []:
        for seg in sl.get("segments") or []:
            for pax in seg.get("passengers") or []:
                if pax.get("cabin_class"):
                    return pax["cabin_class"]
    return None


def duffel_total(raw: dict) -> tuple[Decimal, str]:
    try:
        return Decimal(str(raw["total_amount"])), str(raw["total_currency"]).upper()
    except (KeyError, InvalidOperation) as exc:
        raise ValueError("Offer has no usable total") from exc


def first_departure(normalised_slices: list):
    for sl in normalised_slices:
        for seg in sl["segments"]:
            if seg.get("departing_at"):
                # Local wall-clock; pinned to UTC only so bookings sort roughly.
                dt = parse_datetime(seg["departing_at"])
                if dt is not None and dt.tzinfo is None:
                    dt = dt.replace(tzinfo=dt_timezone.utc)
                return dt
    return None


def offer(raw: dict, fee: Decimal) -> dict:
    total, currency = duffel_total(raw)
    sl = slices(raw.get("slices"))
    return {
        "id": raw["id"],
        "airline": _carrier(raw.get("owner")),
        "total_amount": pricing.fmt(total + fee, currency),
        "total_currency": currency,
        "fee_amount": pricing.fmt(fee, currency),
        "cabin_class": cabin(raw.get("slices")),
        "slices": sl,
        "passengers": [{"id": p.get("id"), "type": p.get("type")} for p in raw.get("passengers") or []],
        "requires_identity_documents": bool(raw.get("passenger_identity_documents_required")),
        "conditions": conditions(raw.get("conditions")),
        "baggage": baggage(raw.get("slices")),
        "expires_at": raw.get("expires_at"),
    }


def order_passengers(raw_order: dict) -> list:
    tickets: dict[str, str] = {}
    for doc in raw_order.get("documents") or []:
        if doc.get("type") == "electronic_ticket":
            for pid in doc.get("passenger_ids") or []:
                tickets[pid] = doc.get("unique_identifier")
    seats: dict[str, str] = {}
    for svc in raw_order.get("services") or []:
        if svc.get("type") == "seat":
            designator = (svc.get("metadata") or {}).get("designator")
            for pid in svc.get("passenger_ids") or []:
                if designator:
                    seats[pid] = designator
    out = []
    for p in raw_order.get("passengers") or []:
        out.append({
            "id": p.get("id"),
            "type": p.get("type"),
            "title": p.get("title"),
            "given_name": p.get("given_name"),
            "family_name": p.get("family_name"),
            "ticket_number": tickets.get(p.get("id")),
            "seat": seats.get(p.get("id")),
        })
    return out


def has_unhandled_airline_changes(raw_order: dict) -> bool:
    changes = raw_order.get("airline_initiated_changes") or []
    return any(not c.get("action_taken") for c in changes)


def order_fields(raw_order: dict) -> dict:
    """Fields of a Booking that mirror the airline's order."""
    sl = slices(raw_order.get("slices"))
    return {
        "duffel_order_id": raw_order.get("id"),
        "booking_reference": raw_order.get("booking_reference") or "",
        "airline": _carrier(raw_order.get("owner")),
        "slices": sl,
        "conditions": conditions(raw_order.get("conditions")),
        "baggage": baggage(raw_order.get("slices")),
        "passengers": order_passengers(raw_order),
        "first_departure": first_departure(sl),
        "has_airline_changes": has_unhandled_airline_changes(raw_order),
    }
