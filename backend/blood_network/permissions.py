"""Blood-network permission gates (approved §3.8).

Maps DRF action → approved permission code; ownership/scope rules (C7/C8/C9)
are enforced in the view querysets as well (a role holding the code never
bypasses object-level eligibility). Deny by default: an action without a
mapped code is denied.
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus


class BloodAccess(permissions.BasePermission):
    message = "You do not have permission to perform this action."

    _ACTION_CODES = {
        "list": "blood_requests.view",
        "retrieve": "blood_requests.view",
        "create": "blood_requests.create",
        "cancel": None,  # owner-only, enforced in the view
        "matches": "blood_matches.view",
        "donation_events": None,  # STA/HOS role (C7), enforced in the view
        "verification_queue": "blood_requests.verify",
    }

    def _code_for(self, request, view):
        action = getattr(view, "action", None)
        if action in self._ACTION_CODES:
            return self._ACTION_CODES[action]
        return None

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        code = self._code_for(request, view)
        return code is None or user.has_perm_code(code)