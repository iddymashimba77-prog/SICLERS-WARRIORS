"""Community permission gates (approved §3.12).

Maps DRF action → approved permission code. Object-level rules (author-only
edit/delete, hide-first moderation) are enforced in the view/service layer on
top of these gates — a role holding a code never bypasses ownership rules.
Deny by default: an action without a mapped code (and not explicitly public to
authenticated users) is denied.
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus


class CommunityAccess(permissions.BasePermission):
    message = "You do not have permission to perform this action."

    # ``None`` means "any authenticated, active user" (public-to-members).
    _ACTION_CODES = {
        "list": None,
        "retrieve": None,
        "create": "community.create_post",
        # Author-only (or moderator) enforced in the view; no extra code.
        "update": None,
        "partial_update": None,
        "destroy": None,
        # Reactions are a member interaction, same bundle as commenting.
        "react": "community.comment",
    }

    def _code_for(self, view):
        return self._ACTION_CODES.get(getattr(view, "action", None), "__deny__")

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        code = self._code_for(view)
        if code == "__deny__":
            return False
        return code is None or user.has_perm_code(code)
