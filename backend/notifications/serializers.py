"""Notification serializers (recipient scope; Stage 4.8 + 4.13)."""

from rest_framework import serializers

from .models import Notification, NotificationPreference, PushDevice


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            "id", "type", "priority", "channel", "title", "body", "data",
            "related_resource_type", "related_resource_id",
            "status", "read_at", "sent_at", "created_at",
        ]
        read_only_fields = fields


class PreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationPreference
        fields = ["category", "enabled", "updated_at"]
        read_only_fields = ["category", "updated_at"]


class PreferencesListSerializer(serializers.Serializer):
    """GET /notifications/preferences → {category: enabled} map (FR-NOT-006)."""

    preferences = serializers.DictField(allow_empty=True)

    def to_representation(self, instance):
        enabled = {
            pref.category: pref.enabled
            for pref in NotificationPreference.objects.filter(user=instance)
        }
        return {"preferences": enabled}


class PreferenceUpdateSerializer(serializers.Serializer):
    category = serializers.ChoiceField(choices=[t for t, _ in Notification.TYPE])
    enabled = serializers.BooleanField()

    def validate(self, attrs):
        # Safety (BR-009 / §3.9.4): emergency can never be muted by the user.
        # Enforced again at the service layer; this is defense in depth.
        if attrs["category"] == "EMERGENCY" and not attrs["enabled"]:
            raise serializers.ValidationError(
                {"category": "Emergency notifications cannot be disabled."}
            )
        return attrs

    def save(self, *, user):
        pref, _ = NotificationPreference.objects.get_or_create(
            user=user, category=self.validated_data["category"],
        )
        pref.enabled = self.validated_data["enabled"]
        pref.save(update_fields=["enabled", "updated_at"])
        return pref


class ReadAllResponseSerializer(serializers.Serializer):
    updated = serializers.IntegerField()


class UnreadCountSerializer(serializers.Serializer):
    unread = serializers.IntegerField()


class PushDeviceSerializer(serializers.ModelSerializer):
    """Device surface — the raw push token is WRITE-ONLY and never echoed.

    ``device_id``/``push_token`` are accepted on registration/rotation but the
    response only confirms the device's identity, platform and lifecycle state.
    """

    push_token = serializers.CharField(write_only=True, max_length=255, trim_whitespace=True)

    class Meta:
        model = PushDevice
        fields = [
            "id", "platform", "device_id", "push_token",
            "is_active", "last_seen_at", "created_at",
        ]
        read_only_fields = ["id", "is_active", "last_seen_at", "created_at"]