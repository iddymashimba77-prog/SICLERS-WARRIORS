"""Content CMS API views.

Deny-by-default: public reads are AllowAny but serve only PUBLISHED news /
ACTIVE ticker rows (drafts are locked); every admin surface requires the
seeded ``content.news.manage`` or ``content.ticker.manage`` code. Admin writes
are audited (content.* actions) and throttled. Cover uploads are re-encoded
server-side and never returned raw.
"""

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Q
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.generics import ListAPIView
from rest_framework.parsers import JSONParser, FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from audit.services import record_audit
from core.pagination import CorePageNumberPagination

from . import models, serializers, services, upload_validation
from .permissions import ContentNewsAccess, ContentTickerAccess
from .throttles import ContentCoverThrottle, ContentWriteThrottle


def _audit(request, action_code, resource_type, resource_id, details=None):
    record_audit(
        actor=getattr(request, "user", None),
        action_code=action_code,
        resource_type=resource_type,
        resource_id=resource_id,
        request=request,
        details=details,
    )


def _by_uid(queryset, uid):
    """Resolve a uid path segment to a row, or ``None``.

    uid fields are UUIDs; a malformed segment would otherwise raise a
    ValueError/ValidationError inside the ORM and surface as a 500. Any
    unparseable value is treated exactly like an unfound row → 404 so public
    readers and the admin CMS never leak an internal error.
    """
    try:
        return queryset.filter(uid=uid).first()
    except (TypeError, ValueError, DjangoValidationError):
        return None


# --------------------------------------------------------------- public news

class PublicNewsCategoryListView(ListAPIView):
    """Public category vocabulary (dropdowns / filters). AllowAny."""

    permission_classes = [AllowAny]

    def list(self, request):
        return Response(
            [
                {"code": code, "label": label}
                for code, label in models.NEWS_CATEGORIES
            ]
        )


class PublicNewsViewSet(viewsets.GenericViewSet):
    """Public news feed — PUBLISHED rows only.

        GET /api/content/news/?featured=true&q=&category=&page=
        GET /api/content/news/{uid}/
    """

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    # Routed sub-paths (/latest/ and /categories/) must never fall into the
    # uid detail regex, so exclude them from the lookup capture.
    lookup_value_regex = r"(?!latest|categories)[^/.]+"
    permission_classes = [AllowAny]
    pagination_class = CorePageNumberPagination
    parser_classes = [JSONParser]

    def get_serializer_class(self):
        return serializers.PublicNewsSummarySerializer

    def get_queryset(self):
        return models.NewsArticle.objects.filter(status="PUBLISHED")

    def _base(self):
        return models.NewsArticle.objects.filter(status="PUBLISHED").select_related("author")

    @action(detail=False, methods=["get"])
    def latest(self, request):
        """The newest published article (home hero read)."""
        article = self._base().order_by("-published_at", "-id").first()
        if article is None:
            return Response({"article": None})
        return Response(
            {
                "article": serializers.PublicNewsDetailSerializer(
                    article, context={"request": request},
                ).data
            }
        )

    def list(self, request):
        qs = self._base()
        query = (request.query_params.get("q") or request.query_params.get("search") or "").strip()
        if query:
            qs = qs.filter(
                Q(title__icontains=query)
                | Q(excerpt__icontains=query)
                | Q(body__icontains=query)
            )
        category = (request.query_params.get("category") or "").strip()
        if category:
            if category not in [c for c, _ in models.NEWS_CATEGORIES]:
                raise ValidationError({"category": "Unsupported category."})
            qs = qs.filter(category=category)
        featured = (request.query_params.get("featured") or "").strip()
        if featured in ("true", "1"):
            qs = qs.filter(featured=True)
        elif featured in ("false", "0"):
            qs = qs.filter(featured=False)
        qs = qs.order_by("-published_at", "-id")
        page = self.paginate_queryset(qs)
        serializer = serializers.PublicNewsSummarySerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        article = _by_uid(self._base(), uid)
        if article is None:
            raise NotFound("Not found.")
        return Response(
            serializers.PublicNewsDetailSerializer(
                article, context={"request": request},
            ).data
        )


class PublicTickerListView(ListAPIView):
    """Public top ticker — active + time-effective announcements only."""

    permission_classes = [AllowAny]

    def list(self, request):
        from django.utils import timezone
        now = timezone.now()
        rows = [
            ann for ann in models.TickerAnnouncement.objects.all()
            if ann.is_effective(now)
        ]
        rows.sort(key=lambda a: (-a.priority, -a.created_at.timestamp()))
        return Response(
            serializers.PublicTickerSerializer(rows, many=True).data
        )


# ----------------------------------------------------------------- admin news

class AdminNewsViewSet(viewsets.GenericViewSet):
    """News CMS — ``content.news.manage`` (SUPER_ADMIN/ADMIN).

        GET   /api/admin/content/news/?status=&featured=&q=&category=
        POST  /api/admin/content/news/                 -> DRAFT
        GET   /api/admin/content/news/{uid}/
        PATCH /api/admin/content/news/{uid}/           (DRAFT/ARCHIVED only)
        DELETE /api/admin/content/news/{uid}/          (DRAFT only)
        POST  /api/admin/content/news/{uid}/publish|unpublish|archive|feature/
        POST  /api/admin/content/news/{uid}/cover/     multipart image
    """

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    permission_classes = [ContentNewsAccess]
    pagination_class = CorePageNumberPagination

    def get_parsers(self):
        # Request initialization runs BEFORE ``self.action`` is set, so parser
        # selection cannot branch on the routed action name — the news CMS
        # accepts both JSON (CRUD/status) and multipart (cover upload). The
        # serializers + our Pillow validator enforce the real constraints.
        return [MultiPartParser(), FormParser(), JSONParser()]

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action == "upload_cover":
            return [ContentCoverThrottle()]
        if action in ("create", "partial_update", "update", "destroy",
                      "publish", "unpublish", "archive", "feature"):
            return [ContentWriteThrottle()]
        return []

    def get_serializer_class(self):
        if getattr(self, "action", None) == "create":
            return serializers.NewsWriteSerializer
        if getattr(self, "action", None) == "partial_update":
            return serializers.NewsWriteSerializer
        return serializers.AdminNewsSerializer

    def get_queryset(self):
        return models.NewsArticle.objects.select_related("author")

    def get_object(self):
        obj = _by_uid(self.get_queryset(), self.kwargs[self.lookup_url_kwarg])
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        qs = self.get_queryset()
        status_filter = (request.query_params.get("status") or "").strip()
        if status_filter:
            if status_filter not in models.NEWS_STATUSES:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        featured = (request.query_params.get("featured") or "").strip()
        if featured in ("true", "1"):
            qs = qs.filter(featured=True)
        elif featured in ("false", "0"):
            qs = qs.filter(featured=False)
        category = (request.query_params.get("category") or "").strip()
        if category:
            qs = qs.filter(category=category)
        query = (request.query_params.get("q") or "").strip()
        if query:
            qs = qs.filter(Q(title__icontains=query) | Q(excerpt__icontains=query))
        page = self.paginate_queryset(qs.order_by("-created_at"))
        serializer = serializers.AdminNewsSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        instance = self.get_object()
        return Response(
            serializers.AdminNewsSerializer(instance, context={"request": request}).data
        )

    @transaction.atomic
    def create(self, request):
        serializer = serializers.NewsWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        article = services.create_news(
            author=request.user,
            title=data["title"],
            category=data["category"],
            body=data["body"],
            excerpt=data.get("excerpt", ""),
            cover_url=data.get("cover_url", ""),
            cover_alt=data.get("cover_alt", ""),
            tags=data.get("tags", []),
        )
        _audit(
            request, "content.news.create", "news_article", article.pk,
            {"category": article.category, "status": article.status},
        )
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    @transaction.atomic
    def partial_update(self, request, uid=None):
        article = self.get_object()
        if article.status not in models.EDITABLE_STATUSES:
            raise ValidationError(
                {"status": "Only draft or archived news can be edited."}
            )
        serializer = serializers.NewsWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.update_news(
            article,
            title=data.get("title"),
            category=data.get("category"),
            body=data.get("body"),
            excerpt=data.get("excerpt"),
            cover_url=data.get("cover_url"),
            cover_alt=data.get("cover_alt"),
            tags=data.get("tags"),
        )
        _audit(request, "content.news.update", "news_article", article.pk)
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data
        )

    def update(self, request, uid=None):
        return self.partial_update(request, uid=uid)

    @transaction.atomic
    def destroy(self, request, uid=None):
        article = self.get_object()
        if article.status != "DRAFT":
            raise ValidationError(
                {"status": "Only a never-published draft can be deleted."}
            )
        _audit(request, "content.news.delete", "news_article", article.pk)
        article.delete()
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="publish")
    @transaction.atomic
    def publish(self, request, uid=None):
        article = self.get_object()
        try:
            services.publish_news(article)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        _audit(request, "content.news.publish", "news_article", article.pk)
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="unpublish")
    @transaction.atomic
    def unpublish(self, request, uid=None):
        article = self.get_object()
        try:
            services.unpublish_news(article)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        _audit(request, "content.news.unpublish", "news_article", article.pk)
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="archive")
    @transaction.atomic
    def archive(self, request, uid=None):
        article = self.get_object()
        try:
            services.archive_news(article)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        _audit(request, "content.news.archive", "news_article", article.pk)
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="feature")
    @transaction.atomic
    def feature(self, request, uid=None):
        article = self.get_object()
        serializer = serializers.FeatureSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        featured = serializer.validated_data["featured"]
        try:
            services.set_featured(article, featured=featured)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        _audit(
            request, "content.news.feature", "news_article", article.pk,
            {"featured": article.featured},
        )
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="cover")
    @transaction.atomic
    def upload_cover(self, request, uid=None):
        article = self.get_object()
        serializer = serializers.NewsCoverSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        image = serializer.validated_data["image"]
        alt = serializer.validated_data.get("alt", "")
        try:
            buffer, _content_type = upload_validation.normalize_cover_image(image)
        except DjangoValidationError as exc:
            raise ValidationError({"image": exc.messages})
        stored_name = default_storage.save(
            f"content/news/{article.uid}.jpg",
            ContentFile(buffer.getvalue()),
        )
        article.cover_url = request.build_absolute_uri(
            f"/{settings.MEDIA_URL}{stored_name}"
        )
        if alt:
            article.cover_alt = alt
        article.save(update_fields=["cover_url", "cover_alt", "updated_at"])
        _audit(request, "content.news.cover", "news_article", article.pk)
        return Response(
            serializers.AdminNewsSerializer(article, context={"request": request}).data
        )


# ------------------------------------------------------------- admin ticker

class AdminTickerViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Top ticker CMS — ``content.ticker.manage`` (SUPER_ADMIN/ADMIN)."""

    queryset = models.TickerAnnouncement.objects.all()
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.AdminTickerSerializer
    permission_classes = [ContentTickerAccess]
    pagination_class = CorePageNumberPagination
    parser_classes = [JSONParser]

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action in ("create", "partial_update", "update", "destroy",
                      "activate", "deactivate"):
            return [ContentWriteThrottle()]
        return []

    def get_serializer_class(self):
        if getattr(self, "action", None) in ("create", "partial_update", "update"):
            return serializers.TickerWriteSerializer
        return serializers.AdminTickerSerializer

    def get_queryset(self):
        queryset = models.TickerAnnouncement.objects.all()
        status_filter = (self.request.query_params.get("is_active") or "").strip()
        if status_filter in ("true", "1"):
            queryset = queryset.filter(is_active=True)
        elif status_filter in ("false", "0"):
            queryset = queryset.filter(is_active=False)
        return queryset

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-priority", "-created_at"))
        serializer = serializers.AdminTickerSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def get_object(self):
        obj = _by_uid(self.get_queryset(), self.kwargs["uid"])
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def retrieve(self, request, uid=None):
        instance = self.get_object()
        return Response(
            serializers.AdminTickerSerializer(
                instance, context={"request": request},
            ).data
        )

    @transaction.atomic
    def create(self, request):
        serializer = serializers.TickerWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        ann = services.create_ticker(
            created_by=request.user,
            message=data["message"],
            announcement_type=data.get("announcement_type", "INFO"),
            link_url=data.get("link_url", ""),
            is_active=data.get("is_active", True),
            priority=data.get("priority", 0),
            start_at=data.get("start_at"),
            end_at=data.get("end_at"),
        )
        _audit(
            request, "content.ticker.create", "ticker_announcement", ann.pk,
            {"type": ann.announcement_type, "active": ann.is_active},
        )
        return Response(
            serializers.AdminTickerSerializer(ann).data,
            status=http_status.HTTP_201_CREATED,
        )

    @transaction.atomic
    def partial_update(self, request, uid=None):
        ann = self.get_object()
        serializer = serializers.TickerWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            services.update_ticker(
                ann,
                message=data.get("message"),
                announcement_type=data.get("announcement_type"),
                link_url=data.get("link_url"),
                is_active=data.get("is_active"),
                priority=data.get("priority"),
                start_at=data.get("start_at"),
                end_at=data.get("end_at"),
            )
        except ValueError as exc:
            raise ValidationError({"end_at": str(exc)})
        _audit(request, "content.ticker.update", "ticker_announcement", ann.pk)
        return Response(serializers.AdminTickerSerializer(ann).data)

    def update(self, request, uid=None):
        return self.partial_update(request, uid=uid)

    @transaction.atomic
    def destroy(self, request, uid=None):
        ann = self.get_object()
        _audit(request, "content.ticker.delete", "ticker_announcement", ann.pk)
        ann.delete()
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="activate")
    @transaction.atomic
    def activate(self, request, uid=None):
        ann = self.get_object()
        services.set_ticker_active(ann, active=True)
        _audit(request, "content.ticker.activate", "ticker_announcement", ann.pk)
        return Response(serializers.AdminTickerSerializer(ann).data)

    @action(detail=True, methods=["post"], url_path="deactivate")
    @transaction.atomic
    def deactivate(self, request, uid=None):
        ann = self.get_object()
        services.set_ticker_active(ann, active=False)
        _audit(request, "content.ticker.deactivate", "ticker_announcement", ann.pk)
        return Response(serializers.AdminTickerSerializer(ann).data)