"""Duffel-shaped payloads used across the tests."""
import copy

AIRPORT_LAS = {"iata_code": "LAS", "name": "Harry Reid International", "city_name": "Las Vegas", "time_zone": "America/Los_Angeles"}
AIRPORT_ATL = {"iata_code": "ATL", "name": "Hartsfield-Jackson", "city_name": "Atlanta", "time_zone": "America/New_York"}
DELTA = {"name": "Delta Air Lines", "iata_code": "DL", "logo_symbol_url": "https://assets.duffel.com/img/airlines/DL.svg"}


def offer(offer_id="off_1", total="245.30", currency="USD", docs_required=False, pax=("pas_1",)):
    return {
        "id": offer_id,
        "total_amount": total,
        "total_currency": currency,
        "owner": DELTA,
        "expires_at": "2026-10-07T18:00:00Z",
        "passenger_identity_documents_required": docs_required,
        "passengers": [{"id": p, "type": "adult"} for p in pax],
        "conditions": {
            "refund_before_departure": {"allowed": True, "penalty_amount": "50.00", "penalty_currency": "USD"},
            "change_before_departure": {"allowed": True, "penalty_amount": None, "penalty_currency": None},
        },
        "slices": [{
            "origin": AIRPORT_LAS, "destination": AIRPORT_ATL, "duration": "PT4H10M", "fare_brand_name": "Main Cabin",
            "segments": [{
                "marketing_carrier": DELTA, "marketing_carrier_flight_number": "1423",
                "origin": AIRPORT_LAS, "destination": AIRPORT_ATL,
                "departing_at": "2026-11-02T09:05:00", "arriving_at": "2026-11-02T16:15:00",
                "duration": "PT4H10M", "aircraft": {"name": "Boeing 737-900"},
                "origin_terminal": "1", "destination_terminal": "S",
                "passengers": [{"cabin_class": "economy", "baggages": [
                    {"type": "checked", "quantity": 1}, {"type": "carry_on", "quantity": 1}]}],
            }],
        }],
    }


def order(order_id="ord_1", pnr="ABC123", pax=("pas_1",), cancelled_at=None, changes=None):
    base = offer(pax=pax)
    return {
        "id": order_id,
        "booking_reference": pnr,
        "owner": DELTA,
        "slices": copy.deepcopy(base["slices"]),
        "conditions": base["conditions"],
        "passengers": [{"id": p, "type": "adult", "title": "ms", "given_name": "Ada", "family_name": "Lovelace"} for p in pax],
        "documents": [{"type": "electronic_ticket", "unique_identifier": "006-1234567890", "passenger_ids": list(pax)}],
        "services": [],
        "cancelled_at": cancelled_at,
        "airline_initiated_changes": changes or [],
        "total_amount": "245.30",
        "total_currency": "USD",
    }


def traveler(pid="pas_1", **over):
    data = {
        "id": pid, "title": "ms", "given_name": "Ada", "family_name": "Lovelace",
        "born_on": "1990-12-10", "gender": "f", "email": "ada@example.com", "phone_number": "+14155550123",
    }
    data.update(over)
    return data
