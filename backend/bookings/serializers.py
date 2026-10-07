import re

from rest_framework import serializers

E164 = re.compile(r"^\+[1-9]\d{6,14}$")
CABINS = ["economy", "premium_economy", "business", "first"]


class SliceSerializer(serializers.Serializer):
    origin = serializers.RegexField(r"^[A-Za-z]{3}$")
    destination = serializers.RegexField(r"^[A-Za-z]{3}$")
    departure_date = serializers.DateField()

    def validate(self, attrs):
        if attrs["origin"].upper() == attrs["destination"].upper():
            raise serializers.ValidationError("Origin and destination must be different.")
        return attrs


class PassengerCountSerializer(serializers.Serializer):
    adults = serializers.IntegerField(min_value=1, max_value=9, default=1)
    children = serializers.IntegerField(min_value=0, max_value=8, default=0)
    infants = serializers.IntegerField(min_value=0, max_value=4, default=0)

    def validate(self, attrs):
        if attrs["infants"] > attrs["adults"]:
            raise serializers.ValidationError("Each infant needs an adult.")
        if attrs["adults"] + attrs["children"] > 9:
            raise serializers.ValidationError("At most 9 travelers per search.")
        return attrs


class SearchSerializer(serializers.Serializer):
    slices = SliceSerializer(many=True, min_length=1, max_length=4)
    passengers = PassengerCountSerializer(required=False)
    cabin_class = serializers.ChoiceField(choices=CABINS, default="economy")

    def validate(self, attrs):
        attrs.setdefault("passengers", {"adults": 1, "children": 0, "infants": 0})
        return attrs


class IdentityDocumentSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=["passport"])
    unique_identifier = serializers.CharField(max_length=64)
    issuing_country_code = serializers.RegexField(r"^[A-Za-z]{2}$")
    expires_on = serializers.DateField()


class TravelerSerializer(serializers.Serializer):
    id = serializers.CharField(max_length=64)
    title = serializers.ChoiceField(choices=["mr", "mrs", "ms", "miss", "dr"])
    given_name = serializers.CharField(max_length=100)
    family_name = serializers.CharField(max_length=100)
    born_on = serializers.DateField()
    gender = serializers.ChoiceField(choices=["m", "f"])
    email = serializers.EmailField()
    phone_number = serializers.RegexField(E164, error_messages={"invalid": "Use international format, e.g. +14155550123."})
    identity_documents = IdentityDocumentSerializer(many=True, required=False)
    infant_passenger_id = serializers.CharField(max_length=64, required=False)


class CheckoutSerializer(serializers.Serializer):
    expected_total_amount = serializers.DecimalField(max_digits=14, decimal_places=3, required=False)
    expected_total_currency = serializers.RegexField(r"^[A-Za-z]{3}$", required=False)
    passengers = TravelerSerializer(many=True, min_length=1, max_length=9)


class CancelConfirmSerializer(serializers.Serializer):
    cancellation_id = serializers.CharField(max_length=64)
