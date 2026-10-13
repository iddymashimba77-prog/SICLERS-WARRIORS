"""Education API views (approved Stage 4.11, endpoint-matrix §18).

    GET         /api/education/categories/                  public (FR-EDU-002)
    GET         /api/education/content/                     public, published (FR-EDU-001/004)
    GET         /api/education/content/?mine=1              author, every status
    GET         /api/education/content/{uid}/               public, published
    POST        /api/education/content/                     education.publish -> DRAFT
    PATCH/DELETE /api/education/content/{uid}/              author (drafts only)
    POST        /api/education/content/{uid}/submit/        author -> IN_REVIEW
    POST/DELETE /api/education/content/{uid}/document/      author, multipart (FR-EDU-005)
    GET         /api/admin/education/content/               education.review
    POST        /api/admin/education/content/{uid}/review/  education.review (FR-EDU-003)
    POST/DELETE /api/admin/education/content/{uid}/document/ education.review, multipart

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
from rest_framework.exceptions import (
    NotAuthenticated,
    NotFound,
    PermissionDenied,
    ValidationError,
)
from rest_framework.generics import ListAPIView
from rest_framework.parsers import JSONParser, MultiPartParser
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


def _truthy(value) -> bool:
    """Parse the loose truthy query flags the API already uses elsewhere."""
    return (value or "").strip().lower() in ("1", "true", "yes")


class EducationDocumentActionMixin:
    """Attach/replace/remove a downloadable handout on an education item.

    Shared by the author surface (``/education/content/``) and the admin CMS
    surface (``/admin/education/content/``). The two differ only in who may
    write — subclasses narrow access through their own permission classes —
    so the validation, storage, audit and status rules live here once.

    >>> POST   .../content/{uid}/document/   multipart `document`
    >>> DELETE .../content/{uid}/document/
    """

    #: Overridden by the admin viewset, where an editor may work on anyone's
    #: draft but the rule that a live article never changes still applies.
    assert_document_author = True

    @action(
        detail=True, methods=["post", "delete"], url_path="document",
        parser_classes=[MultiPartParser, JSONParser],
    )
    def document(self, request, uid=None):
        """POST attaches or replaces the file; DELETE removes it.

        Both verbs live on one action on purpose: the DRF router indexes
        routes by ``url_path``, so two actions sharing ``document`` would let
        the first-registered one shadow the other.
        """
        if request.method == "DELETE":
            return self._remove_document(request, uid=uid)
        return self._upload_document(request, uid=uid)

    def _guard_document(self, request, instance):
        """Deny writes to a PUBLISHED article (object-level rule)."""
        if instance.status == "PUBLISHED":
            raise ValidationError(
                {"status": "A published article cannot be changed. Unpublish it first."}
            )
        if self.assert_document_author:
            self._assert_author(request, instance)

    @transaction.atomic
    def _upload_document(self, request, uid=None):
        instance = self.get_object()
        self._guard_document(request, instance)
        uploaded = request.FILES.get("document") or request.FILES.get("file")
        try:
            meta = services.validate_document_upload(uploaded)
        except services.DocumentRejected as exc:
            raise ValidationError({exc.field: exc.reason})
        services.attach_document(instance, uploaded=uploaded, actor=request.user, meta=meta)

        record_audit(
            actor=request.user, action_code="education.content.document_upload",
            resource_type="educational_content", resource_id=instance.pk, request=request,
            # Metadata only — an attachment is never copied into the audit row.
            details={
                "document_name": instance.document_name,
                "content_type": instance.document_content_type,
                "size": instance.document_size,
            },
        )
        return Response(
            self._document_serializer(instance, request).data
        )

    @transaction.atomic
    def _remove_document(self, request, uid=None):
        instance = self.get_object()
        self._guard_document(request, instance)
        if not instance.document_file:
            raise ValidationError({"document": "This article has no document attached."})
        services.remove_document(instance, actor=request.user)
        record_audit(
            actor=request.user, action_code="education.content.document_remove",
            resource_type="educational_content", resource_id=instance.pk, request=request,
        )
        return Response(self._document_serializer(instance, request).data)

    def _document_serializer(self, instance, request):
        return self.get_serializer(instance, context={"request": request})


class EducationalContentViewSet(EducationDocumentActionMixin, viewsets.GenericViewSet):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.EducationalContentSerializer
    permission_classes = [EducationAccess]
    parser_classes = [JSONParser, MultiPartParser]
    pagination_class = CorePageNumberPagination

    def get_serializer_class(self):
        if getattr(self, "action", None) == "create":
            return serializers.EducationalContentCreateSerializer
        if getattr(self, "action", None) == "list":
            if _truthy(self.request.query_params.get("mine")):
                # The author's own workspace is a management surface, so it
                # carries the full projection (handout metadata included).
                return serializers.EducationalContentSerializer
            # The public feed stays lean (no full HTML body, no file metadata).
            return serializers.EducationalContentListSerializer
        return serializers.EducationalContentSerializer

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action in (
            "create", "partial_update", "update", "destroy", "submit", "document",
        ):
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
        # ``?mine=1`` switches to the author's own workspace: every status,
        # newest first. This is what a doctor's "My articles" screen reads; the
        # public feed above stays published-only either way.
        if _truthy(request.query_params.get("mine")):
            user = getattr(request, "user", None)
            if not (user and user.is_authenticated):
                # Not a 404: the endpoint exists, the caller simply has no
                # identity to scope it to.
                raise NotAuthenticated("Sign in to list your own articles.")
            qs = self._base_queryset().filter(author=user)
            status_filter = (request.query_params.get("status") or "").strip()
            if status_filter:
                if status_filter not in models.CONTENT_STATUSES:
                    raise ValidationError({"status": "Unsupported status."})
                qs = qs.filter(status=status_filter)
            qs = qs.order_by("-updated_at", "-id")
            page = self.paginate_queryset(qs)
            serializer = self.get_serializer(page, many=True, context={"request": request})
            return self.get_paginated_response(serializer.data)

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


class AdminEducationalContentViewSet(
    EducationDocumentActionMixin, mixins.ListModelMixin, viewsets.GenericViewSet,
):
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
    parser_classes = [JSONParser, MultiPartParser]

    # An editor may attach a handout to a draft another person authored; the
    # ``education.review`` gate on this surface is the control that matters.
    assert_document_author = False

    def get_serializer_class(self):
        action = getattr(self, "action", None)
        if action in ("create", "partial_update", "update"):
            return serializers.EducationalContentCreateSerializer
        return serializers.AdminEducationalContentSerializer

    def get_throttles(self):
        if getattr(self, "action", None) in (
            "create", "partial_update", "update", "destroy", "publish", "review",
            "document",
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