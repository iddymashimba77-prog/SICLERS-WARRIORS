"""Admin branding surface — the platform-logo control (Stage 4.31).

Public:
    GET  /api/branding/          200 {"data": {logo_url, logo_alt, has_logo}}
    GET  /api/branding/logo/     image/jpeg bytes (404 when unset)

Admin (``admin.branding.manage``, SUPER_ADMIN only, MFA step-up boundary,
all changes audited ``branding.*``):
    GET    /api/admin/branding/          current branding + provenance
    PATCH  /api/admin/branding/          {"logo_alt": "..."}
    POST   /api/admin/branding/logo/     multipart {"image": <file>, "alt": "..."}
    DELETE /api/admin/branding/logo/     revert to the built-in logo

Safety posture mirrors every other admin control plane:
* Deny-by-default gate + account-status gate + MFA step-up boundary.
* Uploads pass through the same server-side re-encode authority as news
  covers (``content.upload_validation``) — never served back raw.
* Replacing the logo overwrites the previous stored file (bounded storage).
"""

import os

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.http import HttpResponse, HttpResponseNotFound
from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from audit.services import record_audit
from content import upload_validation

from . import models
from .permissions import BrandingAdminAccess


def _audit(request, action_code, resource_id=1, details=None):
    record_audit(
        actor=getattr(request, "user", None),
        action_code=action_code,
        resource_type="app_branding",
        resource_id=resource_id,
        request=request,
        details=details,
    )


def _branding():
    """Return the singleton branding row (created lazily on first access)."""
    obj, _created = models.AppBranding.objects.get_or_create(pk=1)
    return obj


def _public_payload(branding):
    return {
        "logo_url": "/api/branding/logo/",
        "logo_alt": branding.logo_alt,
        "has_logo": bool(branding.logo),
    }


class BrandingPublicView(APIView):
    """Anonymous read of the platform brand (logo only ever points at the
    re-encoded public file endpoint)."""

    permission_classes = [AllowAny]

    def get(self, request):
        return Response(_public_payload(_branding()))


class BrandingLogoFileView(APIView):
    """Serve the stored logo as image bytes. 404 when branding unset."""

    permission_classes = [AllowAny]

    def get(self, request):
        branding = _branding()
        if not branding.logo:
            return HttpResponseNotFound("no logo configured")
        logo = default_storage.open(branding.logo.name, "rb")
        try:
            return HttpResponse(
                logo.read(),
                content_type="image/jpeg",
                headers={"Cache-Control": "public, max-age=3600"},
            )
        finally:
            logo.close()


class AdminBrandingView(APIView):
    """Branding read + alt-text update (SUPER_ADMIN only)."""

    permission_classes = [BrandingAdminAccess]
    parser_classes = [JSONParser, FormParser]

    def get(self, request):
        branding = _branding()
        payload = _public_payload(branding)
        payload.update(
            {
                "updated_at": branding.updated_at.isoformat(),
                "updated_by": (
                    {
                        "id": branding.updated_by_id,
                        "full_name": (
                            f"{branding.updated_by.first_name} {branding.updated_by.last_name}".strip()
                            if branding.updated_by
                            else ""
                        ),
                    }
                    if branding.updated_by_id
                    else None
                ),
            }
        )
        return Response(payload)

    def patch(self, request):
        alt = str(request.data.get("logo_alt", "")).strip()
        if len(alt) > 160:
            return Response(
                {"error": {"logo_alt": "Alt text must be 160 characters or fewer."}},
                status=http_status.HTTP_400_BAD_REQUEST,
            )
        branding = _branding()
        branding.logo_alt = alt
        branding.updated_by = request.user
        branding.updated_at = timezone.now()
        branding.save(update_fields=["logo_alt", "updated_by", "updated_at"])
        _audit(request, "branding.alt_update", details={"logo_alt": alt})
        return Response(_public_payload(branding))


class AdminBrandingLogoView(APIView):
    """Upload replacement logo (POST) or revert to built-in (DELETE)."""

    permission_classes = [BrandingAdminAccess]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        image = request.FILES.get("image")
        if image is None:
            return Response(
                {"error": {"image": "No image file was provided."}},
                status=http_status.HTTP_400_BAD_REQUEST,
            )
        alt = str(request.data.get("alt", "")).strip()[:160]
        try:
            buffer, _content_type = upload_validation.normalize_cover_image(image)
        except DjangoValidationError as exc:
            return Response(
                {"error": {"image": exc.messages}},
                status=http_status.HTTP_400_BAD_REQUEST,
            )

        branding = _branding()
        previous = branding.logo.name if branding.logo else None
        stored_name = default_storage.save(
            f"branding/brand_logo_{int(timezone.now().timestamp())}.jpg",
            ContentFile(buffer.getvalue()),
        )
        if previous:
            try:
                default_storage.delete(previous)
            except Exception:
                pass
        branding.logo = stored_name
        branding.logo_alt = alt
        branding.updated_by = request.user
        branding.save(update_fields=["logo", "logo_alt", "updated_by", "updated_at"])
        _audit(
            request,
            "branding.logo_update",
            details={
                "stored": os.path.basename(stored_name),
                "replaced_previous": bool(previous),
            },
        )
        return Response(_public_payload(branding))

    def delete(self, request):
        branding = _branding()
        if branding.logo:
            removed = branding.logo.name
            branding.logo.delete(save=False)
            branding.updated_by = request.user
            branding.save(update_fields=["logo", "updated_by", "updated_at"])
            _audit(
                request,
                "branding.logo_remove",
                details={"removed": os.path.basename(removed)},
            )
        return Response(
            {"removed": True},
            status=http_status.HTTP_200_OK,
        )