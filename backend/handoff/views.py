from rest_framework import serializers
from rest_framework.decorators import api_view, throttle_classes
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle

from bookings.errors import APIError

from . import providers


class ReadThrottle(UserRateThrottle):
    scope = "read"


class Airport(serializers.RegexField):
    def __init__(self, **kwargs):
        super().__init__(r"^[A-Za-z]{3}$", **kwargs)

    def to_internal_value(self, data):
        return super().to_internal_value(data).upper()


class FlightQuery(serializers.Serializer):
    origin = Airport()
    destination = Airport()
    depart = serializers.DateField()
    # `return` is a Python keyword, so the query key is read manually below.
    adults = serializers.IntegerField(min_value=1, max_value=9, default=1)
    airline = serializers.RegexField(r"^[A-Za-z0-9]{2}$", required=False)


class HotelQuery(serializers.Serializer):
    destination = serializers.CharField(max_length=100)
    check_in = serializers.DateField()
    check_out = serializers.DateField()
    guests = serializers.IntegerField(min_value=1, max_value=9, default=1)

    def validate(self, attrs):
        if attrs["check_out"] <= attrs["check_in"]:
            raise serializers.ValidationError("Check-out must be after check-in.")
        return attrs


class CarQuery(serializers.Serializer):
    pickup = serializers.CharField(max_length=100)
    pickup_date = serializers.DateField()
    dropoff_date = serializers.DateField()

    def validate(self, attrs):
        if attrs["dropoff_date"] <= attrs["pickup_date"]:
            raise serializers.ValidationError("Drop-off must be after pickup.")
        return attrs


@api_view(["GET"])
@throttle_classes([ReadThrottle])
def handoff(request, kind):
    q = request.query_params
    if kind == "flights":
        s = FlightQuery(data=q)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        return_raw = q.get("return")
        return_date = None
        if return_raw:
            field = serializers.DateField()
            return_date = field.run_validation(return_raw)
            if return_date < d["depart"]:
                raise serializers.ValidationError({"return": ["Return must be on or after departure."]})
            return_date = return_date.isoformat()
        items = providers.flights(d["origin"], d["destination"], d["depart"].isoformat(), return_date,
                                  d["adults"], d.get("airline"))
    elif kind == "hotels":
        s = HotelQuery(data=q)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        items = providers.hotels(d["destination"], d["check_in"].isoformat(), d["check_out"].isoformat(), d["guests"])
    elif kind == "cars":
        s = CarQuery(data=q)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        items = providers.cars(d["pickup"], d["pickup_date"].isoformat(), d["dropoff_date"].isoformat())
    else:
        raise APIError("not_found", "Unknown hand-off type.", 404)
    return Response({"providers": items})
