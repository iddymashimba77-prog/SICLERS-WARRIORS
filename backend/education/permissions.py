"""Education permission gates (approved role-permission-matrix §3.16).

Public reads: ``education.view`` is granted to every role and the category /
content read endpoints are Public per api-endpoint-matrix §18 (FR-EDU-002);
they return PUBLISHED content only. Writing DRAFTs requires ``education.publish``
(DOC/ORG = conditional C12, SUP/ADM); moderation/review requires
``education.review`` (SUP/ADM only). Object-level author checks are enforced in
the view on top of these gates — a role holding ``education.publish`` never
bypasses ownership rules.
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus


class EducationAccess(permissions.BasePermission):
    message = "You do not have permission to perform this action."

    # ``list`` / ``retrieve`` are PUBLIC per api-endpoint-matrix §18; every
    # other action requires auth + an approved code.
    _ACTION_CODES = {
        "list": "__public__",
        "retrieve": "__public__",
        "create": "education.publish",
        "update": "education.publish",
        "partial_update": "education.publish",
        "destroy": "education.publish",
        "submit": "education.publish",
    }

    def _code_for(self, view):
        return self._ACTION_CODES.get(getattr(view, "action", None), "__deny__")

    def has_permission(self, request, view):
        code = self._code_for(view)
        if code == "__public__":
            # Public read: no account-state gate, but never returns non-published
            # rows (queryset enforces that).
            return True
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if code == "__deny__":
            return False
        return user.has_perm_code(code)


class AdminEducationAccess(permissions.BasePermission):
    """Admin review surface — ``education.review`` (SUP/ADM) only."""

    message = "You do not have permission to perform this action."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        return user.has_perm_code("education.review")