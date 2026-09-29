"""Analytics serializers (approved api-design §40: AnalyticsSerializer).

Read-only aggregate views — no PHI, no identifiers, no raw domain rows.
``dimensions`` carries only categorical slices (status/urgency/severity/
category/code). ``value`` is a count/sum/average.
"""

from rest_framework import serializers

from .models import AnalyticsSnapshot


class AnalyticsSerializer(serializers.ModelSerializer):
    """One aggregate snapshot row (reporting grid / CSV column set)."""

    measured_at = serializers.DateTimeField(format="%Y-%m-%dT%H:%M:%SZ")

    class Meta:
        model = AnalyticsSnapshot
        fields = ["metric_key", "dimensions", "value", "granularity", "measured_at"]


class AnalyticsQuerySerializer(serializers.Serializer):
    """Whitelisted filters for GET /admin/analytics (§23 — never **)."""

    metric = serializers.CharField(max_length=100)
    granularity = serializers.ChoiceField(choices=["DAILY", "WEEKLY", "MONTHLY"], default="DAILY")
    date_from = serializers.DateField(required=False)
    date_to = serializers.DateField(required=False)
    reason = serializers.CharField(max_length=500, required=False, allow_blank=True)