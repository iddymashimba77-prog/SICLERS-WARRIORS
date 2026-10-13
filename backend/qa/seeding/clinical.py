"""Phase 3 — clinical workflows: appointments, encounters, records, meds, symptoms.

Populates the patient clinical dashboard (medications + adherence + symptoms +
timeline), the clinician-facing records/encounters, the appointment book and a
few doctor–patient chat threads.
"""

from __future__ import annotations

import datetime as _dt
import random

from django.utils import timezone

from appointments.models import ClinicAppointment
from doctors.models import Conversation, ConversationParticipant, Doctor, Message
from medical_records.models import (
    ClinicalEncounter, MedicalRecord, MedicalRecordEvent, RecordCategory,
)
from medications.models import (
    HealthTimelineEntry, Medication, MedicationEvent, MedicationSchedule,
    Symptom, SymptomType,
)
from patients.models import Patient

from .base import MEDICATIONS, MED_NOTES, SYMPTOM_NOTES, TAG, uuid_for

APPT_TYPES = ["NEW_PATIENT", "FOLLOW_UP", "ROUTINE_REVIEW", "LAB_RESULTS", "MEDICATION_REVIEW"]
APPT_STATUSES = ["REQUESTED", "CONFIRMED", "COMPLETED", "RESCHEDULED", "CANCELLED", "NO_SHOW"]
ENCOUNTER_TYPES = ["CONSULTATION", "CLINIC_VISIT", "FOLLOW_UP", "TELEHEALTH", "LAB_RESULT"]
DAYS = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


def _patients(ctx) -> list[Patient]:
    rows = list(Patient.objects.filter(user__in=ctx.users_of("PATIENT")))
    return rows


def _doctors(ctx) -> list[Doctor]:
    return list(Doctor.objects.filter(user__in=ctx.users_of("DOCTOR")))


def _categories() -> list[RecordCategory]:
    cats = list(RecordCategory.objects.all())
    if cats:
        return cats
    fallback = [
        ("LAB_RESULT", "Laboratory Result"), ("IMAGING", "Imaging"),
        ("PRESCRIPTION", "Prescription"), ("CLINICAL_NOTE", "Clinical Note"),
        ("DISCHARGE_SUMMARY", "Discharge Summary"), ("VACCINATION", "Vaccination"),
    ]
    for i, (code, name) in enumerate(fallback):
        RecordCategory.objects.get_or_create(
            code=code, defaults={"name": name, "sort_order": i},
        )
    return list(RecordCategory.objects.all())


def _symptom_types() -> list[SymptomType]:
    types = list(SymptomType.objects.all())
    if types:
        return types
    for code, name, pain in [
        ("PAIN", "Pain", True), ("FEVER", "Fever", False),
        ("FATIGUE", "Fatigue", False), ("HEADACHE", "Headache", True),
        ("BREATHLESSNESS", "Breathlessness", False),
    ]:
        SymptomType.objects.get_or_create(
            code=code, defaults={"name": name, "is_pain_related": pain},
        )
    return list(SymptomType.objects.all())


def seed_appointments(ctx, patients, doctors) -> None:
    rng = ctx.rng
    facilities = ctx.all_facilities()
    now = timezone.now()
    for i, patient in enumerate(patients, start=1):
        for j in range(1, rng.randint(2, 3) + 1):
            doctor = rng.choice(doctors) if doctors else None
            offset = rng.randint(-40, 40)
            scheduled = now + _dt.timedelta(days=offset, hours=rng.randint(0, 6))
            status = rng.choice(APPT_STATUSES)
            if offset > 0:
                status = rng.choice(["REQUESTED", "CONFIRMED", "RESCHEDULED"])
            ClinicAppointment.objects.update_or_create(
                uid=uuid_for("appointment", i, j),
                defaults={
                    "patient": patient.user,
                    "created_by": patient.user,
                    "doctor": doctor,
                    "facility": rng.choice(facilities) if facilities else None,
                    "appointment_type": APPT_TYPES[(i + j) % len(APPT_TYPES)],
                    "status": status,
                    "scheduled_at": scheduled,
                    "duration_minutes": 5 * rng.randint(3, 8),
                    "reminder_days_before": [1],
                    "reminder_times": ["08:00"],
                    "reminder_channels": ["in_app", "push"],
                    "completed_at": now - _dt.timedelta(days=1) if status == "COMPLETED" else None,
                    "cancelled_at": now - _dt.timedelta(days=1) if status == "CANCELLED" else None,
                    "cancellation_reason": "Rescheduled by patient." if status == "CANCELLED" else "",
                },
            )
            ctx.track("appointments")


def seed_encounters_records(ctx, patients, doctors) -> None:
    rng = ctx.rng
    cats = _categories()
    facilities = ctx.all_facilities()
    now = timezone.now()
    for i, patient in enumerate(patients, start=1):
        for j in range(1, rng.randint(1, 2) + 1):
            doctor = rng.choice(doctors) if doctors else None
            occurred = now - _dt.timedelta(days=rng.randint(5, 120))
            encounter, _ = ClinicalEncounter.objects.update_or_create(
                uid=uuid_for("encounter", i, j),
                defaults={
                    "patient": patient,
                    "facility": patient.facility,
                    "doctor": doctor,
                    "encounter_type": ENCOUNTER_TYPES[(i + j) % len(ENCOUNTER_TYPES)],
                    "occurred_at": occurred,
                    "summary": f"{TAG} demo encounter summary #{j}.",
                    "created_by": doctor.user if doctor else ctx.admin,
                },
            )
            ctx.track("encounters")
            for k in range(1, rng.randint(1, 3) + 1):
                cat = rng.choice(cats)
                rec, _ = MedicalRecord.objects.update_or_create(
                    uid=uuid_for("record", i, j, k),
                    defaults={
                        "patient": patient,
                        "category": cat,
                        "encounter": encounter,
                        "title": f"{cats.index(cat)} record — {patient.user.last_name}",
                        "description": f"{TAG} demo clinical record entry.",
                        "facility": encounter.facility,
                        "recorded_by": doctor.user if doctor else ctx.admin,
                        "recorded_at": occurred + _dt.timedelta(hours=j),
                        "status": "ACTIVE",
                        "is_consent_visible": True,
                    },
                )
                MedicalRecordEvent.objects.get_or_create(
                    uid=uuid_for("record-event", i, j, k),
                    defaults={
                        "record": rec,
                        "patient": patient,
                        "actor": doctor.user if doctor else ctx.admin,
                        "event_type": "CREATED",
                        "to_status": "ACTIVE",
                        "details": {"source": TAG},
                    },
                )
                ctx.track("medical_records")


def seed_medications(ctx, patients) -> None:
    rng = ctx.rng
    now = timezone.now()
    for i, patient in enumerate(patients, start=1):
        for j in range(1, rng.randint(1, 2) + 1):
            med_name, generic, strength, dosage = MEDICATIONS[(i + j) % len(MEDICATIONS)]
            start = _dt.date.today() - _dt.timedelta(days=rng.randint(10, 200))
            med, _ = Medication.objects.update_or_create(
                uid=uuid_for("medication", i, j),
                defaults={
                    "patient": patient.user,
                    "name": med_name, "generic_name": generic, "strength": strength,
                    "dosage": dosage, "route": "ORAL",
                    "frequency": "Once daily" if j % 2 else "Twice daily",
                    "start_date": start,
                    "end_date": None if j % 3 else start + _dt.timedelta(days=60),
                    "is_active": j % 4 != 0,
                },
            )
            ctx.track("medications")
            for k, time_of_day in enumerate(
                [(_dt.time(8, 0)), (_dt.time(20, 0))][: 1 if j % 2 else 2], start=1,
            ):
                schedule, _ = MedicationSchedule.objects.update_or_create(
                    uid=uuid_for("medschedule", i, j, k),
                    defaults={
                        "medication": med,
                        "time_of_day": time_of_day,
                        "days_of_week": DAYS,
                        "notes": MED_NOTES[(i + j + k) % len(MED_NOTES)],
                    },
                )
                for d in range(1, rng.randint(3, 8) + 1):
                    status = "TAKEN" if (d + i + j) % 4 else (["MISSED", "SKIPPED", "SNOOZED"][d % 3])
                    taken_at = now - _dt.timedelta(days=d)
                    MedicationEvent.objects.get_or_create(
                        idempotency_key=f"{TAG}-MEDEV-{patient.pk}-{j}-{k}-{d}",
                        defaults={
                            "schedule": schedule,
                            "patient": patient.user,
                            "status": status,
                            "taken_at": taken_at if status == "TAKEN" else None,
                        },
                    )
                    ctx.track("medication_events")
            HealthTimelineEntry.objects.get_or_create(
                event_id=uuid_for("timeline-med", i, j),
                event_type="MED_STARTED",
                patient=patient.user,
                defaults={
                    "occurred_at": timezone.make_aware(
                        _dt.datetime.combine(start, _dt.time(9, 0))
                    ),
                    "summary": f"Started {med_name}",
                    "payload": {"medication": med_name, "source": TAG},
                },
            )


def seed_symptoms(ctx, patients, symptom_types) -> None:
    rng = ctx.rng
    now = timezone.now()
    for i, patient in enumerate(patients, start=1):
        for j in range(1, rng.randint(1, 3) + 1):
            st = rng.choice(symptom_types)
            recorded = now - _dt.timedelta(days=rng.randint(1, 90), hours=rng.randint(0, 12))
            Symptom.objects.update_or_create(
                uid=uuid_for("symptom", i, j),
                defaults={
                    "patient": patient.user,
                    "symptom_type": st,
                    "pain_level": rng.randint(0, 10) if st.is_pain_related else None,
                    "triggers": rng.sample(
                        ["cold", "dehydration", "stress", "infection", "exercise"], 2,
                    ),
                    "duration_minutes": rng.choice([30, 60, 120, 240]),
                    "notes": SYMPTOM_NOTES[(i + j) % len(SYMPTOM_NOTES)],
                    "recorded_at": now - _dt.timedelta(days=1 + j),
                },
            )
            HealthTimelineEntry.objects.get_or_create(
                event_id=uuid_for("timeline-sym", i, j),
                event_type="SYMPTOM_RECORDED",
                patient=patient.user,
                defaults={"occurred_at": now - _dt.timedelta(days=1), "summary": "Symptom recorded"},
            )
            ctx.track("symptoms")


def seed_chat(ctx, patients, doctors) -> None:
    rng = ctx.rng
    patients_u = [p.user for p in patients]
    for i, doctor in enumerate(doctors[:10], start=1):
        patient_user = ctx.users_of("PATIENT")[i - 1]
        conv, _ = Conversation.objects.update_or_create(
            uid=uuid_for("conversation", i),
            defaults={"type": "DOCTOR_PATIENT", "created_by": patient_user, "status": "ACTIVE"},
        )
        ConversationParticipant.objects.get_or_create(
            conversation=conv, user=patient_user,
            defaults={"role_in_chat": "PATIENT"},
        )
        ConversationParticipant.objects.get_or_create(
            conversation=conv, user=doctor.user,
            defaults={"role_in_chat": "DOCTOR"},
        )
        for m in range(1, rng.randint(2, 4) + 1):
            sender = patient_user if m % 2 else doctor.user
            Message.objects.get_or_create(
                uid=uuid_for("message", doctor.pk, m),
                defaults={
                    "conversation": conv,
                    "sender": sender,
                    "content": (
                        "Hello doctor, I have been feeling some pain lately."
                        if sender == patient_user
                        else "Hello, please stay hydrated and take your medication. "
                             "Contact the clinic if the pain worsens."
                    ),
                    "message_type": "TEXT",
                    "status": "DELIVERED",
                },
            )
            ctx.track("messages")
        ctx.track("conversations")


def seed(ctx) -> None:
    ctx.log("## Clinical workflows")
    patients = _patients(ctx)
    doctors = _doctors(ctx)
    seed_appointments(ctx, patients, doctors)
    seed_encounters_records(ctx, patients, doctors)
    seed_medications(ctx, patients)
    seed_symptoms(ctx, patients, _symptom_types())
    seed_chat(ctx, patients, doctors)
    ctx.log(
        f"- appointments={ctx.counts.get('appointments', 0)} "
        f"records={ctx.counts.get('medical_records', 0)} "
        f"medications={ctx.counts.get('medications', 0)} "
        f"symptoms={ctx.counts.get('symptoms', 0)}"
    )
