"""Phase 8 — emergencies: requests, responders, access grants."""

from __future__ import annotations

import datetime as _dt

from django.utils import timezone

from emergencies.models import EmergencyAccessGrant, EmergencyRequest, EmergencyResponder
from patients.models import Patient

from .base import TAG, uuid_for

TYPES = ["MEDICAL", "PAIN_CRISIS", "BLOOD", "FALL", "OTHER"]
SEVERITIES = ["NORMAL", "URGENT", "CRITICAL"]
LIVE_STATUSES = ["CREATED", "VALIDATING", "ACTIVE", "RESPONDING", "ESCALATED"]
DONE_STATUSES = ["RESOLVED", "CANCELLED", "EXPIRED"]


def seed(ctx) -> None:
    ctx.log("## Emergencies")
    rng = ctx.rng
    now = timezone.now()
    patients = list(Patient.objects.filter(user__in=ctx.users_of("PATIENT")))
    responders = ctx.users_of("DOCTOR") + ctx.users_of("CAREGIVER") + ctx.users_of("HEALTHCARE_STAFF")
    if not patients or not responders:
        ctx.log("- skipped (need patients + responders)")
        return

    for i, patient in enumerate(patients, start=1):
        if i % 3:
            status = LIVE_STATUSES[i % len(LIVE_STATUSES)]
        else:
            status = DONE_STATUSES[i % len(DONE_STATUSES)]
        created = now - _dt.timedelta(hours=i * 5)
        req, _ = EmergencyRequest.objects.update_or_create(
            uid=uuid_for("emergency", i),
            defaults={
                "requester": patient.user,
                "patient": patient.user,
                "severity": SEVERITIES[i % 3],
                "type": TYPES[i % len(TYPES)],
                "location": {"region": patient.address_region, "city": patient.address_city},
                "description": f"{TAG} synthetic emergency #{i} for QA dispatch flows.",
                "status": status,
                "phone_verified": bool(i % 2),
                "escalated_at": created + _dt.timedelta(minutes=30) if status == "ESCALATED" else None,
                "resolved_by": ctx.admin if status == "RESOLVED" else None,
                "resolved_at": now - _dt.timedelta(hours=2) if status == "RESOLVED" else None,
                "idempotency_key": f"{TAG}-EMG-{i}",
            },
        )
        ctx.track("emergency_requests")

        for k, responder in enumerate(responders[: 1 + (i % 3)]):
            if status in LIVE_STATUSES[:2]:
                r_status = "NOTIFIED"
            elif status in DONE_STATUSES:
                r_status = "DONE" if k == 0 else "DECLINED"
            else:
                r_status = ["ACKNOWLEDGED", "EN_ROUTE", "ARRIVED"][k % 3]
            EmergencyResponder.objects.update_or_create(
                request=req, responder=responder,
                defaults={
                    "responder_role": ["STAFF", "ADMIN", "CAREGIVER", "DONOR", "OTHER"][k % 5],
                    "status": r_status,
                    "notified_at": created + _dt.timedelta(minutes=1),
                    "acknowledged_at": created + _dt.timedelta(minutes=5) if r_status != "NOTIFIED" else None,
                    "arrived_at": created + _dt.timedelta(minutes=20) if r_status in ("ARRIVED", "DONE") else None,
                    "completed_at": created + _dt.timedelta(minutes=50) if r_status == "DONE" else None,
                },
            )
            ctx.track("emergency_responders")

        if i % 4 == 0:
            grantee = responders[i % len(responders)]
            expired = i % 8 == 0
            EmergencyAccessGrant.objects.update_or_create(
                uid=uuid_for("emergency-grant", i),
                defaults={
                    "request": req,
                    "patient": patient.user,
                    "grantee": grantee,
                    "scope": {"fields": ["blood_group", "allergies", "current_medications"]},
                    "reason": f"{TAG} lifesaving access grant.",
                    "authorized_by": patient.user,
                    "expires_at": now - _dt.timedelta(hours=1) if expired else now + _dt.timedelta(hours=6),
                    "status": "EXPIRED" if expired else "ACTIVE",
                },
            )
            ctx.track("emergency_access_grants")

    ctx.log(
        f"- requests={ctx.counts.get('emergency_requests', 0)} "
        f"responders={ctx.counts.get('emergency_responders', 0)} "
        f"grants={ctx.counts.get('emergency_access_grants', 0)}"
    )
