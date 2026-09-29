"""Emergency request domain (approved Stage 4.8).

Source of truth:
  docs/sdlc/03-system-design/erd/blood-emergency-erd.md  (ERD lines 77-136)
  docs/sdlc/03-system-design/database-design.md §8.6    (column specs, CHECK values)

CHECK vocabularies:
  emergency_requests.severity  : NORMAL URGENT CRITICAL
  emergency_requests.type      : MEDICAL PAIN_CRISIS BLOOD FALL OTHER
  emergency_requests.status    : CREATED VALIDATING ACTIVE RESPONDING ESCALATED
                                 RESOLVED CANCELLED EXPIRED
  emergency_responders.role    : STAFF ADMIN CAREGIVER DONOR OTHER
  emergency_responders.status  : NOTIFIED ACKNOWLEDGED EN_ROUTE ARRIVED DONE DECLINED
  emergency_access_grants.status: ACTIVE EXPIRED REVOKED

Rate limiting (BR-009):
  create is gated by the `emergency.create_rate_limit` throttle (3/hour/user,
  configured in settings.THROTTLE_RATES). Server-side idempotency key accepted
  via Idempotency-Key header to prevent duplicate submissions.

Ownership model ("deny by default", §18/19):
  * PATIENT/CAREGIVER creates requests (C14: self or authorized patient).
  * Responders (DOC/STA/HOS) manage requests they respond to; admin resolves
    escalated cases.
  * EmergencyAccessGrant is always scoped (C10): bounded override, auto-expiry,
    full audit — no bypass-all rule (§16).

IMMUTABLE: emergency_requests/responders — corrected via compensating status
records (DBD-10).
"""

import uuid

from django.conf import settings
from django.db import models


class EmergencyRequest(models.Model):
    SEVERITY = [
        ("NORMAL", "NORMAL"),
        ("URGENT", "URGENT"),
        ("CRITICAL", "CRITICAL"),
    ]
    TYPE = [
        ("MEDICAL", "MEDICAL"),
        ("PAIN_CRISIS", "PAIN_CRISIS"),
        ("BLOOD", "BLOOD"),
        ("FALL", "FALL"),
        ("OTHER", "OTHER"),
    ]
    STATUS = [
        ("CREATED", "CREATED"),
        ("VALIDATING", "VALIDATING"),
        ("ACTIVE", "ACTIVE"),
        ("RESPONDING", "RESPONDING"),
        ("ESCALATED", "ESCALATED"),
        ("RESOLVED", "RESOLVED"),
        ("CANCELLED", "CANCELLED"),
        ("EXPIRED", "EXPIRED"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="emergency_requests",
    )
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="emergency_requests_as_patient",
        help_text="Patient the emergency is about (if requester is a caregiver/staff).",
    )
    severity = models.CharField(max_length=10, choices=SEVERITY, default="NORMAL")
    type = models.CharField(max_length=14, choices=TYPE)
    location = models.JSONField(default=dict, blank=True)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=16, choices=STATUS, default="CREATED", db_index=True)
    rate_limit_ok = models.BooleanField(default=True)
    phone_verified = models.BooleanField(default=False)
    # Idempotency-Key (approved §30): duplicate submission → 409.
    idempotency_key = models.CharField(max_length=120, null=True, blank=True, unique=True)
    escalated_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="resolved_emergencies",
    )
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "emergency_requests"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=[
                    "CREATED", "VALIDATING", "ACTIVE", "RESPONDING",
                    "ESCALATED", "RESOLVED", "CANCELLED", "EXPIRED",
                ]),
                name="emgreq_status_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(severity__in=["NORMAL", "URGENT", "CRITICAL"]),
                name="emgreq_severity_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(type__in=["MEDICAL", "PAIN_CRISIS", "BLOOD", "FALL", "OTHER"]),
                name="emgreq_type_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "severity", "created_at"], name="emg_status_sev_ts_idx"),
        ]

    def __str__(self):
        return f"Emergency({self.uid}:{self.type}[{self.status}])"


class EmergencyResponder(models.Model):
    ROLE = [
        ("STAFF", "STAFF"),
        ("ADMIN", "ADMIN"),
        ("CAREGIVER", "CAREGIVER"),
        ("DONOR", "DONOR"),
        ("OTHER", "OTHER"),
    ]
    STATUS = [
        ("NOTIFIED", "NOTIFIED"),
        ("ACKNOWLEDGED", "ACKNOWLEDGED"),
        ("EN_ROUTE", "EN_ROUTE"),
        ("ARRIVED", "ARRIVED"),
        ("DONE", "DONE"),
        ("DECLINED", "DECLINED"),
    ]

    request = models.ForeignKey(EmergencyRequest, on_delete=models.CASCADE, related_name="responders")
    responder = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="emergency_responder_entries",
    )
    responder_role = models.CharField(max_length=10, choices=ROLE, default="OTHER")
    status = models.CharField(max_length=12, choices=STATUS, default="NOTIFIED")
    notified_at = models.DateTimeField(null=True, blank=True)
    acknowledged_at = models.DateTimeField(null=True, blank=True)
    arrived_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "emergency_responders"
        constraints = [
            models.UniqueConstraint(fields=["request", "responder"], name="emg_req_resp_uk"),
            models.CheckConstraint(
                condition=models.Q(status__in=[
                    "NOTIFIED", "ACKNOWLEDGED", "EN_ROUTE", "ARRIVED", "DONE", "DECLINED",
                ]),
                name="emgresp_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["responder", "status"], name="emg_resp_status_idx"),
        ]

    def __str__(self):
        return f"Responder({self.request_id}→{self.responder_id}:{self.status})"


class EmergencyAccessGrant(models.Model):
    """C10: Time-bounded emergency override grant (§16 badge — never bypass-all)."""

    STATUS = [
        ("ACTIVE", "ACTIVE"),
        ("EXPIRED", "EXPIRED"),
        ("REVOKED", "REVOKED"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    request = models.ForeignKey(EmergencyRequest, on_delete=models.CASCADE, related_name="access_grants")
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="emergency_grants_as_patient",
    )
    grantee = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="emergency_grants_received",
    )
    scope = models.JSONField(default=dict, blank=True, help_text="Lifesaving subset scope.")
    reason = models.TextField(blank=True)
    authorized_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="authorized_emergency_grants",
    )
    starts_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    status = models.CharField(max_length=10, choices=STATUS, default="ACTIVE")
    revoked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="revoked_emergency_grants",
    )
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "emergency_access_grants"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=["ACTIVE", "EXPIRED", "REVOKED"]),
                name="emggrant_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "expires_at"], name="emggrant_status_exp_idx"),
        ]

    def __str__(self):
        return f"Grant({self.uid}:{self.status})"
