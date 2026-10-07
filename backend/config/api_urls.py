from django.urls import path

from accounts import views as account_views
from bookings import views as booking_views
from handoff import views as handoff_views

urlpatterns = [
    path("config", booking_views.public_config),
    path("devices/register", account_views.register),
    path("account", account_views.delete_account),
    path("flights/search", booking_views.flight_search),
    path("flights/offers/<str:offer_id>", booking_views.flight_offer),
    path("flights/offers/<str:offer_id>/checkout", booking_views.flight_checkout),
    path("bookings", booking_views.booking_list),
    path("bookings/<uuid:booking_id>", booking_views.booking_detail),
    path("bookings/<uuid:booking_id>/cancel/quote", booking_views.cancel_quote),
    path("bookings/<uuid:booking_id>/cancel/confirm", booking_views.cancel_confirm),
    path("handoff/<str:kind>", handoff_views.handoff),
]
