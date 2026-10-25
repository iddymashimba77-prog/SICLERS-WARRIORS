"""AI assistant endpoint routing (project ``/api/`` convention).

Maps the approved API-design AD-2 surface under the same ``/api/`` base used
by every implemented stage (NOT ``/api/v1`` — the versioned prefix exists in
design docs but every implemented stage follows the established project
convention; documented in the 4.15 implementation note).

    /api/ai/chat/               POST  (ai.use)
    /api/ai/trends/<uuid>/      GET   (ai.use + analytics.health_trends, owner)
    /api/ai-assistant/conversations/        GET/POST (own history)
    /api/ai-assistant/conversations/<uid>/  GET/PATCH/DELETE (own history)
    /api/ai-assistant/conversations/<uid>/messages/  POST (own history)
    /api/admin/ai/monitoring/   GET   (admin.audit.read — SUP/ADM oversight)
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views
from .admin_views import AdminAiMonitoringView

app_name = "ai_assistant"

router = DefaultRouter()
router.register(
    r"ai-assistant/conversations",
    views.ConversationViewSet,
    basename="ai-assistant-conversations",
)

urlpatterns = [
    path("ai/chat/", views.AiChatView.as_view(), name="ai-chat"),
    path("ai/trends/<uuid:patient_uid>/", views.AiTrendsView.as_view(), name="ai-trends"),
    path("admin/ai/monitoring/", AdminAiMonitoringView.as_view(), name="admin-ai-monitoring"),
    path("", include(router.urls)),
]
