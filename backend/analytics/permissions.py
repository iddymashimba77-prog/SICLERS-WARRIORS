"""Analytics authorization (approved role-permission-matrix §3.19).

    analytics.view         SUP/ADM (A), VO (C6)            -> reporting/dashboard
    analytics.health_trends SUP/ADM (C4), PATIENT (A),
                            DOC/CAR (C2/3)                  -> FUTURE / trend endpoint
    analytics.export       SUP (A), ADM (C4)               -> CSV export

C6 (VO scope) is enforced by ``AnalyticsService.allowed_metrics`` — a VO sees
only the verification metric set, never user/donation/community figures.
``analytics.health_trends`` is seeded but has NO endpoint in this stage: the
approved `/ai/trends/{patient_uid}` surface is a design placeholder (AD-2) and
DOC/CAR grants depend on the consent stage (ODD-8 default: patient only).

Deny by default — an authenticated caller without the code is 403 and the
attempt is audited (api-design §37: "403 + audit DENIED").
"""

from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus


class AnalyticsAccess(permissions.BasePermission):
    """``analytics.view`` (SUP/ADM, C6 VO) for the reporting surfaces."""

    message = "You do not have permission to view analytics data."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        has_code = user.has_perm_code("analytics.view")
        if not has_code:
            from audit.services import record_audit

            record_audit(
                actor=user, action_code="analytics.access_denied",
                resource_type="analytics", resource_id=None,
                result="DENIED", request=request,
            )
        return has_code