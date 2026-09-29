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
from rest_framework import status as http_status
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsAuthenticatedRespectStatus

from .permissions import AiUseAccess
from .serializers import AiChatSerializer, AiTrendsSerializer
from .services import AiAssistantService
from .throttles import AiChatThrottle, AiTrendsThrottle

logger = logging.getLogger(__name__)


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