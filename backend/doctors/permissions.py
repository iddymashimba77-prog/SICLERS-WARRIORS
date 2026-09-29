"""Chat permission gates (approved §3.17).

Action → approved code map; conversation membership (C13) and message
ownership are enforced at the object/queryset layer. Admin roles hold no
``chat.*`` code, so they are denied every private-conversation surface (§23).
Deny by default.
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus


class ChatAccess(permissions.BasePermission):
    message = "You do not have permission to perform this action."

    # ``None`` = member-scoped: any authenticated participant (membership is
    # enforced by the queryset / object checks in the view).
    _ACTION_CODES = {
        "list": None,
        "retrieve": None,
        "create": "chat.start",
        "messages": None,
        "send": "chat.send",
        "delete_message": "chat.send",
        "read": None,
        "leave": None,
        "add_participant": "chat.start",
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
