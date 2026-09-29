"""Audit log serializer — exposes timestamps, actor, action, result (no payload)."""

from rest_framework import serializers

from .models import AuditLog


class AuditLogSerializer(serializers.ModelSerializer):
    actor_email = serializers.EmailField(source="actor.email", read_only=True)

    class Meta:
        model = AuditLog
        fields = [
            "id", "actor_email", "action_code", "resource_type", "resource_id",
            "result", "ip_address", "request_id", "created_at",
        ]
        read_only_fields = fields