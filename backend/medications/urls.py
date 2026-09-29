"""Medication & health-tracking routing (Stage 4.6).

Mounted under ``/api/`` by ``config/urls.py``. Endpoint surface follows the
approved api-design §08 endpoint matrix (see 4.6-discrepancies.md for the
missing-``v1`` namespace note):

    GET/POST            /api/medications/
    GET/PATCH/DELETE    /api/medications/{uid}/          (DELETE is soft)
    GET/POST            /api/medications/{uid}/schedule/
    PATCH/DELETE        /api/medications/{uid}/schedule/{schedule_uid}/
    POST                /api/medications/{uid}/log-dose/
    GET                 /api/medications/{uid}/events/
    GET                 /api/medications/stats/
    GET/POST            /api/symptoms/
    GET                 /api/symptom-types/
    GET                 /api/health-timeline/
"""

from rest_framework.routers import DefaultRouter

from medications import views

router = DefaultRouter()
router.register("medications", views.MedicationViewSet, basename="medication")
router.register("symptoms", views.SymptomViewSet, basename="symptom")
router.register("symptom-types", views.SymptomTypeViewSet, basename="symptom-type")
router.register("health-timeline", views.HealthTimelineViewSet, basename="health-timeline")

urlpatterns = router.urls