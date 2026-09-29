"""Consent data model (AUTH-1; database-design §9).

The authorization layer for private patient data. Source of truth §9:

  consents | id, uid uuid, patient_profile_id FK (grantor), granted_to_user_id
  FK (grantee), authorized_role_id FK roles null, resource_type CHECK(patients
  medical_records medications symptoms appointments health_timeline emergency),
  resource_ids JSONB null, permission_scope JSONB not null (array of
  `module.resource.action` codes), purpose, start_date/expires_at (expiry
  enforcement server-side), status CHECK(DRAFT ACTIVE REVOKED EXPIRED),
  revoked_by FK null, revoked_at, created_at, updated_at.

Enforcement: at request time the grantee's effective permissions are
intersected with the consent `permission_scope`; expiry/revocation is checked
against the DB clock (role-perm §15, §22). Consent changes/access are always
audited (record_audit + SecurityEvent).
"""

import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class Consent(models.Model):
    RESOURCE_TYPE = [
        ("patients", "patients"),
        ("medical_records", "medical_records"),
        ("medications", "medications"),
        ("symptoms", "symptoms"),
        ("appointments", "appointments"),
        ("health_timeline", "health_timeline"),
        ("emergency", "emergency"),
    ]
    STATUS = [
        ("DRAFT", "DRAFT"),
        ("ACTIVE", "ACTIVE"),
        ("REVOKED", "REVOKED"),
        ("EXPIRED", "EXPIRED"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient_profile = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="consents",
        help_text="Grantor - the patient.",
    )
    granted_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="granted_consents",
        help_text="Grantee - the user receiving access.",
    )
    authorized_role = models.ForeignKey(
        "accounts.Role", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="consents",
        help_text="Context role (e.g. CAREGIVER).",
    )
    resource_type = models.CharField(max_length=30, choices=RESOURCE_TYPE)
    resource_ids = models.JSONField(null=True, blank=True, help_text="Specific record ids when scoped.")
    permission_scope = models.JSONField(
        help_text="Array of `module.resource.action` codes the grant covers.",
    )
    purpose = models.TextField(blank=True, help_text="Purpose limitation.")
    start_date = models.DateTimeField(db_index=True)
    expires_at = models.DateTimeField(db_index=True)
    status = models.CharField(max_length=10, choices=STATUS, default="DRAFT", db_index=True)
    revoked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="revoked_consents",
    )
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "consents"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(resource_type__in=[
                    "patients", "medical_records", "medications", "symptoms",
                    "appointments", "health_timeline", "emergency",
                ]),
                name="consents_resource_type_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=["DRAFT", "ACTIVE", "REVOKED", "EXPIRED"]),
                name="consents_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["granted_to", "status"], name="consents_grantee_status_idx"),
            models.Index(fields=["patient_profile", "status"], name="consents_patient_status_idx"),
        ]

    def __str__(self):
        return f"Consent({self.patient_profile_id}→{self.granted_to_id}:{self.status})"

    def is_active_now(self) -> bool:
        if self.status != "ACTIVE":
            return False
        now = timezone.now()
        if self.expires_at <= now:
            return False
        if self.start_date and self.start_date > now:
            return False
        return True