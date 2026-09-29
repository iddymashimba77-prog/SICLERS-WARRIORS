"""AI assistant authorization (role-permission-matrix §3.21).

Only one permission exists in the approved matrix: ``ai.use`` — granted to ALL
roles (A). The assistant therefore never special-cases roles; the *safety layer*
and *privacy layer* (see ``ai_assistant.services`` / ``context``) do the
real gating. This mirrors the analytics pattern (403 + audit on deny).

The trends endpoint is additionally constrained inside the view/service:
only the data owner (self) may be the target — cross-patient use would need the
consent surface, which is not part of the approved 4.15 surface (api-design
AD-2: owner/consent; consent is a separate unbuilt stage). DOC/CAR `C2/3`
grants are therefore not reachable yet (same ODD-8 default as analytics).
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus

DENY_AUDIT_CODE = "ai.use_denied"


class AiUseAccess(permissions.BasePermission):
    """``ai.use`` gate for the assistant chat surface (all roles, A)."""

    message = "You do not have permission to use the AI assistant."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        has_code = user.has_perm_code("ai.use")
        if not has_code:
            from audit.services import record_audit

            record_audit(
                actor=user, action_code=DENY_AUDIT_CODE,
                resource_type="ai", resource_id=None,
                result="DENIED", request=request,
            )
        return has_code