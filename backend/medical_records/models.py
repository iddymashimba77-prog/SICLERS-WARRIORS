"""Consent + clinical-record data models (AUTH-1; database-design §9).

Two layers live in this app:

1. **Consent** (`consents`) — the authorization layer for private patient data.
2. **Clinical records** (`record_categories`, `clinical_encounters`,
   `medical_records`, `medical_record_files`, `medical_record_links`,
   `medical_record_events`) — the record layer itself, plus the append-only
   history that FR-MEDREC-006 requires.

Consent source of truth §9:

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

CLINICAL RECORD SOURCE OF TRUTH (database-design §9, rows 201-204):

  record_categories    | code, name, description, is_active, sort_order
  clinical_encounters  | uid, patient_id FK, facility_id FK null, doctor_id FK
                       | null, staff_id FK null, encounter_type CHECK,
                       | occurred_at, summary, created_by FK, created_at
  medical_records      | uid, patient_id FK, category_id FK, encounter_id FK
                       | null, title, description, facility_id FK null,
                       | recorded_by FK, recorded_at, status CHECK(ACTIVE
                       | ARCHIVED SUPPRESSED), is_consent_visible bool default
                       | true, created_at, updated_at, deleted_at.
                       | Ownership = patient; authorship = recorded_by.
  medical_record_files | uid, record_id FK, file (storage key), file_name,
                       | content_type, size_bytes, checksum, uploaded_by FK,
                       | uploaded_at. Encrypted-at-rest storage; the stored key
                       | is NEVER rendered as a public URL.
  medical_record_links | per-record visibility override (a derived artifact of
                       | consent): record_id FK, granted_to_user_id FK, scope,
                       | expires_at null, granted_by_patient_id FK, granted_at,
                       | revoked_at null, revoked_by FK null.
  medical_record_events| APPEND-ONLY history (FR-MEDREC-006): uid, record_id
                       | FK null, patient_id FK, actor_id FK null, event_type,
                       | from_status null, to_status null, details JSONB,
                       | occurred_at.

OWNERSHIP / AUTHORSHIP (role-perm §15/§22, §8):
* **Ownership is the patient's** and never transfers. A patient reads and edits
  only their own rows (C16: self-entered entries, soft-delete, own scope).
* **Authorship is `recorded_by`** — the clinical actor who wrote the entry.
  A doctor's entry stays attributed to that doctor even after the doctor leaves
  the platform (C15 attribution requirement).
* Nothing here is publicly readable, and no admin role gets habitual access
  (C4 audit/oversight only, and it still requires a recorded reason).
* `medical_record_events` is append-only in the database layer itself
  (`save()`/`delete()` raise) exactly like `audit.AuditLog` — a history that
  can be rewritten is not a history.
* No model here may auto-diagnose, auto-prescribe, or infer treatment (§4.6
  medical safety). Records record; clinicians interpret.
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

class RecordCategory(models.Model):
    """Approved record-category catalog (database-design §9 — no invented rows)."""

    code = models.CharField(max_length=40, unique=True)
    name = models.CharField(max_length=120)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "record_categories"
        ordering = ["sort_order", "code"]

    def __str__(self):
        return self.code


class ClinicalEncounter(models.Model):
    """A visit that produced one or more records (database-design §9 row 201)."""

    ENCOUNTER_TYPE = [
        ("CONSULTATION", "CONSULTATION"),
        ("CLINIC_VISIT", "CLINIC_VISIT"),
        ("ADMISSION", "ADMISSION"),
        ("DISCHARGE", "DISCHARGE"),
        ("FOLLOW_UP", "FOLLOW_UP"),
        ("TELEHEALTH", "TELEHEALTH"),
        ("LAB_RESULT", "LAB_RESULT"),
        ("PROCEDURE", "PROCEDURE"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="encounters",
    )
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="encounters",
    )
    doctor = models.ForeignKey(
        "doctors.Doctor", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="encounters",
    )
    staff = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="clinical_encounters",
    )
    encounter_type = models.CharField(max_length=24, choices=ENCOUNTER_TYPE, db_index=True)
    occurred_at = models.DateTimeField(db_index=True)
    summary = models.TextField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="authored_encounters",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "clinical_encounters"
        ordering = ["-occurred_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(encounter_type__in=[
                    "CONSULTATION", "CLINIC_VISIT", "ADMISSION", "DISCHARGE",
                    "FOLLOW_UP", "TELEHEALTH", "LAB_RESULT", "PROCEDURE",
                ]),
                name="clinical_encounters_type_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["patient", "-occurred_at"], name="encounters_patient_time_idx",
            ),
        ]

    def __str__(self):
        return f"Encounter({self.uid}:{self.encounter_type})"


class MedicalRecord(models.Model):
    """A clinical record owned by the patient, authored by the clinician (C15)."""

    STATUS = [
        ("ACTIVE", "ACTIVE"),
        ("ARCHIVED", "ARCHIVED"),
        ("SUPPRESSED", "SUPPRESSED"),
    ]
    STATUSES = [value for value, _ in STATUS]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="medical_records",
    )
    category = models.ForeignKey(
        RecordCategory, on_delete=models.PROTECT, related_name="records",
    )
    encounter = models.ForeignKey(
        ClinicalEncounter, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="records",
    )
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="medical_records",
    )
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="recorded_medical_records",
    )
    recorded_at = models.DateTimeField(db_index=True)
    status = models.CharField(max_length=12, choices=STATUS, default="ACTIVE", db_index=True)
    is_consent_visible = models.BooleanField(
        default=True,
        help_text="When false the record stays private to the owner and never "
                  "appears in a consent-derived read set.",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "medical_records"
        ordering = ["-recorded_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=["ACTIVE", "ARCHIVED", "SUPPRESSED"]),
                name="medical_records_status_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["patient", "-recorded_at"], name="med_records_patient_time_idx",
            ),
            models.Index(
                fields=["patient", "status"], name="med_records_patient_status_idx",
            ),
        ]

    def __str__(self):
        return f"MedicalRecord({self.uid}:{self.title})"

    @property
    def is_live(self) -> bool:
        return self.deleted_at is None

    def is_visible_to_grantee(self) -> bool:
        """Consent-derived visibility for a non-owner clinical reader.

        ``SUPPRESSED`` is the patient's own "keep this but do not share" mark and
        ``is_consent_visible=False`` is the per-record opt-out. Neither is
        negotiable by the grantee: only the owner can change them.
        """
        return (
            self.is_live
            and self.status != "SUPPRESSED"
            and self.is_consent_visible
        )


class MedicalRecordFile(models.Model):
    """Encrypted-at-rest attachment. The storage key is never a public URL."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    record = models.ForeignKey(
        MedicalRecord, on_delete=models.CASCADE, related_name="files",
    )
    file = models.FileField(upload_to="medical_records/files/", max_length=300)
    file_name = models.CharField(max_length=255)
    content_type = models.CharField(max_length=120)
    size_bytes = models.PositiveIntegerField(default=0)
    checksum = models.CharField(
        max_length=64, blank=True,
        help_text="SHA-256 of the stored bytes; proves the file is unaltered.",
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="uploaded_record_files",
    )
    uploaded_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "medical_record_files"
        ordering = ["-uploaded_at"]

    def __str__(self):
        return f"RecordFile({self.uid}:{self.file_name})"


class MedicalRecordLink(models.Model):
    """Per-record visibility override handed out by the patient (C2/C3)."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    record = models.ForeignKey(
        MedicalRecord, on_delete=models.CASCADE, related_name="links",
    )
    granted_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="medical_record_links",
    )
    scope = models.CharField(
        max_length=40, default="view",
        help_text="Least privilege the patient granted on this specific record.",
    )
    expires_at = models.DateTimeField(null=True, blank=True, db_index=True)
    granted_by_patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="record_links",
    )
    granted_at = models.DateTimeField(auto_now_add=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="revoked_record_links",
    )

    class Meta:
        db_table = "medical_record_links"
        ordering = ["-granted_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["record", "granted_to"], name="med_record_links_record_user_uk",
            ),
        ]

    def __str__(self):
        return f"RecordLink({self.record_id}→{self.granted_to_id})"

    def is_active_now(self) -> bool:
        if self.revoked_at is not None:
            return False
        return self.expires_at is None or self.expires_at > timezone.now()


class AppendOnlyEventQuerySet(models.QuerySet):
    """Refuses bulk mutation of the history table.

    `Model.save()`/`delete()` guards alone are not enough: `QuerySet.update()`
    and `QuerySet.delete()` bypass the instance methods entirely, so a single
    `.filter(...).delete()` in any view or management command would quietly
    rewrite the audit trail. Both are closed here.
    """

    def delete(self):
        raise ValueError("MedicalRecordEvent is append-only and cannot be deleted.")

    def update(self, **kwargs):
        raise ValueError("MedicalRecordEvent is append-only and cannot be modified.")


class MedicalRecordEventManager(models.Manager.from_queryset(AppendOnlyEventQuerySet)):
    pass


class MedicalRecordEvent(models.Model):
    """APPEND-ONLY history for a clinical record (FR-MEDREC-006).

    Every create, edit, status change, file change, soft delete, and every
    *read* of a highly sensitive record lands here as well as in `audit_logs`.
    `save()`/`delete()` refuse to mutate an existing row, so history cannot be
    rewritten by application code, an admin, or a bug.
    """

    EVENT_TYPE = [
        ("CREATED", "CREATED"),
        ("UPDATED", "UPDATED"),
        ("STATUS_CHANGED", "STATUS_CHANGED"),
        ("FILE_ATTACHED", "FILE_ATTACHED"),
        ("FILE_REMOVED", "FILE_REMOVED"),
        ("DELETED", "DELETED"),
        ("VIEWED", "VIEWED"),
        ("DOWNLOADED", "DOWNLOADED"),
        ("ACCESS_DENIED", "ACCESS_DENIED"),
        ("SHARED", "SHARED"),
        ("SHARE_REVOKED", "SHARE_REVOKED"),
    ]
    EVENT_TYPES = [value for value, _ in EVENT_TYPE]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    record = models.ForeignKey(
        MedicalRecord, null=True, blank=True,
        # PROTECT, not SET_NULL: history that loses its subject when the subject
        # is removed is not a history. Clinical records are soft-deleted, so this
        # also makes a hard delete of a chart entry impossible.
        on_delete=models.PROTECT, related_name="history",
    )
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="record_history",
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="medical_record_events",
    )
    event_type = models.CharField(max_length=24, choices=EVENT_TYPE, db_index=True)
    from_status = models.CharField(max_length=12, blank=True)
    to_status = models.CharField(max_length=12, blank=True)
    details = models.JSONField(
        default=dict, blank=True,
        help_text="Non-PHI context only (field names, file names, counts).",
    )
    occurred_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "medical_record_events"
        ordering = ["-occurred_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(event_type__in=[
                    "CREATED", "UPDATED", "STATUS_CHANGED", "FILE_ATTACHED",
                    "FILE_REMOVED", "DELETED", "VIEWED", "DOWNLOADED",
                    "ACCESS_DENIED", "SHARED", "SHARE_REVOKED",
                ]),
                name="medical_record_events_type_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["record", "-occurred_at"], name="med_rec_events_record_idx",
            ),
            models.Index(
                fields=["patient", "-occurred_at"], name="med_rec_events_patient_idx",
            ),
        ]

    objects = MedicalRecordEventManager()

    def __str__(self):
        return f"RecordEvent({self.uid}:{self.event_type})"

    def save(self, *args, **kwargs):
        if self.pk is not None:
            raise ValueError("MedicalRecordEvent is append-only and cannot be modified.")
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("MedicalRecordEvent is append-only and cannot be deleted.")
