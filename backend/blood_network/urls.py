"""Blood-network routing (Stage 4.8).

Mounted under ``/api/`` by ``config/urls.py``:
    GET/PATCH   /api/blood/donors/me/
    GET         /api/blood/donors/
    GET/POST    /api/blood/requests/
    GET         /api/blood/requests/{uid}/
    POST        /api/blood/requests/{uid}/cancel/
    GET         /api/blood/requests/{uid}/matches/
    POST        /api/blood/requests/{uid}/donation-events/
    GET         /api/blood/requests/verification-queue/
    POST        /api/blood/matches/{id}/respond/
    POST        /api/admin/blood/requests/{uid}/verify/
    POST        /api/admin/blood/requests/{uid}/reject/
    POST        /api/admin/blood/run-matching/

Request endpoints use the approved uid routing (like medications); the match
respond action uses the numeric match id (matrix ``/blood/matches/{id}/``).
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from blood_network import views

router = DefaultRouter()
router.register("blood/requests", views.BloodRequestViewSet, basename="blood-request")

urlpatterns = router.urls + [
    path("blood/donors/me/", views.BloodDonorMeView.as_view(), name="blood-donor-me"),
    path("blood/donors/", views.BloodDonorListView.as_view(), name="blood-donor-list"),
    path("blood/matches/<int:match_id>/respond/", views.BloodMatchRespondView.as_view(), name="blood-match-respond"),
    path("admin/blood/requests/<uuid:uid>/verify/", views.BloodRequestVerifyView.as_view(), name="blood-request-verify"),
    path("admin/blood/requests/<uuid:uid>/reject/", views.BloodRequestRejectView.as_view(), name="blood-request-reject"),
    path("admin/blood/run-matching/", views.RunMatchingView.as_view(), name="blood-run-matching"),
]