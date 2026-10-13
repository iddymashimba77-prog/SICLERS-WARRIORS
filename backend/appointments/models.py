"""Clinic appointments and follow-up tracking (approved §11).

The clinic surface needs one first-class record so a booked visit, its
outcome, and its follow-up plan are queryable history rather than chat text.
Every row is patient-scoped: `patient` is the subject, `created_by` is who
booked it, so a caregiver acting for a patient is distinguishable from the
patient themselves, and the audit trail records the actor.

Relationship rules (role-perm §20/§24):
* A patient books/cancels their own appointments; a CAREGIVER may book for a
  patient they hold an ACTIVE `Consent` for.
* Clinical staff (DOCTOR / HEALTHCARE_STAFF / HOSPITAL) read and update the
  appointment they are attached to — never the clinical notes of patients they
  have no approved relationship with (object-level scoping in views).
* Appointment notes are clinical data: they are never exposed on the public or
  patient-own serializer.
"""

import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone

APPOINTMENT_TYPES = [
    ("NEW_PATIENT", "New patient consultation"),
    ("FOLLOW_UP", "Follow-up visit"),
    ("ROUTINE_REVIEW", "Routine review"),
    ("LAB_RESULTS", "Laboratory results review"),
    ("MEDICATION_REVIEW", "Medication review"),
    ("VACCINATION", "Vaccination"),
    ("OTHER", "Other"),
]

APPOINTMENT_STATUSES = [
    ("REQUESTED", "Requested"),
    ("CONFIRMED", "Confirmed"),
    ("COMPLETED", "Completed"),
    ("RESCHEDULED", "Rescheduled"),
    ("CANCELLED", "Cancelled"),
    ("NO_SHOW", "No show"),
]

FOLLOW_UP_STATUSES = [
    ("NOT_REQUIRED", "Not required"),
    ("PENDING", "Pending"),
    ("SCHEDULED", "Scheduled"),
    ("COMPLETED", "Completed"),
]

# Only patient-actionable transitions. Clinical completion (COMPLETED) and
# confirmation (CONFIRMED) are performed by the facility/clinic side.
PATIENT_TRANSITIONS = {
    "REQUESTED": {"CANCELLED"},
    "CONFIRMED": {"CANCELLED", "RESCHEDULED"},
    "RESCHEDULED": {"CANCELLED"},
    "COMPLETED": set(),
    "CANCELLED": set(),
    "NO_SHOW": set(),
}


class ClinicAppointment(models.Model):
    """A booked clinic visit with its follow-up plan and reminder settings."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="clinic_appointments",
        help_text="Subject of the visit.",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="booked_appointments",
    )
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="clinic_appointments",
        help_text="Clinic/hospital the visit is booked at.",
    )
    doctor = models.ForeignKey(
        "doctors.Doctor", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="clinic_appointments",
        help_text="Assigned clinician (clinical side confirms).",
    )
    appointment_type = models.CharField(
        max_length=24, choices=APPOINTMENT_TYPES, default="FOLLOW_UP",
    )
    status = models.CharField(
        max_length=16, choices=APPOINTMENT_STATUSES, default="REQUESTED", db_index=True,
    )
    scheduled_at = models.DateTimeField(db_index=True)
    duration_minutes = models.PositiveSmallIntegerField(default=30)
    reason = models.TextField(blank=True, help_text="Why the patient is coming in.")
    notes = models.TextField(blank=True, help_text="Clinical notes — never sent to the patient app.")

    # --- Follow-up (medication review / next visit) -----------------------
    follow_up_required = models.BooleanField(default=False)
    follow_up_due_on = models.DateField(null=True, blank=True)
    follow_up_status = models.CharField(
        max_length=16, choices=FOLLOW_UP_STATUSES, default="NOT_REQUIRED",
    )

    # --- Reminders (Stage 4.12 reminder pipeline) -------------------------
    # Defaults follow the mobile medication form so the two surfaces agree.
    reminder_enabled = models.BooleanField(default=True)
    reminder_days_before = models.JSONField(default=list, blank=True)
    reminder_times = models.JSONField(default=list, blank=True, help_text='["07:00", "19:00"]')
    reminder_channels = models.JSONField(default=list, blank=True, help_text='["in_app", "push"]')
    reminders_sent = models.PositiveIntegerField(default=0)
    last_reminder_sent_at = models.DateTimeField(null=True, blank=True)

    cancellation_reason = models.TextField(blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "clinic_appointments"
        ordering = ["scheduled_at"]
        indexes = [
            models.Index(fields=["patient", "scheduled_at"], name="appt_patient_time_idx"),
            models.Index(fields=["status", "scheduled_at"], name="appt_status_time_idx"),
            models.Index(fields=["doctor", "scheduled_at"], name="appt_doctor_time_idx"),
        ]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=[s for s, _ in APPOINTMENT_STATUSES]),
                name="appt_status_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(follow_up_status__in=[s for s, _ in FOLLOW_UP_STATUSES]),
                name="appt_follow_up_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(appointment_type__in=[t for t, _ in APPOINTMENT_TYPES]),
                name="appt_type_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(duration_minutes__gte=5),
                name="appt_duration_ck",
            ),
        ]

    def __str__(self):
        return f"ClinicAppointment({self.uid}:{self.status}@{self.scheduled_at:%Y-%m-%d %H:%M})"

    def is_past(self) -> bool:
        return self.scheduled_at < timezone.now()

    def reminder_due(self, at=None):
        """Return the reminder datetimes still owed for this appointment.

        A reminder is due when its lead day matches and its time-of-day has
        passed, but only while the appointment is still upcoming and not
        cancelled. The dispatcher calls this once per tick; ``reminders_sent``
        plus ``last_reminder_sent_at`` keeps it idempotent per day.
        """
        if not self.reminder_enabled or self.status in ("CANCELLED", "COMPLETED", "NO_SHOW"):
            return []
        now = at or timezone.now()
        if self.scheduled_at <= now:
            return []
        days_before = self.reminder_days_before if isinstance(self.reminder_days_before, list) else []
        times = self.reminder_times if isinstance(self.reminder_times, list) else []
        channels = self.reminder_channels if isinstance(self.reminder_channels, list) else []
        if not times or not channels:
            return []
        if self.last_reminder_sent_at and self.last_reminder_sent_at.date() == now.date():
            return []
        due = []
        for days in days_before:
            try:
                days = int(days)
            except (TypeError, ValueError):
                continue
            remind_on = (self.scheduled_at - timezone.timedelta(days=days)).date()
            if remind_on != now.date():
                continue
            for raw in times:
                hh, _, mm = str(raw).partition(":")
                try:
                    hour, minute = int(hh), int(mm or 0)
                except (TypeError, ValueError):
                    continue
                slot = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
                if slot <= now and slot > now - timezone.timedelta(hours=12):
                    due.append(slot)
        return due