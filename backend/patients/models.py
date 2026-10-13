"""Patient profile & medical identity (Stage 4.5).

Source of truth — approved SSoT:
- docs/sdlc/03-system-design/database-design.md row 162 (`patients`, 1:1):
    user_id FK unique (1:1), date_of_birth, gender CHECK, genotype CHECK
    (SS, SC, SBetaThal, SBetaC, unknown), diagnosis_date, primary_diagnosis,
    emergency_contact_name, emergency_contact_phone, emergency_contact_relation,
    address_region, address_city, notes (private), created_at, updated_at,
    deleted_at
- docs/sdlc/03-system-design/erd/patient-medical-erd.md (approved 1:1 set)
- docs/sdlc/03-system-design/role-permission-design.md (ownership §8/§17)

Rules enforced here and at the API layer:
* The `patients` row is 1:1 with the identity (`accounts.User`); profile data
  NEVER merges into `users`. Authentication data stays on `User`, profile data
  lives here (approved architecture, Stage 4.5 §1).
* A user owns ONLY their own row; doctors/caregivers are authorized actors,
  never owners (role-perm §8, §17). Cross-profile access flows through the
  consent/permission architecture (separate, consent-gated surface).
* `notes` is private (owner-only display; audit logs record the event, never
  the medical content — §21).
* Medical vocabulary is intentionally minimal and fixed — no invented fields
  beyond the approved row-162 set.
"""

from django.conf import settings
from django.db import models


class Patient(models.Model):
    """1:1 medical-identity profile for a sickle-cell warrior (row 162)."""

    GENDER = [
        ("FEMALE", "FEMALE"),
        ("MALE", "MALE"),
        ("OTHER", "OTHER"),
        ("UNSPECIFIED", "UNSPECIFIED"),
    ]
    GENOTYPE = [
        ("SS", "SS"),
        ("SC", "SC"),
        ("SBetaThal", "SBetaThal"),
        ("SBetaC", "SBetaC"),
        ("unknown", "unknown"),
    ]

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,  # identity rows are soft-deleted, never removed
        related_name="patient_profile",
    )
    date_of_birth = models.DateField(null=True, blank=True)
    gender = models.CharField(max_length=20, choices=GENDER, null=True, blank=True)
    genotype = models.CharField(max_length=20, choices=GENOTYPE, null=True, blank=True)
    diagnosis_date = models.DateField(null=True, blank=True)
    primary_diagnosis = models.CharField(max_length=255, blank=True)
    emergency_contact_name = models.CharField(max_length=150, blank=True)
    emergency_contact_phone = models.CharField(max_length=30, blank=True)
    emergency_contact_relation = models.CharField(max_length=60, blank=True)
    address_region = models.CharField(max_length=120, blank=True)
    address_city = models.CharField(max_length=120, blank=True)
    # Treating facility: where this warrior receives care. Required at profile
    # completion (§6) and surfaced in patient history/appointments.
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="patients",
        help_text="Clinic/hospital where the patient receives treatment.",
    )
    notes = models.TextField(blank=True)  # private — never surfaced beyond owner
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)  # soft delete (§20)

    class Meta:
        db_table = "patients"
        constraints = [
            models.CheckConstraint(
                name="patients_gender_ck",
                condition=models.Q(gender__in=["FEMALE", "MALE", "OTHER", "UNSPECIFIED"])
                | models.Q(gender__isnull=True),
            ),
            models.CheckConstraint(
                name="patients_genotype_ck",
                condition=models.Q(
                    genotype__in=["SS", "SC", "SBetaThal", "SBetaC", "unknown"]
                )
                | models.Q(genotype__isnull=True),
            ),
        ]

    def __str__(self):
        return f"Patient({self.user.email})"


class CaregiverRelationship(models.Model):
    """Explicit patient→caregiver link (AUTH-1; database-design §8.1 line 163).

    Source of truth::
      caregivers | id, patient_id FK, user_id FK (caregiver account),
      relationship_type CHECK, status CHECK(PENDING ACTIVE REVOKED EXPIRED),
      invited_by FK, accepted_at, created_at, updated_at; UNIQUE(patient_id,
      user_id). Scope/duration/revocation are implemented by `consents`
      (authorization of record) — CAREGIVER role alone grants nothing.

    The relationship is the *who*; `consents` provide the *what* (scope +
    duration). A caregiver only reads patient data when BOTH an ACTIVE link
    and an ACTIVE consent exist (role-perm §10/§15, C14).
    """

    RELATIONSHIP_TYPE = [
        ("PARENT", "PARENT"),
        ("SPOUSE", "SPOUSE"),
        ("CHILD", "CHILD"),
        ("SIBLING", "SIBLING"),
        ("GUARDIAN", "GUARDIAN"),
        ("FRIEND", "FRIEND"),
        ("OTHER", "OTHER"),
    ]
    STATUS = [
        ("PENDING", "PENDING"),
        ("ACTIVE", "ACTIVE"),
        ("REVOKED", "REVOKED"),
        ("EXPIRED", "EXPIRED"),
    ]

    patient = models.ForeignKey(
        Patient, on_delete=models.PROTECT, related_name="caregiver_links",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="caregiver_relationships",
    )
    relationship_type = models.CharField(max_length=20, choices=RELATIONSHIP_TYPE)
    status = models.CharField(max_length=10, choices=STATUS, default="PENDING", db_index=True)
    invited_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="caregiver_invites",
    )
    accepted_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "caregivers"
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["patient", "user"], name="caregivers_patient_user_uk"),
            models.CheckConstraint(
                condition=models.Q(
                    relationship_type__in=[
                        "PARENT", "SPOUSE", "CHILD", "SIBLING", "GUARDIAN", "FRIEND", "OTHER",
                    ]
                ),
                name="caregivers_relationship_type_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=["PENDING", "ACTIVE", "REVOKED", "EXPIRED"]),
                name="caregivers_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "status"], name="caregivers_user_status_idx"),
        ]

    def __str__(self):
        return f"Caregiver({self.user_id}→{self.patient_id}:{self.status})"