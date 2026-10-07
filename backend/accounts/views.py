import uuid

from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, authentication_classes, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle

from bookings.services import anonymise_device_bookings

from .models import Device


class RegisterThrottle(AnonRateThrottle):
    scope = "register"


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([RegisterThrottle])
def register(request):
    data = request.data if isinstance(request.data, dict) else {}
    User = get_user_model()
    with transaction.atomic():
        user = User.objects.create(username=f"device-{uuid.uuid4().hex}")
        user.set_unusable_password()
        user.save(update_fields=["password"])
        device = Device.objects.create(
            user=user,
            app_version=str(data.get("app_version", ""))[:32],
            platform=str(data.get("platform", ""))[:16],
        )
        token = Token.objects.create(user=user)
    return Response({"device_id": str(device.id), "token": token.key}, status=status.HTTP_201_CREATED)


@api_view(["DELETE"])
def delete_account(request):
    """Erase this traveler (App Store guideline 5.1.1(v))."""
    user = request.user
    with transaction.atomic():
        anonymise_device_bookings(user)
        user.delete()  # cascades to Device and Token
    return Response(status=status.HTTP_204_NO_CONTENT)
