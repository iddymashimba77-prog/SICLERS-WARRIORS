import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models
from django.utils import timezone


class Migration(migrations.Migration):

    dependencies = [
        ("ai_assistant", "0002_seed_ai_permissions"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="Conversation",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("uid", models.UUIDField(db_index=True, default=uuid.uuid4, editable=False, unique=True)),
                ("title", models.CharField(blank=True, max_length=200)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True, db_index=True)),
                ("last_activity_at", models.DateTimeField(db_index=True, default=timezone.now)),
                ("archived", models.BooleanField(default=False)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="ai_conversations", to=settings.AUTH_USER_MODEL)),
            ],
            options={
                "ordering": ["-last_activity_at", "-created_at"],
            },
        ),
        migrations.CreateModel(
            name="Message",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("uid", models.UUIDField(db_index=True, default=uuid.uuid4, editable=False, unique=True)),
                ("role", models.CharField(choices=[("user", "User"), ("assistant", "Assistant")], max_length=20)),
                ("content", models.TextField()),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("meta", models.JSONField(blank=True, default=dict)),
                ("conversation", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="messages", to="ai_assistant.conversation")),
            ],
            options={
                "ordering": ["created_at", "id"],
            },
        ),
        migrations.AddIndex(
            model_name="conversation",
            index=models.Index(fields=["user", "-last_activity_at"], name="ai_assistan_user_id_ae3f22_idx"),
        ),
        migrations.AddIndex(
            model_name="message",
            index=models.Index(fields=["conversation", "created_at"], name="ai_assistan_convers_8f1a44_idx"),
        ),
    ]
