"""Caregiver relationship routing (AUTH-1). Mounted under ``/api/``.

    GET/POST      /api/caregivers/
    GET/PATCH     /api/caregivers/{id}/permissions/
    POST          /api/caregivers/{id}/accept/
    POST          /api/caregivers/{id}/decline/
    DELETE        /api/caregivers/{id}/
    GET           /api/caregivers/me/patient/
"""

from rest_framework.routers import DefaultRouter

from patients import caregivers_views

router = DefaultRouter()
router.register("caregivers", caregivers_views.CaregiverViewSet, basename="caregiver")

urlpatterns = router.urls