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
    path(
        "community/categories/",
        views.ForumCategoryListView.as_view(),
        name="community-category-list",
    ),
    path(
        "community/notifications/",
        views.ForumNotificationListView.as_view(),
        name="community-notification-list",
    ),
    path(
        "community/notifications/unread-count/",
        views.ForumNotificationUnreadCountView.as_view(),
        name="community-notification-unread-count",
    ),
    path(
        "community/notifications/read-all/",
        views.ForumNotificationReadAllView.as_view(),
        name="community-notification-read-all",
    ),
    path(
        "community/notifications/<int:pk>/read/",
        views.ForumNotificationReadView.as_view(),
        name="community-notification-read",
    ),
    path("community/reports/", views.ReportCreateView.as_view(), name="community-report-create"),
]
