"""Analytics & reporting API views (approved Stage 4.14).

Endpoints (api-design §22 / endpoint-matrix; base is the project ``/api/``
convention used by every implemented stage):

    GET  /api/admin/dashboard/   analytics.view (SUP/ADM, C6 VO)
    GET  /api/admin/analytics/   analytics.view (+ analytics.export for CSV)

Privacy posture (AD-7 / database-design §19):
  * Both surfaces are AGGREGATE-ONLY — the controller never materialises a
    raw domain row; every figure comes from ``analytics_snapshots`` or a
    Count/Sum/Avg query. No PHI appears in any response or export.
  * ``/admin/analytics`` is strictly whitelisted: unknown metric -> 400; a
    known metric outside the caller's scope (VO C6) -> 403 (audited).
  * CSV export is gated by ``analytics.export``: SUPER_ADMIN (A), ADMIN (C4:
    a ``reason`` is required) and every export is audit-logged with its
    filters + row count (admin-web §28).
"""

import csv
import datetime
import io
import json
import logging

from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsAuthenticatedRespectStatus
from audit.services import record_audit

from . import services
from .permissions import AnalyticsAccess
from .serializers import AnalyticsQuerySerializer
from .throttles import AnalyticsReadThrottle

logger = logging.getLogger(__name__)

_MAX_ANALYTICS_DAYS = 366  # NFR-PERF-002: bounded reporting windows.


class AdminDashboardView(APIView):
    """GET /api/admin/dashboard — aggregate KPI cards (role-adaptive)."""

    permission_classes = [IsAuthenticatedRespectStatus, AnalyticsAccess]
    throttle_classes = [AnalyticsReadThrottle]
    parser_classes = [JSONParser]

    def get(self, request):
        payload = services.AnalyticsService().dashboard(request.user)
        return Response(payload)


class AdminAnalyticsView(APIView):
    """GET /api/admin/analytics — aggregate series (+ CSV export)."""

    permission_classes = [IsAuthenticatedRespectStatus, AnalyticsAccess]
    throttle_classes = [AnalyticsReadThrottle]
    parser_classes = [JSONParser]

    def _export_allowed(self, request, reason):
        user = request.user
        if not user.has_perm_code("analytics.export"):
            return False, http_status.HTTP_403_FORBIDDEN, "analytics.export required."
        if "SUPER_ADMIN" in user.role_codes:
            return True, None, ""
        # ADMIN (non-super) with analytics.export -> C4 justification required.
        if not reason:
            return False, http_status.HTTP_400_BAD_REQUEST, (
                "reason is required for export (C4)."
            )
        return True, None, ""

    def get(self, request):
        qs = AnalyticsQuerySerializer(data=request.query_params)
        qs.is_valid(raise_exception=True)
        params = qs.validated_data
        metric = params["metric"]
        granularity = params["granularity"]
        date_from = params.get("date_from")
        date_to = params.get("date_to")

        metric_def = services.METRICS.get(metric)
        if metric_def is None:
            raise ValidationError({"metric": "Unsupported metric."})
        allowed = services.AnalyticsService().metrics_visible(request.user)
        if metric not in allowed:
            record_audit(
                actor=request.user, action_code="analytics.access_denied",
                resource_type="analytics", resource_id=None,
                result="DENIED", request=request,
                details={"metric": metric, "scope": "out_of_scope"},
            )
            raise PermissionDenied("You do not have permission for this metric.")

        if date_from and date_to and date_from > date_to:
            raise ValidationError({"date_from": "Must be before or equal to date_to."})
        if date_from and date_to:
            span = (date_to - date_from).days + 1
            if span > _MAX_ANALYTICS_DAYS:
                raise ValidationError({"date_from": f"Window must not exceed {_MAX_ANALYTICS_DAYS} days."})
        from_dt = timezone.make_aware(
            datetime.datetime.combine(date_from, datetime.time.min)
        ) if date_from else None
        to_dt = timezone.make_aware(
            datetime.datetime.combine(date_to, datetime.time.max)
        ) if date_to else None

        try:
            rows = services.AnalyticsService().series(
                request.user, metric, granularity=granularity,
                date_from=from_dt, date_to=to_dt,
            )
        except ValueError as exc:
            raise ValidationError({"granularity": str(exc)})

        export = (request.query_params.get("export") or "").strip().lower()
        if export == "csv":
            ok, code, message = self._export_allowed(request, params.get("reason", "").strip())
            if not ok:
                if code == http_status.HTTP_400_BAD_REQUEST:
                    raise ValidationError({"reason": message})
                raise PermissionDenied(message)
            csv_text = self._render_csv(metric, granularity, rows)
            record_audit(
                actor=request.user, action_code="analytics.export",
                resource_type="analytics", resource_id=None,
                result="SUCCESS", request=request,
                details={
                    "format": "csv",
                    "metric": metric,
                    "granularity": granularity,
                    "date_from": date_from.isoformat() if date_from else None,
                    "date_to": date_to.isoformat() if date_to else None,
                    "row_count": len(rows),
                    "reason": params.get("reason", "").strip(),
                },
            )
            return Response(
                csv_text, status=http_status.HTTP_200_OK, content_type="text/csv",
            )

        payload = {
            "metric": metric,
            "granularity": granularity,
            "results": rows,
            "count": len(rows),
        }
        return Response(payload)

    def _render_csv(self, metric, granularity, rows) -> str:
        """Aggregate-only CSV — columns are the snapshot fields, never PHI."""
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            ["metric_key", "dimensions", "value", "granularity", "measured_at"]
        )
        for row in rows:
            writer.writerow([
                metric,
                json.dumps(row.get("dimensions") or {}),
                row["value"],
                granularity,
                row.get("period") or row.get("measured_at") or "",
            ])
        return buffer.getvalue()