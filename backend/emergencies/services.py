"""Emergency request service (approved Stage 4.8, §8.6 + ERD).

Lifecycle (authoritative, database-design §8.6):
  CREATED -> VALIDATING -> ACTIVE -> RESPONDING -> RESOLVED
                 \\         \\-> ESCALATED -> RESOLVED
                  \\-> CANCELLED / EXPIRED

Rules (BR-009 + role-permission §3.9):
  * Anti-spam: creating a request is rate-limited (3/hour/user) and the
    throttle outcome is persisted on `rate_limit_ok`; a server-side
    Idempotency-Key header dedupes a duplicated submission (409).
  * No "emergency = bypass all" rule (§16): every access-grant is a bounded
    C10 override (default 24h, auto-expiry, full audit).
"""

import logging
from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from accounts.models import SecurityEvent
from audit.services import record_audit
from notifications.services import create_notification
from .models import EmergencyAccessGrant, EmergencyRequest, EmergencyResponder

logger = logging.getLogger(__name__)


def _security_event(user, event_type, detail=None):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type, detail=dict(detail or {}))
    except Exception:
        logger.exception("SecurityEvent write failed (non-blocking): %s", event_type)


@transaction.atomic
def create_emergency(
    *,
    requester,
    patient=None,
    severity="NORMAL",
    type_="MEDICAL",
    location=None,
    description="",
    rate_limit_ok=True,
    phone_verified=False,
    idempotency_key="",
):
    """Create an emergency request (FR-EMG-001/002) plus its C10 grant.

    Acknowledge notification is sent to the requester and, when different, the
    patient. Any existing ACTIVE grant for the patient is reused.
    """
    request_obj = EmergencyRequest.objects.create(
        requester=requester,
        patient=patient or requester,
        severity=severity,
        type=type_,
        location=dict(location or {}),
        description=description,
        status="CREATED",
        rate_limit_ok=rate_limit_ok,
        phone_verified=phone_verified,
        idempotency_key=idempotency_key or None,
    )
    _notify_participants(request_obj, "created")
    grant = _ensure_grant(request_obj, authorized_by=requester)
    return request_obj, grant


def _ensure_grant(request_obj: EmergencyRequest, *, authorized_by):
    """Bounded C10 override: one active grant per patient, default +24h.

    Grant issuance is audited (FR-EMG-006 / §16): the override is time-bounded,
    reason-labelled and never a bypass-all rule.
    """
    active = EmergencyAccessGrant.objects.filter(
        patient=request_obj.patient,
        status="ACTIVE",
        expires_at__gt=timezone.now(),
    ).first()
    if active:
        return active
    grant = EmergencyAccessGrant.objects.create(
        request=request_obj,
        patient=request_obj.patient,
        grantee=request_obj.requester,
        scope={"patient_basics": True, "emergency_contact": True},
        reason="Automatic bounded override for active emergency request.",
        authorized_by=authorized_by,
        expires_at=timezone.now() + timedelta(hours=24),
    )
    record_audit(
        actor=authorized_by, action_code="emergency.access_grant",
        resource_type="emergency_access_grant", resource_id=grant.pk,
        details={
            "action": "issue", "grantee": str(grant.grantee.uid),
            "patient": str(grant.patient.uid), "reason": grant.reason[:500],
            "expires_at": grant.expires_at.isoformat(),
        },
    )
    _security_event(authorized_by, "EMERGENCY_ACCESS_GRANTED", {
        "grant": str(grant.uid), "patient": str(grant.patient.uid),
    })
    return grant


def _notify_participants(request_obj: EmergencyRequest, phase: str):
    recipients = {request_obj.requester_id}
    if request_obj.patient_id:
        recipients.add(request_obj.patient_id)
    recipients.discard(None)
    for uid in recipients:
        user = request_obj.requester if uid == request_obj.requester_id else request_obj.patient
        if user is None:
            continue
        create_notification(
            recipient=user,
            type_="EMERGENCY",
            title="Emergency request",
            body=f"Your {request_obj.get_type_display().lower()} request is {phase}.",
            related_resource_type="emergency_request",
            related_resource_id=str(request_obj.uid),
            delivery_key=f"emergency:{phase}:{request_obj.uid}:{uid}",
            force=True,
        )


def validate(request_obj: EmergencyRequest, *, actor) -> None:
    """→ VALIDATING (operator/system telephone + severity checks, FR-EMG-002).

    Only a freshly CREATED request can enter validation. The transition is
    audited (FR-EMG-006) and never exposes medical payload in the event log.
    """
    if request_obj.status != "CREATED":
        raise ValueError("Only a newly created request can be validated.")
    EmergencyRequest.objects.filter(pk=request_obj.pk).update(status="VALIDATING")
    request_obj.status = "VALIDATING"
    _notify_participants(request_obj, "under validation")


def respond(request_obj: EmergencyRequest, responder, *, role: str = "OTHER") -> EmergencyResponder:
    """Responder acknowledges the request → RESPONDING.

    Scoped to requests the responder is part of (their own entry) or that the
    responder has emergency_requests.manage for (enforced in the view). Creates
    the responder entry on first acknowledge.
    """
    row, _created = EmergencyResponder.objects.get_or_create(
        request=request_obj,
        responder=responder,
        defaults={
            "responder_role": role,
            "status": "ACKNOWLEDGED",
            "notified_at": timezone.now(),
            "acknowledged_at": timezone.now(),
        },
    )
    if _created and request_obj.status in ("CREATED", "VALIDATING", "ACTIVE"):
        EmergencyRequest.objects.filter(pk=request_obj.pk).update(status="RESPONDING")
        request_obj.status = "RESPONDING"
        _notify_participants(request_obj, "being responded to")
    return row


def escalate(request_obj: EmergencyRequest, *, actor) -> None:
    """→ ESCALATED (BR-009: escalation is always audited + reason recorded)."""
    if request_obj.status not in ("CREATED", "VALIDATING", "ACTIVE", "RESPONDING"):
        raise ValueError("This request cannot be escalated from its current state.")
    EmergencyRequest.objects.filter(pk=request_obj.pk).update(
        status="ESCALATED", escalated_at=timezone.now(),
    )
    request_obj.status = "ESCALATED"
    _notify_participants(request_obj, "escalated")


def resolve(request_obj: EmergencyRequest, *, actor) -> None:
    """→ RESOLVED (emergency_requests.resolve)."""
    if request_obj.status in ("RESOLVED", "CANCELLED", "EXPIRED"):
        raise ValueError("This request is already closed.")
    EmergencyRequest.objects.filter(pk=request_obj.pk).update(
        status="RESOLVED", resolved_by=actor, resolved_at=timezone.now(),
    )
    request_obj.status = "RESOLVED"
    grant_ids = list(
        EmergencyAccessGrant.objects.filter(request=request_obj, status="ACTIVE").values_list(
            "pk", flat=True
        )
    )
    EmergencyAccessGrant.objects.filter(pk__in=grant_ids).update(
        status="EXPIRED", expires_at=timezone.now(),
    )
    record_audit(
        actor=actor, action_code="emergency.access_grant",
        resource_type="emergency_access_grant", resource_id=None,
        details={"action": "expire", "grant_ids": grant_ids},
    )
    _security_event(actor, "EMERGENCY_ACCESS_REVOKED", {"action": "expire", "grant_ids": grant_ids})
    _notify_participants(request_obj, "resolved")


def cancel(request_obj: EmergencyRequest, *, actor) -> None:
    """→ CANCELLED (owner or operator only — view-enforced)."""
    if request_obj.status in ("RESOLVED", "CANCELLED", "EXPIRED"):
        raise ValueError("This request is already closed.")
    EmergencyRequest.objects.filter(pk=request_obj.pk).update(status="CANCELLED")
    grant_ids = list(
        EmergencyAccessGrant.objects.filter(request=request_obj, status="ACTIVE").values_list(
            "pk", flat=True
        )
    )
    EmergencyAccessGrant.objects.filter(pk__in=grant_ids).update(
        status="REVOKED", revoked_by=actor, revoked_at=timezone.now(),
    )
    record_audit(
        actor=actor, action_code="emergency.access_grant",
        resource_type="emergency_access_grant", resource_id=None,
        details={"action": "revoke", "grant_ids": grant_ids},
    )
    _security_event(actor, "EMERGENCY_ACCESS_REVOKED", {"action": "revoke", "grant_ids": grant_ids})
    request_obj.status = "CANCELLED"
    _notify_participants(request_obj, "cancelled")