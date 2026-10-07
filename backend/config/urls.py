from django.contrib import admin
from django.urls import include, path

from bookings import views as booking_views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health/", booking_views.health),
    path("api/v1/", include("config.api_urls")),
    path("webhooks/stripe/", booking_views.stripe_webhook),
    path("webhooks/duffel/", booking_views.duffel_webhook),
    path("checkout/return/", booking_views.checkout_return),
    path("", include("legal.urls")),
]
