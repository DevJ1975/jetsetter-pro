import uuid

from django.conf import settings
from django.db import models


class Device(models.Model):
    """An anonymous traveler: one install of the app.

    JetSetter Pro has no sign-in. The app registers once, keeps the token in
    the Keychain, and that token is the only thing that can read the bookings
    made from this install.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="device")
    app_version = models.CharField(max_length=32, blank=True)
    platform = models.CharField(max_length=16, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return str(self.id)
