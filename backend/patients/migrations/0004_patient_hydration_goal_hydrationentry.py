import django.core.validators
import django.db.models.deletion
import django.utils.timezone
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("patients", "0003_patient_facility"),
    ]

    operations = [
        migrations.AddField(
            model_name="patient",
            name="hydration_goal_ml",
            field=models.PositiveIntegerField(
                blank=True,
                help_text="Optional personal daily fluid goal in millilitres.",
                null=True,
                validators=[
                    django.core.validators.MinValueValidator(250),
                    django.core.validators.MaxValueValidator(6000),
                ],
            ),
        ),
        migrations.CreateModel(
            name="HydrationEntry",
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
                    "uid",
                    models.UUIDField(
                        db_index=True, default=uuid.uuid4, editable=False, unique=True
                    ),
                ),
                (
                    "amount_ml",
                    models.PositiveIntegerField(
                        validators=[
                            django.core.validators.MinValueValidator(1),
                            django.core.validators.MaxValueValidator(3000),
                        ]
                    ),
                ),
                (
                    "recorded_at",
                    models.DateTimeField(
                        db_index=True, default=django.utils.timezone.now
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "patient",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="hydration_entries",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "hydration_entries",
                "ordering": ["-recorded_at"],
                "indexes": [
                    models.Index(
                        fields=["patient", "-recorded_at"],
                        name="hydration_patient_ts_idx",
                    )
                ],
            },
        ),
    ]
