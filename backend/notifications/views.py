"""Notification API views (recipient-only scope, Stage 4.8 + 4.13).

    GET      /api/notifications/                    list own (recipient)
    GET      /api/notifications/unread-count/       unread badge count
    GET      /api/notifications/{id}/               detail own
    POST     /api/notifications/{id}/read/          mark own read
    POST     /api/notifications/read-all/           mark all own read
    GET/PATCH /api/notifications/preferences/       FR-NOT-006
    POST     /api/notifications/devices/            register push device
    GET      /api/notifications/devices/            list own active devices
    DELETE   /api/notifications/devices/{id}/       deactivate own device

Ownership model ("deny by default"): every queryset is filtered to the
authenticated recipient; a notification id belonging to another user yields
404, never a foreign payload (IDOR-safe). Emergency notifications are never
suppressible (services layer). ``SUPPRESSED`` rows stay in the database for
audit but are excluded from the inbox and the unread badge.
"""

from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.generics import GenericAPIView, ListCreateAPIView, RetrieveUpdateDestroyAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus, require
from core.pagination import CorePageNumberPagination
from . import models, serializers, services


class NotificationViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """Recipient-scoped inbox (FR-NOT-001..005)."""

    serializer_class = serializers.NotificationSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("notifications.view")]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.Notification.objects.none()
        return models.Notification.objects.filter(recipient=user).exclude(status="SUPPRESSED")

    @action(detail=False, methods=["get"], url_path="unread-count")
    def unread_count(self, request):
        count = services.unread_count(request.user)
        return Response({"unread": count})

    @action(detail=True, methods=["post"], url_path="read")
    def read(self, request, pk=None):
        notification = self.get_object()
        services.mark_read(notification)
        return Response(self.get_serializer(notification).data)

    @action(detail=False, methods=["post"], url_path="read-all")
    def read_all(self, request):
        updated = services.read_all(request.user)
        return Response({"updated": updated})


class NotificationPreferencesView(GenericAPIView):
    """GET/PATCH /notifications/preferences — FR-NOT-006 (manage_prefs).

    GET returns the full ``{category: enabled}`` map (unset == enabled).
    PATCH receives ``{"category": "...", "enabled": bool}``.
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("notifications.manage_prefs")]
    parser_classes = [JSONParser]
    pagination_class = None
    serializer_class = serializers.PreferenceUpdateSerializer

    def get(self, request):
        from .services import ALL_CATEGORIES

        prefs = {
            pref.category: pref.enabled
            for pref in models.NotificationPreference.objects.filter(user=request.user)
        }
        return Response(
            {"preferences": {cat: prefs.get(cat, True) for cat in ALL_CATEGORIES}}
        )

    def patch(self, request):
        srz = self.get_serializer(data=request.data)
        srz.is_valid(raise_exception=True)
        pref = srz.save(user=request.user)
        return Response(serializers.PreferenceSerializer(pref).data, status=http_status.HTTP_200_OK)


class PushDeviceListCreateView(ListCreateAPIView):
    """POST /notifications/devices/ (register/rotate) + GET own devices.

    Registration is authenticated (recipient-only) and ownership is enforced by
    a user-scoped queryset; the response never contains the raw push token.
    """

    serializer_class = serializers.PushDeviceSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    pagination_class = None

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.PushDevice.objects.none()
        return services.list_devices(user)

    def perform_create(self, serializer):
        services.register_device(
            user=self.request.user,
            push_token=serializer.validated_data["push_token"],
            platform=serializer.validated_data.get("platform", "OTHER"),
            device_id=serializer.validated_data.get("device_id", ""),
        )

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        # Response is the user's active device surface, token stripped.
        device = services.list_devices(request.user).first()
        return Response(serializers.PushDeviceSerializer(device).data, status=http_status.HTTP_201_CREATED)


class PushDeviceDetailView(RetrieveUpdateDestroyAPIView):
    """DELETE /notifications/devices/{id}/ — deactivate an own device (IDOR-safe)."""

    serializer_class = serializers.PushDeviceSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.PushDevice.objects.none()
        return services.list_devices(user)

    def destroy(self, request, *args, **kwargs):
        device = self.get_object()
        services.deactivate_device(request.user, device)
        return Response({"deactivated": device.pk}, status=http_status.HTTP_200_OK)