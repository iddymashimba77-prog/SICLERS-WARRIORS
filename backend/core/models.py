"""Background job queue model (Stage 4.18 — NFR-PERF-004).

Deliberately minimal and dependency-free: a durable, database-backed job row
with a bounded retry loop. Processed by workers invoking the
``core.management.commands.process_jobs`` command (cron/systemd timer); no
Redis, no Celery, no extra runtime dependency.

Safety posture:
* Jobs only ever reference plain identifiers/payloads (never raw PHI). The
  embedded worker runs ANALYTICS-level, administrative or maintenance tasks
  only; anything touching patient data must keep its own authorization.
* Claiming uses ``select_for_update`` inside a transaction so two workers can
  never run the same job row twice (see ``core/jobs.py``).
* A job that keeps failing is ``FAILED`` after ``max_attempts`` (never
  dropped silently, never retried forever).
"""

import uuid

from django.db import models

JOB_STATUSES = [
    ("PENDING", "PENDING"),
    ("RUNNING", "RUNNING"),
    ("SUCCEEDED", "SUCCEEDED"),
    ("FAILED", "FAILED"),
    ("CANCELLED", "CANCELLED"),
]


class BackgroundJob(models.Model):
    """One unit of background work, enqueued by name with a JSON payload."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    task = models.CharField(max_length=120, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    status = models.CharField(
        max_length=12, choices=JOB_STATUSES, default="PENDING", db_index=True,
    )
    attempts = models.PositiveSmallIntegerField(default=0)
    max_attempts = models.PositiveSmallIntegerField(default=3)
    scheduled_for = models.DateTimeField(db_index=True)
    started_at = models.DateTimeField(null=True, blank=True)
    finished_at = models.DateTimeField(null=True, blank=True)
    error = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "core_background_jobs"
        ordering = ["scheduled_for", "-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=["PENDING", "RUNNING", "SUCCEEDED", "FAILED", "CANCELLED"]),
                name="bj_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "scheduled_for"], name="bj_status_sched_idx"),
        ]

    def __str__(self):
        return f"BackgroundJob({self.task}:{self.status})"

class AppBranding(models.Model):
    """Singleton brand configuration for the platform's public face.

    One row (id=1) holding the uploadable platform logo plus its alt text.
    The logo is re-encoded through the same server-side authority used for
    news covers (``content.upload_validation``), so no untrusted bytes are
    ever served back. It is delivered as plain image bytes by the public
    ``/api/branding/logo/`` endpoint so clients (Admin Web, mobile) do not
    depend on MEDIA_URL resolution.

    Safety posture mirrors the rest of the platform: the write surface is
    gated by the seeded ``admin.branding.manage`` code (SUPER_ADMIN only) and
    every change is audited (``branding.*``), with the MFA step-up boundary
    applied before any write.
    """

    logo = models.FileField(upload_to="branding/", blank=True)
    logo_alt = models.CharField(max_length=160, blank=True)
    updated_by = models.ForeignKey(
        "accounts.User",
        null=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "app_branding"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(id=1),
                name="app_branding_singleton_ck",
            ),
        ]

    def __str__(self):
        return "AppBranding(1)"
