"""Medication & health business services (approved Stage 4.6).

Pure functions over the approved models — no I/O side effects beyond the
materialized ``health_timeline`` projection (best-effort writes, isolated).

- ``expected_slots``   : authoritative dose-slot generator (schedule × weekday)
                         consumed by adherence stats today and by the future
                         NotificationService reminder job (integration point,
                         FR-APP-002 — NOT implemented here; no push claims).
- ``adherence_stats`` : derived adherence (approved DBD-1 "derived, never
                         stored"); TAKEN / expected × 100, null when there is
                         no schedule data yet.
- ``dashboard``       : aggregate for GET /api/patients/me/dashboard.
- ``record_timeline`` : materializes domain events into health_timeline
                         (approved projection; best-effort, non-blocking).
"""

import datetime
from collections import OrderedDict

from django.db.models import Count
from django.utils import timezone

from medications.models import HealthTimelineEntry, Medication, MedicationEvent, Symptom

WEEKDAY_BY_INDEX = {0: "MON", 1: "TUE", 2: "WED", 3: "THU", 4: "FRI", 5: "SAT", 6: "SUN"}

_STATUS_TO_KEY = {
    "TAKEN": "taken", "MISSED": "missed", "SKIPPED": "skipped", "SNOOZED": "snoozed",
}


def expected_slots(medication, start_dt, end_dt):
    """Yield ``(MedicationSchedule, aware datetime)`` dose slots in
    ``[start_dt, end_dt]`` for a medication's active schedules.

    A dose is expected on every day whose weekday is listed in the schedule's
    ``days_of_week``, at ``time_of_day``. Server timezone (settings.TIME_ZONE)
    is authoritative for adherence windows; the Flutter client renders only.
    """
    for schedule in medication.schedules.all():
        days = set(schedule.days_of_week or [])
        if not days:
            continue
        cursor = start_dt
        while cursor <= end_dt:
            if WEEKDAY_BY_INDEX[cursor.weekday()] in days:
                slot = timezone.make_aware(
                    datetime.datetime.combine(cursor.date(), schedule.time_of_day)
                )
                if schedule.medication.is_active:
                    yield schedule, slot
            cursor += datetime.timedelta(days=1)
    return


def _counts_for_medications(medication_ids, start_dt, end_dt):
    """Aggregate MedicationEvent status counts for many meds in ONE query.

    Returns ``{medication_id: OrderedDict(taken/missed/skipped/snoozed)}``.
    Replaces the previous per-medication ``.count()``/full-row loop (N+1).
    """
    counts = {
        med_id: OrderedDict((s, 0) for s in ("taken", "missed", "skipped", "snoozed"))
        for med_id in medication_ids
    }
    if not medication_ids:
        return counts
    rows = (
        MedicationEvent.objects.filter(
            schedule__medication_id__in=medication_ids,
            created_at__gte=start_dt,
            created_at__lte=end_dt,
        )
        .values("schedule__medication_id", "status")
        .annotate(n=Count("id"))
    )
    for row in rows:
        med_id = row["schedule__medication_id"]
        key = _STATUS_TO_KEY.get(row["status"], "missed")
        counts[med_id][key] += row["n"]
    return counts


def _adherence_block(medication, start_dt, end_dt, counts_map=None):
    expected = sum(1 for _ in expected_slots(medication, start_dt, end_dt))
    if counts_map is None:
        counts_map = _counts_for_medications([medication.pk], start_dt, end_dt)
    counts = counts_map.get(medication.pk, OrderedDict(
        (s, 0) for s in ("taken", "missed", "skipped", "snoozed")
    ))
    taken = counts["taken"]
    adherence_pct = round((taken / expected) * 100, 1) if expected else None
    return {
        "expected": expected,
        "taken": taken,
        "missed": counts["missed"],
        "skipped": counts["skipped"],
        "snoozed": counts["snoozed"],
        "non_adherent": counts["missed"] + counts["skipped"] + counts["snoozed"],
        "adherence_pct": adherence_pct,
    }


def adherence_stats(user, window_days=30):
    """Approved FR-MED-006 GET /api/v1/medications/stats.

    Adherence (derived, not stored): TAKEN ÷ expected_doses × 100 over the
    trailing ``window_days``; null when no schedule data exists yet.
    """
    end_dt = timezone.localtime()
    start_dt = end_dt - datetime.timedelta(days=window_days)
    rollup = {
        "expected": 0, "taken": 0, "missed": 0, "skipped": 0, "snoozed": 0,
        "non_adherent": 0,
    }
    per_medication = []
    medications = list(
        Medication.objects.filter(
            patient=user, deleted_at__isnull=True
        ).prefetch_related("schedules")
    )
    med_ids = [med.pk for med in medications]
    counts_map = _counts_for_medications(med_ids, start_dt, end_dt)
    for med in medications:
        block = _adherence_block(med, start_dt, end_dt, counts_map=counts_map)
        for key in ("expected", "taken", "missed", "skipped", "snoozed", "non_adherent"):
            rollup[key] += block[key]
        per_medication.append({
            "uid": str(med.uid),
            "name": med.name,
            "generic_name": med.generic_name,
            "strength": med.strength,
            "is_active": med.is_active,
            **block,
        })
    rollup["adherence_pct"] = (
        round((rollup["taken"] / rollup["expected"]) * 100, 1)
        if rollup["expected"] else None
    )
    return {
        "window_days": window_days,
        "overall": rollup,
        "per_medication": per_medication,
    }


def dashboard(user):
    """Approved GET /api/v1/patients/me/dashboard (FR-MED-007)."""
    now = timezone.localtime()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = now - datetime.timedelta(days=6)

    active_meds = list(
        Medication.objects.filter(patient=user, deleted_at__isnull=True)
        .prefetch_related("schedules")
    )

    med_summary = []
    doses_today = {"expected": 0, "taken": 0, "pending": 0}
    med_ids = [med.pk for med in active_meds]
    # One grouped query for the whole dashboard instead of one count per med.
    taken_counts = _counts_for_medications(med_ids, today_start, now)
    for med in active_meds:
        slots_today = list(expected_slots(med, today_start, now))
        taken_today = taken_counts[med.pk]["taken"]
        expected_today = len(slots_today)
        pending = max(expected_today - taken_today, 0)
        doses_today["expected"] += expected_today
        doses_today["taken"] += taken_today
        doses_today["pending"] += pending
        med_summary.append({
            "uid": str(med.uid),
            "name": med.name,
            "strength": med.strength,
            "is_active": med.is_active,
            "doses_today": {"expected": expected_today, "pending": pending},
        })

    adherence_7 = _adherence_block_batch(user, active_meds, week_start, now)

    recent_symptoms = [
        {
            "uid": str(s.uid),
            "symptom_type_code": s.symptom_type.code if s.symptom_type else None,
            "symptom_type_name": s.symptom_type.name if s.symptom_type else None,
            "pain_level": s.pain_level,
            "triggers": s.triggers,
            "duration_minutes": s.duration_minutes,
            "recorded_at": s.recorded_at.isoformat(),
        }
        for s in Symptom.objects.filter(patient=user).select_related("symptom_type")[:5]
    ]

    recent_timeline = [
        {
            "event_type": t.event_type,
            "occurred_at": t.occurred_at.isoformat(),
            "summary": t.summary,
            "payload": t.payload,
        }
        for t in HealthTimelineEntry.objects.filter(patient=user)[:10]
    ]

    return {
        "generated_at": now.isoformat(),
        "medications": {
            "active_count": sum(1 for m in active_meds if m.is_active),
            "doses_today": doses_today,
            "list": med_summary,
        },
        "adherence_last_7_days": adherence_7,
        "recent_symptoms": recent_symptoms,
        "recent_timeline": recent_timeline,
    }


def _adherence_block_batch(user, medications, start_dt, end_dt):
    """Roll-up adherence over a batch of already-loaded medications."""
    rollup = {
        "expected": 0, "taken": 0, "missed": 0, "skipped": 0, "snoozed": 0,
        "non_adherent": 0,
    }
    counts_map = _counts_for_medications([med.pk for med in medications], start_dt, end_dt)
    for med in medications:
        block = _adherence_block(med, start_dt, end_dt, counts_map=counts_map)
        for key in ("expected", "taken", "missed", "skipped", "snoozed", "non_adherent"):
            rollup[key] += block[key]
    rollup["adherence_pct"] = (
        round((rollup["taken"] / rollup["expected"]) * 100, 1)
        if rollup["expected"] else None
    )
    return rollup


def record_timeline(patient, event_type, event_id, occurred_at, summary, payload=None):
    """Best-effort materialization into health_timeline (approved projection).

    Never raises: the timeline is derived/denormalized; a failure here must not
    fail the primary domain write. A backfill/rebuild job is documented
    (DBD-2) to recover from any missed event.
    """
    try:
        HealthTimelineEntry.objects.create(
            patient=patient,
            event_type=event_type,
            event_id=event_id,
            occurred_at=occurred_at,
            summary=summary,
            payload=payload or {},
        )
    except Exception:
        pass