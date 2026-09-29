"""Append-only operational audit log (approved §20).

Source of truth — docs/sdlc/03-system-design/database-design.md §20 (lines 420-436):
  audit_logs | id, actor_user_id FK null, action_code, resource_type,
               resource_id bigint null, result CHECK(SUCCESS FAILURE DENIED),
               ip_address, user_agent, request_id UUID, details JSONB,
               created_at  [audit_logs — append-only, no update/delete]

`audit_logs` captures operational access events (consent grants, record reads,
emergency activations, etc.). Auth telemetry lives separately in
`security_events` to keep `audit_logs` clean.
"""

from django.conf import settings
from django.db import models


class AuditLog(models.Model):
    """Append-only operational audit record — immutable by design."""

    RESULT = [
        ("SUCCESS", "SUCCESS"),
        ("FAILURE", "FAILURE"),
        ("DENIED", "DENIED"),
    ]

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="audit_logs",
    )
    action_code = models.CharField(max_length=120, db_index=True)
    resource_type = models.CharField(max_length=60, blank=True)
    resource_id = models.BigIntegerField(null=True, blank=True)
    result = models.CharField(max_length=10, choices=RESULT, default="SUCCESS")
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    request_id = models.UUIDField(null=True, blank=True, db_index=True)
    details = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "audit_logs"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(result__in=["SUCCESS", "FAILURE", "DENIED"]),
                name="audit_result_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["action_code", "-created_at"], name="audit_action_ts_idx"),
            models.Index(fields=["actor", "-created_at"], name="audit_actor_ts_idx"),
        ]

    def __str__(self):
        return f"{self.action_code}:{self.resource_type} [{self.result}]"

    def save(self, *args, **kwargs):
        if self.pk is not None:
            raise ValueError("AuditLog is append-only and cannot be modified.")
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("AuditLog is append-only and cannot be deleted.")
