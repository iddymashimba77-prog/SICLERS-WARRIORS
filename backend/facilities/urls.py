"""Facility routing (Stage 4.8).

Mounted under ``/api/`` by ``config/urls.py``:
    GET          /api/facilities/                 public verified list
    GET          /api/facilities/{uid}/           verified detail
    GET/PATCH    /api/facilities/me/              HOSPITAL operator
    POST         /api/admin/facilities/{uid}/verify
"""

from django.urls import path

from facilities import views

app_name = "facilities"

urlpatterns = [
    path("facilities/", views.FacilityListView.as_view(), name="facility-list"),
    path("facilities/me/", views.FacilityMeView.as_view(), name="facility-me"),
    path("facilities/me/verification/", views.FacilityVerificationSubmitView.as_view(), name="facility-me-verification"),
    path("facilities/<uuid:uid>/", views.FacilityDetailView.as_view(), name="facility-detail"),
    path("admin/facilities/", views.AdminFacilityListView.as_view(), name="facility-admin-list"),
    path("admin/facilities/<uuid:uid>/verify", views.FacilityVerifyView.as_view(), name="facility-verify"),
]