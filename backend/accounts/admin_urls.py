"""Admin control-plane routing (Stage 4.16 user/security management).

Mounted under the project's ``/api/`` base (same convention as every
implemented stage — the versioned prefix lives in design docs only):

    /api/admin/users/                     (admin.users.manage)
    /api/admin/users/{uid}/activate/      (admin.users.manage)
    /api/admin/users/{uid}/deactivate/    (admin.users.manage)
    /api/admin/users/{uid}/roles/         (admin.users.manage, C17)
    /api/admin/security-events/           (admin.audit.read)
"""

from rest_framework.routers import DefaultRouter

from .admin_views import AdminSecurityEventsView, AdminUsersViewSet
from .roles_views import AdminRoleViewSet

app_name = "admin_control"

router = DefaultRouter()
router.register("admin/users", AdminUsersViewSet, basename="admin-user")
router.register("admin/security-events", AdminSecurityEventsView, basename="admin-security-event")
router.register("admin/roles", AdminRoleViewSet, basename="admin-role")

urlpatterns = router.urls