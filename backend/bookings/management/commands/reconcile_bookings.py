"""Run hourly (Railway cron): close abandoned checkouts and list bookings that need a human."""
from django.core.management.base import BaseCommand

from bookings import services
from bookings.models import Booking


class Command(BaseCommand):
    help = "Expire abandoned checkouts and report bookings flagged for attention."

    def handle(self, *args, **options):
        expired = services.expire_stale_bookings()
        self.stdout.write(f"expired {expired} abandoned checkout(s)")
        flagged = Booking.objects.filter(needs_attention=True)
        for b in flagged:
            self.stdout.write(self.style.WARNING(f"ATTENTION {b.id} [{b.status}] {b.attention_note}"))
        self.stdout.write(f"{flagged.count()} booking(s) need attention")
