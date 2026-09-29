"""Adds the professional verification registry (`doctors`, database-design §3.4).

Stage 4.x (AUTH-1). ``doctors`` is the single source of truth for a doctor's
professional verification state (PENDING/APPROVED/REJECTED/SUSPENDED) and gates
``User.is_verified_doctor`` (BR-001). Chat lives in the same ``doctors`` app
but on its own tables; no chat behaviour changes here.
"""

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("doctors", "0002_seed_chat_permissions"),
        ("facilities", "0003_facility_facility_type_ck"),
    ]

    operations = [
        migrations.CreateModel(
            name="Doctor",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID",
                    ),
                ),
                ("license_number", models.CharField(blank=True, max_length=120)),
                (
                    "specialty",
                    models.CharField(
                        blank=True, max_length=120, help_text="Clinical specialty code.",
                    ),
                ),
                ("registration_body", models.CharField(blank=True, max_length=200)),
                (
                    "verification_status",
                    models.CharField(
                        choices=[
                            ("PENDING", "PENDING"),
                            ("APPROVED", "APPROVED"),
                            ("REJECTED", "REJECTED"),
                            ("SUSPENDED", "SUSPENDED"),
                        ],
                        db_index=True,
                        default="PENDING",
                        max_length=16,
                    ),
                ),
                (
                    "verified_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="verified_doctors",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                ("verified_at", models.DateTimeField(blank=True, null=True)),
                ("verification_expires_at", models.DateTimeField(blank=True, null=True)),
                ("rejection_reason", models.TextField(blank=True)),
                ("is_active", models.BooleanField(default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "facility",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="doctors",
                        to="facilities.facility",
                    ),
                ),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="doctor_profile",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddIndex(
            model_name="doctor",
            index=models.Index(
                fields=["verification_status", "created_at"],
                name="doctors_status_created_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="doctor",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("verification_status__in", ["PENDING", "APPROVED", "REJECTED", "SUSPENDED"])
                ),
                name="doctors_verification_status_ck",
            ),
        ),
        migrations.AlterModelTable(
            name="doctor",
            table="doctors",
        ),
    ]