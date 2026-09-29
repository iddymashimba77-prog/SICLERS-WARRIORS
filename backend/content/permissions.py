"""Content CMS permission gates (least privilege).

Approved admin grant:
    content.news.manage   -> SUPER_ADMIN, ADMIN
    content.ticker.manage -> SUPER_ADMIN, ADMIN

Every CMS read/write sits behind one of these two codes (mirror of the seeded
role-permission matrix in migration 0002). The public news / ticker endpoints
are ``AllowAny`` but serve PUBLISHED / ACTIVE rows only — existence of a draft
is never observable from the anonymous surface.
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus


class _ContentAdminAccess(permissions.BasePermission):
    message = "You do not have permission to perform this action."

    code = None

    def has_permission(self, request, view):
        if not self.code:
            return False
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        return user.has_perm_code(self.code)


class ContentNewsAccess(_ContentAdminAccess):
    """News CMS surface — ``content.news.manage`` (SUPER_ADMIN/ADMIN)."""

    code = "content.news.manage"


class ContentTickerAccess(_ContentAdminAccess):
    """Top ticker surface — ``content.ticker.manage`` (SUPER_ADMIN/ADMIN)."""

    code = "content.ticker.manage"