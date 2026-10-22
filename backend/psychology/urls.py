"""Psychology workspace routing (§2).

Mounted at both ``/api/`` and ``/api/v1/`` by ``config/urls.py``:

    GET    /api/psychology/caseload/         consented ∪ appointed patients
    GET    /api/psychology/assessments/      consent-scoped list (+ filters)
    POST   /api/psychology/assessments/      record a structured assessment
    GET    /api/psychology/notes/            consent-scoped session notes
    POST   /api/psychology/notes/            add a session note
    GET    /api/psychology/referrals/        escalations for this psychologist
    POST   /api/psychology/referrals/        raise an escalation
    GET    /api/psychology/referrals/{uid}/  one escalation
    PATCH  /api/psychology/referrals/{uid}/  status / owner / follow-up
"""

from django.urls import path

from psychology import views

app_name = "psychology"

urlpatterns = [
    path("psychology/caseload/", views.CaseloadView.as_view(), name="psychology-caseload"),
    path(
        "psychology/assessments/",
        views.AssessmentListCreateView.as_view(),
        name="psychology-assessments",
    ),
    path(
        "psychology/notes/",
        views.ProgressNoteListCreateView.as_view(),
        name="psychology-notes",
    ),
    path(
        "psychology/referrals/",
        views.ReferralListCreateView.as_view(),
        name="psychology-referrals",
    ),
    path(
        "psychology/referrals/<uuid:uid>/",
        views.ReferralDetailView.as_view(),
        name="psychology-referral-detail",
    ),
]
