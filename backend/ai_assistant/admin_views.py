"""Admin AI monitoring (Stage 4.16 §20).

    GET /api/admin/ai/monitoring/   admin.audit.read (SUP/ADM)

Read-only operational aggregates over the append-only audit trail — request
volume, refusal/safety blocks, provider failures, denied use, unique users.

Privacy (per stage mandate): NO conversation text, NO context payload, NO user
content is aggregated or returned. Only action-code counters over the audit
meta. No new analytics engine is introduced — the audit trail is the source.
"""

from datetime import timedelta

from django.db.models import Count
from django.utils import timezone
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import permissions, status as http_status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsAuthenticatedRespectStatus
from audit.models import AuditLog

# Action codes written by the 4.15 AI assistant (services.py).
AI_REQUEST = "ai.request"
AI_COMPLETED = "ai.completed"
AI_SAFETY_BLOCK = "ai.safety_block"
AI_PROVIDER_FAILURE = "ai.provider_failure"
AI_USE_DENIED = "ai.use_denied"
AI_TRENDS = "ai.trends"
AI_TRENDS_DENIED = "ai.trends_denied"
AI_CODES = {
    AI_REQUEST, AI_COMPLETED, AI_SAFETY_BLOCK, AI_PROVIDER_FAILURE,
    AI_USE_DENIED, AI_TRENDS, AI_TRENDS_DENIED,
}


class AdminAiMonitoringAccess(permissions.BasePermission):
    """admin.audit.read + status gate + MFA boundary."""

    message = "You do not have permission to view AI monitoring."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("admin.audit.read"):
            return False
        from accounts.mfa import MfaPolicy

        return MfaPolicy().is_compliant(request, user)


@extend_schema(responses={200: OpenApiTypes.OBJECT})
class AdminAiMonitoringView(APIView):
    permission_classes = [IsAuthenticatedRespectStatus, AdminAiMonitoringAccess]

    def get(self, request):
        try:
            window_days = int(request.query_params.get("days", "30"))
        except (TypeError, ValueError):
            raise ValidationError({"days": "Must be an integer."})
        if not (1 <= window_days <= 90):
            raise ValidationError({"days": "Use a window between 1 and 90 days."})
        since = timezone.now() - timedelta(days=window_days)

        qs = AuditLog.objects.filter(action_code__in=AI_CODES, created_at__gte=since)
        # ONE grouped query over (action_code, result) instead of six separate
        # .count() scans over the same window (Stage 4.18 N+1-count fix).
        grouped = list(
            qs.values("action_code", "result").annotate(count=Count("id"))
        )
        counts = {(r["action_code"], r["result"]): r["count"] for r in grouped}
        total = sum(counts.values())
        failures = sum(
            n for (_code, result), n in counts.items() if result == "FAILURE"
        )
        denied = sum(n for (_code, result), n in counts.items() if result == "DENIED")
        safety_blocks = sum(
            n for (code, _result), n in counts.items() if code == AI_SAFETY_BLOCK
        )
        provider_failures = sum(
            n for (code, _result), n in counts.items() if code == AI_PROVIDER_FAILURE
        )
        usage_denied = sum(
            n for (code, _result), n in counts.items() if code == AI_USE_DENIED
        )
        unique_users = qs.exclude(actor__isnull=True).values("actor").distinct().count()
        by_action = {
            code: sum(n for (_c, _r), n in counts.items() if _c == code)
            for code in AI_CODES
        }
        by_action = sorted(
            ({"action_code": code, "count": count} for code, count in by_action.items()),
            key=lambda row: row["count"],
            reverse=True,
        )

        total_request_events = total
        payload = {
            "window_days": window_days,
            "generated_at": timezone.now().isoformat(),
            "total_events": total_request_events,
            "successes": max(total_request_events - failures - denied, 0),
            "failures": failures,
            "denied": denied,
            "safety_blocks": safety_blocks,
            "provider_failures": provider_failures,
            "usage_denied": usage_denied,
            "unique_users": unique_users,
            "by_action": by_action,
        }
        return Response(payload, status=http_status.HTTP_200_OK)