"""Core permission gates.

Only the admin branding surface (Stage 4.31) needs a gate here so far; it
mirrors the CMS pattern (accounts.permissions.IsAuthenticatedRespectStatus +
a seeded code) plus the MFA step-up boundary used by the other admin control
planes (accounts.mfa.MfaPolicy). Deny-by-default: anything without the seeded
``admin.branding.manage`` grant (SUPER_ADMIN only) is refused.
"""

from rest_framework import permissions

from accounts import mfa
from accounts.permissions import IsAuthenticatedRespectStatus


class BrandingAdminAccess(permissions.BasePermission):
    """Branding write surface — ``admin.branding.manage`` (SUPER_ADMIN only)
    + account-status gate + MFA step-up boundary."""

    message = "You do not have permission to modify the platform branding."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("admin.branding.manage"):
            return False
        return mfa.MfaPolicy().is_compliant(request, user)