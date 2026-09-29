"""Education API views (approved Stage 4.11, endpoint-matrix §18).

    GET         /api/education/categories/                  public (FR-EDU-002)
    GET         /api/education/content/                     public, published (FR-EDU-001/004)
    GET         /api/education/content/{uid}/               public, published
    POST        /api/education/content/                     education.publish -> DRAFT
    PATCH/DELETE /api/education/content/{uid}/              author (drafts only)
    POST        /api/education/content/{uid}/submit/        author -> IN_REVIEW
    GET         /api/admin/education/content/               education.review
    POST        /api/admin/education/content/{uid}/review/  education.review (FR-EDU-003)

Deny by default: reads are Public but serve PUBLISHED content only (drafts are
locked, security-database-traceability); write requires ``education.publish``
(C12 for DOC/ORG — publication only after SUP/ADM review); the admin review
surface requires ``education.review``. There is no admin bypass into private
medical data — education is its own boundary (§4.11-3).
"""

from django.db import transaction
from django.db.models import Q
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.generics import ListAPIView
from rest_framework.parsers import JSONParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus
from audit.services import record_audit
from core.cache import KEY_EDUCATION_CATEGORIES, TTL_REFERENCE_15M
from core.caching import ReferenceCachedListMixin
from core.pagination import CorePageNumberPagination
from . import models, serializers, services
from .permissions import AdminEducationAccess, EducationAccess
from .throttles import EducationContentThrottle


class EducationCategoryListView(ReferenceCachedListMixin, ListAPIView):
    """Public categories (FR-EDU-002). No auth required."""

    queryset = models.EducationCategory.objects.all()
    serializer_class = serializers.EducationCategorySerializer
    permission_classes = [AllowAny]
    # Stage 4.18: the category vocabulary is static reference data — cache the
    # serialized list for 15 minutes.
    reference_key = KEY_EDUCATION_CATEGORIES
    reference_ttl = TTL_REFERENCE_15M


class EducationalContentViewSet(viewsets.GenericViewSet):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.EducationalContentSerializer
    permission_classes = [EducationAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_serializer_class(self):
        if getattr(self, "action", None) == "create":
            return serializers.EducationalContentCreateSerializer
        if getattr(self, "action", None) == "list":
            return serializers.EducationalContentListSerializer
        return serializers.EducationalContentSerializer

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action in ("create", "partial_update", "update", "destroy", "submit"):
            return [EducationContentThrottle()]
        return []

    def _base_queryset(self):
        return models.EducationalContent.objects.select_related("category", "author")

    def get_queryset(self):
        return self._base_queryset().filter(status="PUBLISHED")

    def get_object(self):
        qs = self._base_queryset()
        obj = qs.filter(**{self.lookup_field: self.kwargs[self.lookup_url_kwarg]}).first()
        if obj is None:
            raise NotFound("Not found.")
        if obj.status != "PUBLISHED":
            # Drafts/rejected/archived are locked from every non-author surface.
            user = getattr(self.request, "user", None)
            if not (user and user.is_authenticated and user.pk == obj.author_id):
                raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        qs = self.get_queryset()
        query = (request.query_params.get("q") or request.query_params.get("search") or "").strip()
        if query:
            qs = qs.filter(Q(title__icontains=query) | Q(body__icontains=query))
        category = (request.query_params.get("category") or "").strip()
        if category:
            if not models.EducationCategory.objects.filter(code=category).exists():
                raise ValidationError({"category": "Unsupported category."})
            qs = qs.filter(category__code=category)
        qs = qs.order_by("-published_at", "-id")
        page = self.paginate_queryset(qs)
        # Stage 4.18: the list payload is lean (no full HTML body) via
        # get_serializer -> EducationalContentListSerializer.
        serializer = self.get_serializer(page, many=True, context={"request": request})
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        instance = self.get_object()
        return Response(
            serializers.EducationalContentSerializer(instance, context={"request": request}).data
        )

    def _assert_author(self, request, obj):
        if obj.author_id != request.user.id:
            raise PermissionDenied("Only the author can change this content.")

    @transaction.atomic
    def create(self, request):
        user = request.user
        serializer = serializers.EducationalContentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        content = services.create_content(
            author=user, title=data["title"], body=data["body"],
            category=data["category"], cover_url=data.get("cover_url", ""),
        )
        record_audit(
            actor=user, action_code="education.content.create",
            resource_type="educational_content", resource_id=content.pk, request=request,
            details={"category": content.category.code, "status": content.status},
        )
        return Response(
            serializers.EducationalContentSerializer(content, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    @transaction.atomic
    def partial_update(self, request, uid=None):
        instance = self.get_object()
        self._assert_author(request, instance)
        if instance.status not in models.EDITABLE_STATUSES:
            raise ValidationError({"status": "Only draft, rejected or archived content can be edited."})
        serializer = serializers.EducationalContentCreateSerializer(
            data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.update_content(
            instance,
            title=data.get("title"),
            body=data.get("body"),
            category=data.get("category"),
            cover_url=data.get("cover_url"),
        )
        record_audit(
            actor=request.user, action_code="education.content.update",
            resource_type="educational_content", resource_id=instance.pk, request=request,
        )
        return Response(
            serializers.EducationalContentSerializer(instance, context={"request": request}).data
        )

    def update(self, request, uid=None):
        return self.partial_update(request, uid=uid)

    @transaction.atomic
    def destroy(self, request, uid=None):
        instance = self.get_object()
        self._assert_author(request, instance)
        if instance.status != "DRAFT":
            raise ValidationError(
                {"status": "Only a never-published draft can be deleted."}
            )
        # Hard delete is safe: a DRAFT has never been public, so no audience or
        # audit history is destroyed (audit keeps the delete event itself).
        record_audit(
            actor=request.user, action_code="education.content.delete",
            resource_type="educational_content", resource_id=instance.pk, request=request,
        )
        instance.delete()
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="submit")
    @transaction.atomic
    def submit(self, request, uid=None):
        instance = self.get_object()
        self._assert_author(request, instance)
        try:
            services.submit_content(instance)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=request.user, action_code="education.content.submit",
            resource_type="educational_content", resource_id=instance.pk, request=request,
        )
        return Response(
            serializers.EducationalContentSerializer(instance, context={"request": request}).data
        )


class AdminEducationalContentViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Admin CMS + review queue — ``education.review`` (SUP/ADM only).

    GET      /api/admin/education/content/?status=…      list (any status)
    POST     /api/admin/education/content/               create DRAFT
    GET      /api/admin/education/content/{uid}/
    PATCH    /api/admin/education/content/{uid}/         edit (DRAFT/REJECTED/ARCHIVED)
    DELETE   /api/admin/education/content/{uid}/         delete (DRAFT only)
    POST     /api/admin/education/content/{uid}/publish/ one-step publish (news-CMS parity)
    POST     /api/admin/education/content/{uid}/review/  approve/reject (community workflow)

    Users browse the PUBLIC library at /api/education/content/ which is locked
    to PUBLISHED rows only — admins manage/author here, everyone else reads
    the published library.
    """

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.AdminEducationalContentSerializer
    permission_classes = [AdminEducationAccess]
    pagination_class = CorePageNumberPagination
    parser_classes = [JSONParser]

    def get_serializer_class(self):
        action = getattr(self, "action", None)
        if action in ("create", "partial_update", "update"):
            return serializers.EducationalContentCreateSerializer
        return serializers.AdminEducationalContentSerializer

    def get_throttles(self):
        if getattr(self, "action", None) in (
            "create", "partial_update", "update", "destroy", "publish", "review",
        ):
            return [EducationContentThrottle()]
        return []

    def get_queryset(self):
        qs = models.EducationalContent.objects.select_related(
            "category", "author", "reviewed_by",
        )
        status_filter = (self.request.query_params.get("status") or "").strip()
        if status_filter:
            if status_filter not in models.CONTENT_STATUSES:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        return qs

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-created_at"))
        serializer = serializers.AdminEducationalContentSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def get_object(self):
        obj = models.EducationalContent.objects.select_related(
            "category", "author", "reviewed_by",
        ).filter(uid=self.kwargs["uid"]).first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    @transaction.atomic
    def create(self, request):
        serializer = serializers.EducationalContentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        content = services.create_content(
            author=request.user, title=data["title"], body=data["body"],
            category=data["category"], cover_url=data.get("cover_url", ""),
        )
        record_audit(
            actor=request.user, action_code="education.content.create",
            resource_type="educational_content", resource_id=content.pk, request=request,
            details={"category": content.category.code, "status": content.status},
        )
        return Response(
            serializers.AdminEducationalContentSerializer(content, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    @transaction.atomic
    def partial_update(self, request, uid=None):
        content = self.get_object()
        if content.status not in models.EDITABLE_STATUSES:
            raise ValidationError(
                {"status": "Only draft, rejected or archived content can be edited."}
            )
        serializer = serializers.EducationalContentCreateSerializer(
            data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.update_content(
            content,
            title=data.get("title"),
            body=data.get("body"),
            category=data.get("category"),
            cover_url=data.get("cover_url"),
        )
        record_audit(
            actor=request.user, action_code="education.content.update",
            resource_type="educational_content", resource_id=content.pk, request=request,
        )
        return Response(
            serializers.AdminEducationalContentSerializer(content, context={"request": request}).data
        )

    def update(self, request, uid=None):
        return self.partial_update(request, uid=uid)

    @transaction.atomic
    def destroy(self, request, uid=None):
        content = self.get_object()
        if content.status != "DRAFT":
            raise ValidationError(
                {"status": "Only a never-published draft can be deleted."}
            )
        record_audit(
            actor=request.user, action_code="education.content.delete",
            resource_type="educational_content", resource_id=content.pk, request=request,
        )
        content.delete()
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="publish")
    @transaction.atomic
    def publish(self, request, uid=None):
        content = self.get_object()
        try:
            services.admin_publish_content(content, actor=request.user)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=request.user, action_code="education.content.publish",
            resource_type="educational_content", resource_id=content.pk, request=request,
        )
        return Response(
            serializers.AdminEducationalContentSerializer(content, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="review")
    @transaction.atomic
    def review(self, request, uid=None):
        content = self.get_object()
        serializer = serializers.ReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            services.review_content(
                content, actor=request.user,
                decision=data["decision"], reason=data.get("reason", ""),
            )
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=request.user, action_code="education.content.review",
            resource_type="educational_content", resource_id=content.pk, request=request,
            details={"decision": data["decision"], "status": content.status},
        )
        return Response(
            serializers.AdminEducationalContentSerializer(content, context={"request": request}).data
        )