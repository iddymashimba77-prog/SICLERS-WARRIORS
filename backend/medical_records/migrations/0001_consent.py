"""Adds the consent authorization registry (`consents`, database-design §9).

AUTH-1. `consents` gate grantee access: effective permissions ∩
permission_scope, expiry/revocation enforced against the DB clock.
"""

import uuid

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("patients", "0002_caregiver_relationship"),
        ("accounts", "0003_seed_roles_permissions"),
    ]

    operations = [
        migrations.CreateModel(
            name="Consent",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID",
                    ),
                ),
                ("uid", models.UUIDField(db_index=True, default=uuid.uuid4, editable=False, unique=True)),
                (
                    "resource_ids",
                    models.JSONField(blank=True, help_text="Specific record ids when scoped.", null=True),
                ),
                (
                    "permission_scope",
                    models.JSONField(
                        help_text="Array of `module.resource.action` codes the grant covers."
                    ),
                ),
                ("purpose", models.TextField(blank=True, help_text="Purpose limitation.")),
                ("start_date", models.DateTimeField(db_index=True)),
                ("expires_at", models.DateTimeField(db_index=True)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("DRAFT", "DRAFT"),
                            ("ACTIVE", "ACTIVE"),
                            ("REVOKED", "REVOKED"),
                            ("EXPIRED", "EXPIRED"),
                        ],
                        db_index=True,
                        default="DRAFT",
                        max_length=10,
                    ),
                ),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "authorized_role",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="consents",
                        to="accounts.role",
                        help_text="Context role (e.g. CAREGIVER).",
                    ),
                ),
                (
                    "granted_to",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="granted_consents",
                        to=settings.AUTH_USER_MODEL,
                        help_text="Grantee - the user receiving access.",
                    ),
                ),
                (
                    "patient_profile",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="consents",
                        to="patients.patient",
                        help_text="Grantor - the patient.",
                    ),
                ),
                (
                    "revoked_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="revoked_consents",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "resource_type",
                    models.CharField(
                        choices=[
                            ("patients", "patients"),
                            ("medical_records", "medical_records"),
                            ("medications", "medications"),
                            ("symptoms", "symptoms"),
                            ("appointments", "appointments"),
                            ("health_timeline", "health_timeline"),
                            ("emergency", "emergency"),
                        ],
                        max_length=30,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddConstraint(
            model_name="consent",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("resource_type__in", ["patients", "medical_records", "medications", "symptoms", "appointments", "health_timeline", "emergency"])
                ),
                name="consents_resource_type_ck",
            ),
        ),
        migrations.AddConstraint(
            model_name="consent",
            constraint=models.CheckConstraint(
                condition=models.Q(("status__in", ["DRAFT", "ACTIVE", "REVOKED", "EXPIRED"])),
                name="consents_status_ck",
            ),
        ),
        migrations.AddIndex(
            model_name="consent",
            index=models.Index(fields=["granted_to", "status"], name="consents_grantee_status_idx"),
        ),
        migrations.AddIndex(
            model_name="consent",
            index=models.Index(fields=["patient_profile", "status"], name="consents_patient_status_idx"),
        ),
        migrations.AlterModelTable(
            name="consent",
            table="consents",
        ),
    ]