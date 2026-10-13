"""Reminder dispatch jobs (Stage 4.13, FR-NOT-001 / FR-APP-002).

The documented integration point from ``medications/services.py``:
``expected_slots`` is the authoritative dose-slot generator; a periodic job
calls :func:`dispatch_medication_reminders` which turns due slots into inbox
notifications through the central service (never a module-owned provider).

Batching: one reminder per (schedule, day) is coalesced via a stable
``med:reminder:<schedule-uid>:<date>`` delivery key, so running the job
multiple times a day does not create duplicate reminders for earlier slots.
Privacy: reminder bodies are de-identified ("a scheduled dose", never the
medication name) per G4 preview-safety.

Appointment reminders (T-1d / T-2h, deployment-design line 456) are driven by
the per-appointment reminder plan the patient sets when booking
(``ClinicAppointment.reminder_days_before`` / ``reminder_times`` /
``reminder_channels``), so :func:`dispatch_appointment_reminders` honours what
the patient actually asked for instead of a fixed policy. Bodies stay
de-identified (clinic name + time, never the reason or any clinical note) per
G4 preview-safety.
"""

import logging

from django.utils import timezone

from medications.models import Medication
from notifications.models import Notification
from notifications.services import create_notification

logger = logging.getLogger(__name__)


def dispatch_medication_reminders(now=None):
    """Create today's coalesced medication reminders for every active schedule.

    Returns the number of notifications created this run (idempotent — reruns
    for the same day create no duplicate rows thanks to the delivery key).
    """
    now = now or timezone.now()
    if timezone.is_naive(now):
        now = timezone.make_aware(now)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = now.replace(hour=23, minute=59, second=59, microsecond=999999)

    from medications.services import expected_slots

    created = 0
    medications = (
        Medication.objects.filter(deleted_at__isnull=True)
        .select_related("patient")
        .prefetch_related("schedules")
    )
    for med in medications:
        patient = med.patient
        if patient is None or not getattr(patient, "is_active", True):
            continue
        for schedule, slot in expected_slots(med, start, end):
            if slot < start or slot > end:
                continue
            key = f"med:reminder:{schedule.uid}:{slot.date().isoformat()}"
            if Notification.objects.filter(delivery_key=key).exists():
                continue
            create_notification(
                recipient=patient,
                type_="MEDICATION_REMINDER",
                title="Medication reminder",
                body="It's time for a scheduled dose.",
                data={
                    "route": "medication",
                    "resource_type": "medication",
                    "resource_id": str(med.uid),
                },
                related_resource_type="medication",
                related_resource_id=str(med.uid),
                delivery_key=key,
            )
            created += 1
    logger.info("Medication reminders dispatched: %s", created)
    return created

def dispatch_appointment_reminders(now=None, horizon_days=14):
    """Create the clinic-appointment reminders the patients asked for.

    Each appointment carries its own reminder plan (lead days, times-of-day,
    channels). This walks the upcoming window, asks each appointment what it
    owes right now (``ClinicAppointment.reminder_due``), and turns each due
    slot into an inbox notification.

    Idempotency: a per-(appointment, day, slot) delivery key means reruns on
    the same day never duplicate a reminder, and ``reminders_sent`` /
    ``last_reminder_sent_at`` are advanced so the model-level guard and the
    delivery key agree.

    Returns the number of notifications created this run.
    """
    now = now or timezone.now()
    if timezone.is_naive(now):
        now = timezone.make_aware(now)

    from appointments.models import ClinicAppointment

    window_end = now + timezone.timedelta(days=horizon_days)
    created = 0
    appointments = (
        ClinicAppointment.objects.filter(
            reminder_enabled=True,
            scheduled_at__gte=now,
            scheduled_at__lte=window_end,
        )
        .exclude(status__in=["CANCELLED", "COMPLETED", "NO_SHOW"])
        .select_related("patient", "facility")
    )
    for appointment in appointments:
        patient = appointment.patient
        if patient is None or not getattr(patient, "is_active", True):
            continue
        due = appointment.reminder_due(now)
        if not due:
            continue
        for slot in due:
            key = (
                f"appt:reminder:{appointment.uid.hex}:"
                f"{slot.date().isoformat()}:{slot.strftime('%H%M')}"
            )
            if Notification.objects.filter(delivery_key=key).exists():
                continue
            where = appointment.facility.name if appointment.facility else "your clinic"
            when = appointment.scheduled_at
            create_notification(
                recipient=patient,
                type_="APPOINTMENT",
                title="Clinic appointment reminder",
                body=f"You have an appointment at {where} on {when:%d %b %Y at %H:%M}.",
                data={
                    "route": "clinic",
                    "resource_type": "clinic_appointment",
                    "resource_id": str(appointment.uid),
                    "scheduled_at": when.isoformat(),
                },
                related_resource_type="clinic_appointment",
                related_resource_id=str(appointment.uid),
                delivery_key=key,
            )
            created += 1
        # One pass may satisfy several slots; record the newest.
        appointment.reminders_sent += len(due)
        appointment.last_reminder_sent_at = max(
            appointment.last_reminder_sent_at or due[0], due[-1]
        )
        appointment.save(update_fields=["reminders_sent", "last_reminder_sent_at"])

    logger.info("Appointment reminders dispatched: %s", created)
    return created


def dispatch_all_reminders(now=None):
    """Run every reminder producer — the single entry point for the scheduler."""
    return {
        "medication": dispatch_medication_reminders(now=now),
        "appointment": dispatch_appointment_reminders(now=now),
    }
