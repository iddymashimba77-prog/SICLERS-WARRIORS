"""Community routing (Stage 4.10). Mounted under ``/api/`` by config/urls.py."""

from django.urls import path
from rest_framework.routers import DefaultRouter

from community import views

router = DefaultRouter()
router.register("community/posts", views.CommunityPostViewSet, basename="community-post")
router.register("admin/community/reports", views.AdminReportViewSet, basename="community-admin-report")

urlpatterns = router.urls + [
    path(
        "community/posts/<uuid:uid>/comments/",
        views.CommentListCreateView.as_view(),
        name="community-comment-list",
    ),
    path(
        "community/posts/<uuid:uid>/comments/<int:pk>/",
        views.CommentDetailView.as_view(),
        name="community-comment-detail",
    ),
    path("community/reports/", views.ReportCreateView.as_view(), name="community-report-create"),
]
