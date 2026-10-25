"""AI assistant API views (api-design AD-2; role-permission-matrix §3.21).

    POST /api/ai/chat/              — ai.use (all roles A); chat pipeline
    GET  /api/ai/trends/<uid>/      — ai.use + analytics.health_trends;
                                       owner-only (self)

Privacy posture (AD-7 / database-design §19):
  * The chat response carries only the generated text, citations and context
    provenance flags — never another person's data, and never a full record.
  * ``/ai/trends`` targets the caller's own ``uid`` only. Non-owners get a 403
    ``consent_unavailable`` (consent is a separate, unbuilt surface) and the
    denial is audit-logged; invalid/missing uids are 404 (no existence probes).
"""

import logging

from django.contrib.auth import get_user_model
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import status as http_status
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsAuthenticatedRespectStatus

from .models import Conversation
from .permissions import AiUseAccess
from .serializers import (
    AiChatSerializer,
    AiTrendsSerializer,
    ConversationCreateSerializer,
    ConversationDetailSerializer,
    ConversationListSerializer,
    ConversationUpdateSerializer,
)
from .services import AiAssistantService
from .throttles import AiChatThrottle, AiConversationThrottle, AiTrendsThrottle

logger = logging.getLogger(__name__)


@extend_schema(request=AiChatSerializer, responses={200: OpenApiTypes.OBJECT})
class AiChatView(APIView):
    """Ask the assistant one turn (education + decision support, FR-AI-001/002)."""

    permission_classes = [IsAuthenticatedRespectStatus, AiUseAccess]
    throttle_classes = [AiChatThrottle]
    parser_classes = [JSONParser]

    def post(self, request):
        serializer = AiChatSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = AiAssistantService().handle_chat(
            request.user, serializer.validated_data, request
        )
        return Response(payload, status=http_status.HTTP_200_OK)


@extend_schema(parameters=[AiTrendsSerializer], responses={200: OpenApiTypes.OBJECT})
class AiTrendsView(APIView):
    """GET /api/ai/trends/<patient_uid>/ — own health-trend analysis (FR-AI-004)."""

    permission_classes = [IsAuthenticatedRespectStatus, AiUseAccess]
    throttle_classes = [AiTrendsThrottle]
    parser_classes = [JSONParser]

    def get(self, request, patient_uid):
        qs = AiTrendsSerializer(data=request.query_params)
        qs.is_valid(raise_exception=True)

        User = get_user_model()
        try:
            target = User.objects.get(uid=patient_uid)
        except (User.DoesNotExist, ValidationError, ValueError, TypeError):
            raise NotFound()

        payload = AiAssistantService().handle_trends(
            request.user, target, qs.validated_data["window_days"], request
        )
        return Response(payload)

class ConversationViewSet(viewsets.GenericViewSet):
    """CRUD for the caller's own AI conversations (never another user's)."""

    permission_classes = [IsAuthenticatedRespectStatus, AiUseAccess]
    throttle_classes = [AiConversationThrottle]

    def get_throttles(self):
        # A turn is a chat call and belongs to the chat budget; CRUD is cheap
        # and must not consume the 6/min chat allowance.
        if self.action == "messages":
            return [AiChatThrottle()]
        return super().get_throttles()

    def get_queryset(self):
        return Conversation.objects.filter(user=self.request.user).prefetch_related(
            "messages"
        )

    def list(self, request):
        qs = self.get_queryset().filter(archived=False)
        return Response(ConversationListSerializer(qs, many=True).data)

    def create(self, request):
        serializer = ConversationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        title = (serializer.validated_data.get("title") or "").strip()
        if not title:
            title = (serializer.validated_data.get("message") or "").strip()
        conversation = Conversation.objects.create(
            user=request.user,
            title=title[:200],
            last_activity_at=timezone.now(),
        )
        return Response(
            ConversationDetailSerializer(conversation).data,
            status=http_status.HTTP_201_CREATED,
        )

    def retrieve(self, request, pk=None):
        conversation = get_object_or_404(self.get_queryset(), uid=pk)
        return Response(ConversationDetailSerializer(conversation).data)

    def partial_update(self, request, pk=None):
        conversation = get_object_or_404(self.get_queryset(), uid=pk)
        serializer = ConversationUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if "title" in serializer.validated_data:
            conversation.title = (serializer.validated_data["title"] or "")[:200]
        if "archived" in serializer.validated_data:
            conversation.archived = serializer.validated_data["archived"]
        conversation.last_activity_at = timezone.now()
        conversation.save()
        return Response(ConversationDetailSerializer(conversation).data)

    def destroy(self, request, pk=None):
        conversation = get_object_or_404(self.get_queryset(), uid=pk)
        conversation.delete()
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="messages")
    def messages(self, request, pk=None):
        conversation = get_object_or_404(self.get_queryset(), uid=pk)
        serializer = AiChatSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = dict(serializer.validated_data)
        data["conversation_uid"] = conversation.uid
        payload = AiAssistantService().handle_chat(request.user, data, request)
        return Response(payload, status=http_status.HTTP_200_OK)
