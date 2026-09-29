"""AI assistant serializers.

Chat contract (api-design AD-2, configured here):

    POST /api/ai/chat/
    {
      "message":      "plain-language question",           required, 1..2000
      "use_case":     "education" | "medication_education" | "health_questions"
                      | "appointment_preparation" | "health_summary"
                      | "symptom_assistance" | "insight_explanation",
      "personalized": bool,                                default true
      "metric":       "medication_adherence"               only for insight_explanation
    }

One endpoint, one use-case switch — no redundant per-use-case endpoints
(§22; every surface maps to an approved FR and is counted in the traceability
matrix).

Trends contract:

    GET /api/ai/trends/{patient_uid}/?window_days=30
    window_days int, 1..90 (settings.AI_TRENDS_MAX_WINDOW_DAYS).
"""

from django.conf import settings
from rest_framework import serializers

USE_CASES = [
    "education",
    "medication_education",
    "health_questions",
    "appointment_preparation",
    "health_summary",
    "symptom_assistance",
    "insight_explanation",
]

#: The only deterministic metric an AI *explains*; it is always computed by the
#: durable enforcement (medications.services.adherence_stats), never by the LLM.
KNOWN_METRICS = ["medication_adherence"]


class AiChatSerializer(serializers.Serializer):
    message = serializers.CharField(
        trim_whitespace=True,
        max_length=settings.AI_MAX_MESSAGE_CHARS,
        min_length=1,
        error_messages={"blank": "message is required."},
    )
    use_case = serializers.ChoiceField(choices=USE_CASES, default="education")
    personalized = serializers.BooleanField(default=True)
    metric = serializers.ChoiceField(
        choices=KNOWN_METRICS, required=False, allow_null=True
    )

    def validate(self, attrs):
        if attrs["use_case"] == "insight_explanation" and not attrs.get("metric"):
            raise serializers.ValidationError(
                {"metric": "metric is required for insight_explanation."}
            )
        if attrs["use_case"] != "insight_explanation":
            attrs["metric"] = None
        return attrs


class AiTrendsSerializer(serializers.Serializer):
    window_days = serializers.IntegerField(
        min_value=1,
        max_value=settings.AI_TRENDS_MAX_WINDOW_DAYS,
        default=settings.AI_TRENDS_DEFAULT_WINDOW_DAYS,
    )