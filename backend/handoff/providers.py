"""Vendor hand-off links: searches that finish on the vendor's own site.

Search-result deep links are used only where the URL format is a documented,
stable pattern (Kayak, Booking.com, Expedia, Google Flights). Airlines and
rental brands link to their site root: a deep link that 404s is worse than one
extra tap. Keeping this server-side means a broken pattern is fixed with a
deploy, not an app release.
"""
from urllib.parse import quote, urlencode

AIRLINES = {
    "DL": ("Delta Air Lines", "https://www.delta.com"),
    "UA": ("United Airlines", "https://www.united.com"),
    "AA": ("American Airlines", "https://www.aa.com"),
    "WN": ("Southwest Airlines", "https://www.southwest.com"),
    "B6": ("JetBlue", "https://www.jetblue.com"),
    "AS": ("Alaska Airlines", "https://www.alaskaair.com"),
    "NK": ("Spirit Airlines", "https://www.spirit.com"),
    "F9": ("Frontier Airlines", "https://www.flyfrontier.com"),
    "HA": ("Hawaiian Airlines", "https://www.hawaiianairlines.com"),
    "AC": ("Air Canada", "https://www.aircanada.com"),
    "BA": ("British Airways", "https://www.britishairways.com"),
    "LH": ("Lufthansa", "https://www.lufthansa.com"),
    "AF": ("Air France", "https://www.airfrance.com"),
    "KL": ("KLM", "https://www.klm.com"),
    "EK": ("Emirates", "https://www.emirates.com"),
    "QR": ("Qatar Airways", "https://www.qatarairways.com"),
}
DEFAULT_AIRLINES = ["DL", "UA", "AA", "WN"]

RENTAL_BRANDS = [
    ("hertz", "Hertz", "https://www.hertz.com"),
    ("enterprise", "Enterprise", "https://www.enterprise.com"),
    ("avis", "Avis", "https://www.avis.com"),
    ("national", "National", "https://www.nationalcar.com"),
    ("budget", "Budget", "https://www.budget.com"),
    ("alamo", "Alamo", "https://www.alamo.com"),
]

HOTEL_BRANDS = [
    ("marriott", "Marriott", "https://www.marriott.com"),
    ("hilton", "Hilton", "https://www.hilton.com"),
    ("hyatt", "Hyatt", "https://www.hyatt.com"),
]


def flights(origin: str, destination: str, depart: str, return_date: str | None, adults: int, airline: str | None):
    path = f"/flights/{origin}-{destination}/{depart}" + (f"/{return_date}" if return_date else "")
    google_query = f"Flights from {origin} to {destination} on {depart}" + (f" through {return_date}" if return_date else "")
    providers = []
    codes = list(DEFAULT_AIRLINES)
    if airline and airline.upper() in AIRLINES:
        code = airline.upper()
        codes = [code] + [c for c in codes if c != code]
    for code in codes:
        name, url = AIRLINES[code]
        providers.append({"id": code.lower(), "name": name, "url": url, "kind": "airline"})
    return [
        {"id": "kayak", "name": "Kayak", "kind": "agency", "url": f"https://www.kayak.com{path}?{urlencode({'adults': adults})}"},
        {"id": "google_flights", "name": "Google Flights", "kind": "agency",
         "url": "https://www.google.com/travel/flights?" + urlencode({"q": google_query}, quote_via=quote)},
        *providers,
    ]


def hotels(destination: str, check_in: str, check_out: str, guests: int):
    return [
        {"id": "kayak", "name": "Kayak", "kind": "agency",
         "url": f"https://www.kayak.com/hotels/{quote(destination, safe='')}/{check_in}/{check_out}/{guests}adults"},
        {"id": "booking_com", "name": "Booking.com", "kind": "agency",
         "url": "https://www.booking.com/searchresults.html?" + urlencode(
             {"ss": destination, "checkin": check_in, "checkout": check_out, "group_adults": guests, "no_rooms": 1})},
        {"id": "expedia", "name": "Expedia", "kind": "agency",
         "url": "https://www.expedia.com/Hotel-Search?" + urlencode(
             {"destination": destination, "startDate": check_in, "endDate": check_out, "adults": guests})},
        *[{"id": key, "name": name, "kind": "hotel", "url": url} for key, name, url in HOTEL_BRANDS],
    ]


def cars(pickup: str, pickup_date: str, dropoff_date: str):
    providers = [{"id": key, "name": name, "kind": "car_rental", "url": url} for key, name, url in RENTAL_BRANDS]
    if len(pickup) == 3 and pickup.isalpha():
        providers.insert(0, {
            "id": "kayak", "name": "Kayak", "kind": "agency",
            "url": f"https://www.kayak.com/cars/{pickup.upper()}/{pickup_date}/{dropoff_date}",
        })
    return providers
