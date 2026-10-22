"""Social-support workspace routing (§3).

Mounted at both ``/api/`` and ``/api/v1/`` by ``config/urls.py``:

    GET    /api/social/caseload/             consented ∪ appointed patients
    GET    /api/social/cases/                consent-scoped case list
    POST   /api/social/cases/                open a case
    GET    /api/social/cases/{uid}/          one case
    PATCH  /api/social/cases/{uid}/          state-machine status transition
    GET    /api/social/cases/{uid}/notes/    notes for one case
    POST   /api/social/cases/{uid}/notes/    add a casework note
    GET    /api/social/needs/                needs assessments (consent-scoped)
    POST   /api/social/needs/                record a needs assessment
    GET    /api/social/referrals/            referrals (consent-scoped)
    POST   /api/social/referrals/            raise a referral
    GET    /api/social/referrals/{uid}/      one referral
    PATCH  /api/social/referrals/{uid}/      status / owner / follow-up
"""

from django.urls import path

from social_work import views

app_name = "social_work"

urlpatterns = [
    path("social/caseload/", views.SocialCaseloadView.as_view(), name="social-caseload"),
    path("social/cases/", views.CaseListCreateView.as_view(), name="social-cases"),
    path("social/cases/<uuid:uid>/", views.CaseDetailView.as_view(), name="social-case-detail"),
    path(
        "social/cases/<uuid:uid>/notes/",
        views.CaseNoteListCreateView.as_view(),
        name="social-case-notes",
    ),
    path("social/needs/", views.NeedsAssessmentListCreateView.as_view(), name="social-needs"),
    path("social/referrals/", views.ReferralListCreateView.as_view(), name="social-referrals"),
    path(
        "social/referrals/<uuid:uid>/",
        views.ReferralDetailView.as_view(),
        name="social-referral-detail",
    ),
]
