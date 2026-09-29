"""Stage 4.6 alignment to approved model: `medication_events` replaces the
staged `dose_logs`, plus approved timeline/dose vocab, schedules.uid handle
and server-side new-field/constraint guards.

Approved source: database-design.md §8.3 rows 208-222 (medications,
medication_schedules, medication_events, symptom_types.is_pain_related,
health_timeline). 4.6-discrepancies.md documents the divergences resolved here.
"""

import django.core.validators
import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("medications", "0001_initial"),
    ]

    operations = [
        # Stable external handle for schedule create/update/delete operations.
        migrations.AddField(
            model_name="medicationschedule",
            name="uid",
            field=models.UUIDField(
                db_index=True, default=uuid.uuid4, editable=False, unique=True
            ),
        ),
        # Approved catalog marker (database-design ERD: pain-related types).
        migrations.AddField(
            model_name="symptomtype",
            name="is_pain_related",
            field=models.BooleanField(default=False),
        ),
        # Approved dose vocabulary includes SKIPPED/SNOOZED.
        migrations.AlterField(
            model_name="healthtimelineentry",
            name="event_type",
            field=models.CharField(
                choices=[
                    ("MED_STARTED", "MED_STARTED"),
                    ("MED_STOPPED", "MED_STOPPED"),
                    ("DOSE_TAKEN", "DOSE_TAKEN"),
                    ("DOSE_MISSED", "DOSE_MISSED"),
                    ("DOSE_SKIPPED", "DOSE_SKIPPED"),
                    ("DOSE_SNOOZED", "DOSE_SNOOZED"),
                    ("SYMPTOM_RECORDED", "SYMPTOM_RECORDED"),
                    ("PAIN_RECORDED", "PAIN_RECORDED"),
                ],
                max_length=40,
            ),
        ),
        migrations.CreateModel(
            name="MedicationEvent",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("TAKEN", "TAKEN"),
                            ("MISSED", "MISSED"),
                            ("SKIPPED", "SKIPPED"),
                            ("SNOOZED", "SNOOZED"),
                        ],
                        max_length=20,
                    ),
                ),
                ("taken_at", models.DateTimeField(blank=True, null=True)),
                ("note", models.CharField(blank=True, max_length=300)),
                (
                    "idempotency_key",
                    models.CharField(blank=True, max_length=120, null=True, unique=True),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "patient",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="medication_events",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "schedule",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="events",
                        to="medications.medicationschedule",
                    ),
                ),
            ],
            options={
                "db_table": "medication_events",
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddIndex(
            model_name="medicationevent",
            index=models.Index(
                fields=["patient", "-created_at"], name="medevent_patient_idx"
            ),
        ),
        migrations.AddIndex(
            model_name="medicationevent",
            index=models.Index(
                fields=["schedule", "-created_at"], name="medevent_schedule_idx"
            ),
        ),
        migrations.AddConstraint(
            model_name="medicationevent",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("status__in", ["TAKEN", "MISSED", "SKIPPED", "SNOOZED"])
                ),
                name="medevent_status_ck",
            ),
        ),
        migrations.AddConstraint(
            model_name="medicationevent",
            constraint=models.CheckConstraint(
                condition=models.Q(("taken_at__isnull", False))
                | ~models.Q(("status", "TAKEN")),
                name="medevent_taken_at_ck",
            ),
        ),
        # Approved immutable adherence table replaces the staged dose_logs.
        migrations.DeleteModel(name="DoseLog"),
        # Server-side guard for invalid/malicious date ranges.
        migrations.AddConstraint(
            model_name="medication",
            constraint=models.CheckConstraint(
                condition=models.Q(("end_date__isnull", True))
                | models.Q(("end_date__gte", models.F("start_date"))),
                name="meds_end_after_start_ck",
            ),
        ),
    ]