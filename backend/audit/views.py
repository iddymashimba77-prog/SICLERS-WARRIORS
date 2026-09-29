"""Audit log API views (approved §20 + endpoint-matrix §20, extended 4.16 §21).

Search/filter surface for the append-only audit trail plus a CSV export gated
by ``audit_logs.export`` (seeded SUPER_ADMIN only). No payload, no medical
data, no actor content beyond identity — export records its own audit row.
"""

import csv
from io import StringIO

from django.http import HttpResponse
from rest_framework.exceptions import ValidationError
from rest_framework.generics import ListAPIView
from rest_framework.views import APIView

from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from .models import AuditLog
from .serializers import AuditLogSerializer


def _parse_date(value):
    from datetime import datetime

    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        raise ValidationError({"date": "Use YYYY-MM-DD dates."})


def _audit_queryset(request):
    qs = AuditLog.objects.all()
    params = request.query_params

    action_code = (params.get("action_code") or "").strip()
    if action_code:
        qs = qs.filter(action_code__icontains=action_code)
    resource_type = (params.get("resource_type") or "").strip()
    if resource_type:
        qs = qs.filter(resource_type__icontains=resource_type)
    result = (params.get("result") or "").strip().upper()
    if result:
        if result not in {"SUCCESS", "FAILURE", "DENIED"}:
            raise ValidationError({"result": "Unsupported result."})
        qs = qs.filter(result=result)
    actor = (params.get("actor") or "").strip()
    if actor:
        qs = qs.filter(actor__email__icontains=actor)
    date_from = (params.get("date_from") or "").strip()
    if date_from:
        qs = qs.filter(created_at__date__gte=_parse_date(date_from))
    date_to = (params.get("date_to") or "").strip()
    if date_to:
        qs = qs.filter(created_at__date__lte=_parse_date(date_to))
    return qs


class AuditLogListView(ListAPIView):
    """GET /admin/audit-logs — SUP/ADM oversight (C4). Never exposes payloads.

    4.16 extended filters: action_code, resource_type, result, actor,
    date_from, date_to (search/filter surface for the audit trail).
    """

    serializer_class = AuditLogSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("audit_logs.view")]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        return _audit_queryset(self.request)


class AdminAuditLogExportView(APIView):
    """GET /admin/audit-logs/export/?reason= — CSV export (audit_logs.export).

    SUPER_ADMIN-only (seeded). A reason is mandatory and the export itself is
    appended to the audit trail — an admin cannot export and erase that fact.
    Never includes free-form ``details`` (payload-free by policy).
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("audit_logs.export")]

    def get(self, request):
        from accounts.mfa import MfaPolicy

        if not MfaPolicy().is_compliant(request, request.user):
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Multi-factor authentication is required for this action.")

        reason = (request.query_params.get("reason") or "").strip()
        if len(reason) < 5:
            raise ValidationError({"reason": "A reason is required (min 5 chars)."})

        qs = _audit_queryset(request).select_related("actor").order_by("-created_at")[:5000]
        out = StringIO()
        writer = csv.writer(out)
        writer.writerow(
            ["created_at", "actor_email", "action_code", "resource_type",
             "resource_id", "result", "ip_address", "request_id"]
        )
        for row in qs.iterator(chunk_size=500):
            writer.writerow(
                [
                    row.created_at.isoformat(),
                    row.actor.email if row.actor else "",
                    row.action_code,
                    row.resource_type,
                    row.resource_id,
                    row.result,
                    row.ip_address or "",
                    row.request_id or "",
                ]
            )

        record_audit(
            actor=request.user,
            action_code="audit_logs.export",
            resource_type="audit_logs",
            request=request,
            details={"reason": reason, "rows": qs.count()},
        )

        response = HttpResponse(out.getvalue(), content_type="text/csv")
        response["Content-Disposition"] = 'attachment; filename="audit-log.csv"'
        return response