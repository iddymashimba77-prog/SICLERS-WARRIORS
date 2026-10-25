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
      "conversation_uid": "uuid"                           optional (append to history)
    }

The response is the single ``_finish()`` envelope plus ``conversation_uid``.

Conversation history contract:

    GET    /api/ai-assistant/conversations/            → newest first
    POST   /api/ai-assistant/conversations/            {title?} → create
    GET    /api/ai-assistant/conversations/{uid}/      → detail + messages
    PATCH  /api/ai-assistant/conversations/{uid}/      {title?, archived?}
    DELETE /api/ai-assistant/conversations/{uid}/
    POST   /api/ai-assistant/conversations/{uid}/messages/  (a chat turn)

All conversation access is owner-scoped; another user's uid is a 404.

Trends contract:

    GET /api/ai/trends/{patient_uid}/?window_days=30
    window_days int, 1..90 (settings.AI_TRENDS_MAX_WINDOW_DAYS).
"""

from django.conf import settings
from rest_framework import serializers

from .models import Conversation, Message

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
    # Client-supplied fallback context only (server-side history is preferred
    # and rebuilt from the database). Capped so a caller cannot inflate the
    # prompt without bound.
    history = serializers.ListField(
        child=serializers.DictField(), required=False, allow_null=True, max_length=50
    )
    messages = serializers.ListField(
        child=serializers.DictField(), required=False, allow_null=True, max_length=50
    )
    conversation_uid = serializers.UUIDField(required=False)

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


class MessageSerializer(serializers.ModelSerializer):
    uid = serializers.UUIDField(read_only=True)

    class Meta:
        model = Message
        fields = ["uid", "role", "content", "created_at", "meta"]


class ConversationListSerializer(serializers.ModelSerializer):
    uid = serializers.UUIDField(read_only=True)
    message_count = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = ["uid", "title", "created_at", "updated_at", "last_activity_at", "archived", "message_count"]

    def get_message_count(self, obj):
        try:
            return obj.messages.count()
        except Exception:
            return 0


class ConversationDetailSerializer(serializers.ModelSerializer):
    uid = serializers.UUIDField(read_only=True)
    messages = MessageSerializer(many=True, read_only=True)

    class Meta:
        model = Conversation
        fields = ["uid", "title", "created_at", "updated_at", "last_activity_at", "archived", "messages"]


class ConversationCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=200, required=False, allow_blank=True)
    message = serializers.CharField(max_length=settings.AI_MAX_MESSAGE_CHARS, required=False, allow_blank=True)


class ConversationUpdateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=200, required=False, allow_blank=True)
    archived = serializers.BooleanField(required=False)
