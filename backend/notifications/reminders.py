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

Appointment reminders (T-1d / T-2h, deployment-design line 456) are gated on
the appointment domain model, which is not yet implemented in this codebase;
this module is their future home.
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