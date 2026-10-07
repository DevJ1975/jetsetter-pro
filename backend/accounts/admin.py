from django.contrib import admin

from .models import Device


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ("id", "platform", "app_version", "created_at", "last_seen_at")
    readonly_fields = ("id", "user", "created_at", "last_seen_at")
