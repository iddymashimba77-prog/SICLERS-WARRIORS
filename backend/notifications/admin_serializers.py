"""Admin notification serializers (Stage 4.16 §16)."""

from rest_framework import serializers


class AdminBroadcastOut(serializers.Serializer):
    audience = serializers.CharField()
    recipient_count = serializers.IntegerField()