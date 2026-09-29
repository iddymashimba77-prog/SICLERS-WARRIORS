"""Patient profile endpoint routing (Stage 4.5).

Mounted under ``/api/patients/`` by ``config/urls.py``; follows the approved
endpoint matrix (§4): GET/PATCH ``/patients/me``.
"""

from django.urls import path

from medications.views import PatientDashboardView
from . import views

app_name = "patients"

urlpatterns = [
    path("me/", views.PatientMeView.as_view(), name="me"),
    path("me/dashboard/", PatientDashboardView.as_view({"get": "list"}), name="dashboard"),
]