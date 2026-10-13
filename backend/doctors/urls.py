"""Chat + doctor registry routing (Stage 4.10 + AUTH-1). Mounted under ``/api/``.

Chat:
    /chat/conversations/                      (router)
Doctor registry (database-design §3.4, endpoint-matrix §5):
    GET/PATCH   /doctors/me/
    POST        /doctors/me/verification/
    GET         /doctors/
    GET         /doctors/{uid}/
    GET         /admin/doctors/verification-queue/
    POST        /admin/doctors/{uid}/verify/
    POST        /admin/doctors/{uid}/suspend/
    POST        /admin/doctors/{uid}/reinstate/
    GET         /doctors/{uid}/verification-history/     own trail or C6 reviewer
    GET         /admin/doctors/verification-history/    C6 reviewer, whole registry
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from doctors import views

router = DefaultRouter()
router.register("chat/conversations", views.ConversationViewSet, basename="chat-conversation")

urlpatterns = router.urls + [
    path(
        "chat/conversations/<uuid:conv_uid>/messages/<uuid:uid>/",
        views.MessageDeleteView.as_view(),
        name="chat-message-delete",
    ),
    path("doctors/me/", views.DoctorMeView.as_view(), name="doctor-me"),
    path(
        "doctors/me/verification/",
        views.DoctorVerificationSubmitView.as_view(),
        name="doctor-verification-submit",
    ),
    path("doctors/", views.DoctorDirectoryListView.as_view(), name="doctor-directory"),
    path("doctors/<uuid:uid>/", views.DoctorDirectoryDetailView.as_view(), name="doctor-directory-detail"),
    path(
        "admin/doctors/verification-queue/",
        views.AdminDoctorVerificationQueueView.as_view(),
        name="admin-doctor-verification-queue",
    ),
    path("admin/doctors/<uuid:uid>/verify/", views.AdminDoctorVerifyView.as_view(), name="admin-doctor-verify"),
    path("admin/doctors/<uuid:uid>/suspend/", views.AdminDoctorSuspendView.as_view(), name="admin-doctor-suspend"),
    path(
        "admin/doctors/<uuid:uid>/reinstate/",
        views.AdminDoctorReinstateView.as_view(),
        name="admin-doctor-reinstate",
    ),
    path(
        "admin/doctors/verification-history/",
        views.AdminDoctorVerificationHistoryView.as_view(),
        name="admin-doctor-verification-history",
    ),
    path(
        "doctors/<uuid:uid>/verification-history/",
        views.DoctorVerificationHistoryView.as_view(),
        name="doctor-verification-history",
    ),
]