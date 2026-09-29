"""Append-only operational audit service (approved §20).

Used by blood/emergency flows to record actionable events (create/verify/
reject/cancel/match/respond/donate/escalate/resolve) with minimal, non-PHI
context. `result` reflects the outcome: SUCCESS / FAILURE / DENIED.

The write is deliberately best-effort: an audit failure must never break the
primary business transaction (safety over bookkeeping).
"""

import logging
from uuid import UUID

from .models import AuditLog

logger = logging.getLogger(__name__)


def record_audit(
    *,
    actor=None,
    action_code,
    resource_type="",
    resource_id=None,
    result="SUCCESS",
    request=None,
    details=None,
):
    """Persist one operational audit row. Never raises on failure."""
    try:
        ip_address = None
        user_agent = ""
        request_id = None
        if request is not None:
            meta = getattr(request, "META", {}) or {}
            ip_address = meta.get("REMOTE_ADDR") or None
            user_agent = (meta.get("HTTP_USER_AGENT") or "")[:500]
            cid = getattr(request, "correlation_id", None)
            if cid:
                try:
                    request_id = UUID(cid)
                except (ValueError, TypeError, AttributeError):
                    request_id = None
        AuditLog.objects.create(
            actor=actor,
            action_code=action_code,
            resource_type=resource_type,
            resource_id=resource_id,
            result=result,
            ip_address=ip_address,
            user_agent=user_agent,
            request_id=request_id,
            details=dict(details or {}),
        )
    except Exception:  # pragma: no cover — defensive by contract
        logger.exception("Audit write failed (non-blocking): %s", action_code)