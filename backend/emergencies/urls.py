"""Emergency routing (Stage 4.8).

Mounted under ``/api/`` by ``config/urls.py``:
    POST        /api/emergency/requests/
    GET         /api/emergency/requests/
    GET         /api/emergency/requests/{uid}/
    POST        /api/emergency/requests/{uid}/validate/
    POST        /api/emergency/requests/{uid}/respond/
    POST        /api/emergency/requests/{uid}/escalate/
    POST        /api/emergency/requests/{uid}/resolve/
    POST        /api/emergency/requests/{uid}/cancel/
    GET         /api/emergency/access-grants/
    GET         /api/admin/emergency/
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from emergencies import views

router = DefaultRouter()
router.register("emergency/requests", views.EmergencyRequestViewSet, basename="emergency-request")
router.register("emergency/access-grants", views.EmergencyAccessGrantViewSet, basename="emergency-access-grant")

urlpatterns = router.urls + [
    path("admin/emergency/", views.EmergencyAdminMonitoringView.as_view(), name="emergency-monitoring"),
]