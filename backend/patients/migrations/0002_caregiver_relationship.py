"""Adds the caregiver relationship link (`caregivers`, database-design §8.1).

AUTH-1. The link is the *who*; `consents` (medical_records) provide the
*what* (scope + duration). CAREGIVER role alone grants nothing.
"""

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("patients", "0001_initial"),
        ("accounts", "0003_seed_roles_permissions"),
    ]

    operations = [
        migrations.CreateModel(
            name="CaregiverRelationship",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID",
                    ),
                ),
                (
                    "relationship_type",
                    models.CharField(
                        choices=[
                            ("PARENT", "PARENT"),
                            ("SPOUSE", "SPOUSE"),
                            ("CHILD", "CHILD"),
                            ("SIBLING", "SIBLING"),
                            ("GUARDIAN", "GUARDIAN"),
                            ("FRIEND", "FRIEND"),
                            ("OTHER", "OTHER"),
                        ],
                        max_length=20,
                    ),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("PENDING", "PENDING"),
                            ("ACTIVE", "ACTIVE"),
                            ("REVOKED", "REVOKED"),
                            ("EXPIRED", "EXPIRED"),
                        ],
                        db_index=True,
                        default="PENDING",
                        max_length=10,
                    ),
                ),
                (
                    "patient",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="caregiver_links",
                        to="patients.patient",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="caregiver_relationships",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "invited_by",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="caregiver_invites",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                ("accepted_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddConstraint(
            model_name="caregiverrelationship",
            constraint=models.UniqueConstraint(
                fields=("patient", "user"), name="caregivers_patient_user_uk"
            ),
        ),
        migrations.AddConstraint(
            model_name="caregiverrelationship",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("relationship_type__in", ["PARENT", "SPOUSE", "CHILD", "SIBLING", "GUARDIAN", "FRIEND", "OTHER"])
                ),
                name="caregivers_relationship_type_ck",
            ),
        ),
        migrations.AddConstraint(
            model_name="caregiverrelationship",
            constraint=models.CheckConstraint(
                condition=models.Q(("status__in", ["PENDING", "ACTIVE", "REVOKED", "EXPIRED"])),
                name="caregivers_status_ck",
            ),
        ),
        migrations.AddIndex(
            model_name="caregiverrelationship",
            index=models.Index(fields=["user", "status"], name="caregivers_user_status_idx"),
        ),
        migrations.AlterModelTable(
            name="caregiverrelationship",
            table="caregivers",
        ),
    ]