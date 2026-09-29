"""Notification routing (Stage 4.8 + 4.13).

Mounted under ``/api/`` by ``config/urls.py``:
    GET            /api/notifications/
    GET            /api/notifications/unread-count/
    GET            /api/notifications/{id}/
    POST           /api/notifications/{id}/read/
    POST           /api/notifications/read-all/
    GET/PATCH      /api/notifications/preferences/
    POST/GET       /api/notifications/devices/
    DELETE         /api/notifications/devices/{id}/

The static ``preferences`` and ``devices`` paths must precede the ``{id}``
detail route so they never resolve as a notification id.
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from notifications import views
from notifications.admin_views import AdminBroadcastView

urlpatterns = [
    path("admin/notifications/broadcast/", AdminBroadcastView.as_view(), name="admin-notification-broadcast"),
    path("notifications/preferences/", views.NotificationPreferencesView.as_view(), name="notification-preferences"),
    path("notifications/devices/", views.PushDeviceListCreateView.as_view(), name="notification-devices"),
    path("notifications/devices/<int:pk>/", views.PushDeviceDetailView.as_view(), name="notification-device-detail"),
]

router = DefaultRouter()
router.register("notifications", views.NotificationViewSet, basename="notification")

urlpatterns += router.urls