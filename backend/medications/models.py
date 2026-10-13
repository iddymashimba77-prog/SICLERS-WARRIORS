"""Medication & health-tracking domain (approved Stage 4.6).

Source of truth — docs/sdlc/03-system-design/database-design.md (§8.3/§8.4):
  medications        | uid, patient_id FK(User), name, generic_name, strength,
                       dosage, route CHECK, frequency, start_date, end_date null,
                       prescribed_by_id FK null, is_active, created_at,
                       updated_at, deleted_at                     [medications]
  medication_schedules | medication_id FK, time_of_day, days_of_week JSONB, notes,
                       created_at, updated_at                     [schedules]
  medication_events  | schedule_id FK, patient_id FK, status
                       CHECK(TAKEN MISSED SKIPPED SNOOZED), taken_at null, note,
                       created_at (immutable; adherence derived)  [events]
  symptoms           | uid, patient_id FK(User), symptom_type_id FK,
                       pain_level smallint CHECK 0..10, triggers JSONB,
                       duration_minutes, notes, recorded_at, created_at
  symptom_types      | code, name, is_pain_related (approved catalog)
  health_timeline    | materialized projection (patient_id, event_type, event_id,
                       occurred_at, summary, payload JSONB); read-only view

Identity is `accounts.User` (AUTH_USER_MODEL); `patient_id` is a FK to that
identity, never an invented separate table (approved 1:1 identity doctrine).

CONFORMANCE NOTE (vs the earlier staged `dose_logs`):
  * Approved row 212 names the adherence table `medication_events` with a FK
    to `medication_schedules.schedule_id` and status vocabulary
    TAKEN/MISSED/SKIPPED/SNOOZED. Stage 4.6 aligns to that: the event is bound
    to a *scheduled dose* (schedule_id), not to the medication directly.
  * `idempotency_key` (unique, nullable) implements the approved §30
    Idempotency-Key contract for POST /medications/{id}/log-dose (dedupe →
    409 IDEMPOTENCY_CONFLICT). It is an implementation artifact of an approved
    API behaviour, not an invented medical field.

OWNERSHIP ("deny by default", Stage 4.4 §18/§19):
  * A User may view/edit only its OWN rows (patient_id == request.user).
  * Medication/health data is Highly Sensitive — never blanket-visible to any
    role. Doctor/caregiver/adherence access is via the approved role+permission+
    relationship+consent gates (C2/C3 — implemented with the consent stage,
    later); until then those conditional cells are DENY by default.
  * Admin roles get NO medical-data access on patient surfaces (C4 audit-only,
    later). medication_events are IMMUTABLE — no delete/update; corrected via
    compensating events (database-design §24: derived adherence).
  * Audit events (SecurityEvent) record the event TYPE only, never payload.

MEDICAL SAFETY: no model here may auto-prescribe, auto-change dosing, infer
diagnosis, or recommend treatment (§ 4.6 medical safety). Tracking is for
recording/monitoring/reminding/visualizing only.
"""

import uuid

from django.conf import settings
from django.db import models


class TimestampedModel(models.Model):
    """Approved audit fields for health data (§ DB design timestamps)."""

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        abstract = True


class SymptomType(models.Model):
    """Approved symptom catalog (§ database-design 8.1 — no invented entries)."""

    code = models.CharField(max_length=40, unique=True)
    name = models.CharField(max_length=120)
    is_pain_related = models.BooleanField(default=False)

    class Meta:
        db_table = "symptom_types"
        ordering = ["code"]

    def __str__(self):
        return self.code


class Medication(TimestampedModel):
    """A patient's medication record (§ medications; 1 patient → many)."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="medications",
    )
    name = models.CharField(max_length=150)
    generic_name = models.CharField(max_length=150, blank=True)
    strength = models.CharField(max_length=50, blank=True)  # e.g. "500 mg"
    dosage = models.CharField(max_length=120, blank=True)
    route = models.CharField(
        max_length=40,
        choices=[("ORAL", "ORAL"), ("TOPICAL", "TOPICAL"), ("INHALED", "INHALED"),
                 ("INJECTION", "INJECTION"), ("SUBLINGUAL", "SUBLINGUAL"),
                 ("SUPPOSITORY", "SUPPOSITORY"), ("OTHER", "OTHER")],
        default="ORAL",
    )
    frequency = models.CharField(max_length=40)  # free text (no approved enum)
    # The prescriber's directions to the patient ("take with food", "avoid
    # alcohol"). Kept separate from `MedicationSchedule.notes`, which describes a
    # single reminder time rather than the medicine as a whole.
    instructions = models.TextField(blank=True)
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    prescribed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="prescribed_medications",
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "medications"
        ordering = ["-created_at"]
        constraints = [
            # Server-side guard for invalid date ranges (§4.2/§9 validation).
            models.CheckConstraint(
                condition=models.Q(end_date__isnull=True) | models.Q(end_date__gte=models.F("start_date")),
                name="meds_end_after_start_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["patient", "is_active"], name="meds_patient_active_idx"),
            models.Index(fields=["patient", "start_date"], name="meds_patient_start_idx"),
            models.Index(fields=["start_date", "end_date"], name="meds_start_end_idx"),
        ]

    def __str__(self):
        return f"{self.name} ({self.patient.email})"


class MedicationSchedule(TimestampedModel):
    """Per-medication reminder schedule (§ medication_schedules)."""

    DAYS = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    medication = models.ForeignKey(
        Medication, on_delete=models.CASCADE, related_name="schedules"
    )
    time_of_day = models.TimeField()
    days_of_week = models.JSONField(default=list)  # subset of DAYS
    notes = models.TextField(blank=True)

    class Meta:
        db_table = "medication_schedules"
        ordering = ["time_of_day"]
        indexes = [
            models.Index(fields=["medication", "time_of_day"], name="medschedule_med_tod_idx"),
        ]

    def __str__(self):
        return f"{self.medication.name} {self.time_of_day:%H:%M}"


class MedicationEvent(models.Model):
    """Adherence event — a recorded dose outcome (§ medication_events row 212).

    IMMUTABLE by design: clients POST recorded events; the server never
    rewrites/deletes an event after creation (corrected via compensating
    events). Adherence statistics are DERIVED from these rows, never stored.
    """

    STATUS = [
        ("TAKEN", "TAKEN"),
        ("MISSED", "MISSED"),
        ("SKIPPED", "SKIPPED"),
        ("SNOOZED", "SNOOZED"),
    ]

    schedule = models.ForeignKey(
        MedicationSchedule, on_delete=models.PROTECT, related_name="events"
    )
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="medication_events"
    )
    status = models.CharField(max_length=20, choices=STATUS)
    taken_at = models.DateTimeField(null=True, blank=True)
    note = models.CharField(max_length=300, blank=True)
    # Idempotency-Key (approved §30): duplicate key → 409, no double count.
    idempotency_key = models.CharField(max_length=120, null=True, blank=True, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "medication_events"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=["TAKEN", "MISSED", "SKIPPED", "SNOOZED"]),
                name="medevent_status_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(taken_at__isnull=False) | ~models.Q(status="TAKEN"),
                name="medevent_taken_at_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["patient", "-created_at"], name="medevent_patient_idx"),
            models.Index(fields=["schedule", "-created_at"], name="medevent_schedule_idx"),
        ]

    def __str__(self):
        return f"{self.patient.email} {self.status} {self.created_at:%Y-%m-%d %H:%M}"


class Symptom(TimestampedModel):
    """Recorded health event — pain/symptom tracking (§ symptoms)."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="symptoms"
    )
    symptom_type = models.ForeignKey(
        SymptomType, null=True, on_delete=models.PROTECT, related_name="symptoms"
    )
    pain_level = models.PositiveSmallIntegerField(
        null=True, blank=True,
        validators=[models.fields.validators.MinValueValidator(0),
                    models.fields.validators.MaxValueValidator(10)],
    )
    triggers = models.JSONField(default=list, blank=True)
    duration_minutes = models.PositiveIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True)
    recorded_at = models.DateTimeField()

    class Meta:
        db_table = "symptoms"
        ordering = ["-recorded_at"]
        indexes = [
            models.Index(fields=["patient", "-recorded_at"], name="symptoms_patient_ts_idx"),
            models.Index(fields=["symptom_type"], name="symptoms_type_idx"),
        ]

    def __str__(self):
        return f"{self.patient.email} {self.symptom_type_id} {self.recorded_at:%Y-%m-%d}"


class HealthTimelineEntry(TimestampedModel):
    """Materialized health timeline projection (§ health_timeline).

    Populated from domain events (medication started/stopped, dose logged,
    symptom/pain recorded). Reads are cheap; a rebuild/backfill job is
    documented (DBD-2) — this is NOT a second full copy of the data.
    """

    EVENT_TYPES = [
        ("MED_STARTED", "MED_STARTED"),
        ("MED_STOPPED", "MED_STOPPED"),
        ("DOSE_TAKEN", "DOSE_TAKEN"),
        ("DOSE_MISSED", "DOSE_MISSED"),
        ("DOSE_SKIPPED", "DOSE_SKIPPED"),
        ("DOSE_SNOOZED", "DOSE_SNOOZED"),
        ("SYMPTOM_RECORDED", "SYMPTOM_RECORDED"),
        ("PAIN_RECORDED", "PAIN_RECORDED"),
    ]
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="health_timeline"
    )
    event_type = models.CharField(max_length=40, choices=EVENT_TYPES)
    event_id = models.UUIDField()
    occurred_at = models.DateTimeField()
    summary = models.CharField(max_length=255)
    payload = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "health_timeline"
        ordering = ["-occurred_at"]
        indexes = [
            models.Index(fields=["patient", "-occurred_at"], name="timeline_patient_ts_idx"),
        ]

    def __str__(self):
        return f"{self.patient.email} {self.event_type} {self.occurred_at:%Y-%m-%d}"