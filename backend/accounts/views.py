"""Authentication views for Sickler's Warriors (§ SD-9 / §07 API design).

Every endpoint enforces the approved security posture:

* Authentication proves identity but grants **no** access by itself
  (NFR-SEC-003/004).
* Account status gates all authenticated views: ACTIVE and
  PENDING_VERIFICATION are usable; SUSPENDED / DISABLED / DEACTIVATED are
  denied (BR-017/018, account-status lifecycle).
* Privileged roles can never be self-assigned at registration
  (``_PRIVILEGED_ROLE_SUBSTRINGS`` gate in serializers).
* Rate limiting / throttling is applied by settings (user-scoped for
  login/refresh/password-reset).
* No passwords, tokens or session material is ever written to logs or
  returned in error responses.
"""

import logging
import mimetypes
import os
from urllib.parse import urlparse

import uuid

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.http import FileResponse, HttpResponse
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, permissions, status
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from audit.services import record_audit
from content import upload_validation
from core.media import media_path, media_prefix, store_media_path
from .models import SecurityEvent, VerificationDocument
from .permissions import CanReviewVerificationDocuments, IsAuthenticatedRespectStatus
from .throttles import AuthThrottle
from .verification_documents import normalize_verification_document
from .serializers import (
    ChangePasswordSerializer,
    LoginPinSerializer,
    LoginSerializer,
    LogoutSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    ProfilePhotoSerializer,
    RefreshRotationSerializer,
    RegisterSerializer,
    SELF_REGISTERABLE_ROLES,
    SetLoginPinSerializer,
    UserSummarySerializer,
    VerificationDocumentUploadSerializer,
)

logger = logging.getLogger(__name__)

User = get_user_model()

REGISTER_SHORTCODES = set(SELF_REGISTERABLE_ROLES)


def _verification_storage_name(file_url):
    """Map a stored ``/media/...`` path back to its storage-relative name.

    Returns ``None`` for anything that is not one of our uploads so a caller
    can 404 rather than attempt to open an arbitrary path.
    """
    path = media_path(file_url)
    if path is None:
        return None
    prefix = media_prefix()
    name = path[len(prefix):] if path.startswith(prefix) else path.lstrip("/")
    return name or None


class RegisterView(generics.CreateAPIView):
    """Public self-registration for SELF_REGISTERABLE_ROLES (patients,
    caregivers, blood donors, care professionals and facilities — never
    administrative roles). Response returns the signed-in JWT pair + safe user
    summary and a ``verification_required`` hint so clients route professionals
    and facilities into the C5 document-verification pipeline on signup."""

    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = serializer.save()
        return Response(
            {
                "access": result["access"],
                "refresh": result["refresh"],
                "user": UserSummarySerializer(
                    result["user"], context={"request": request}
                ).data,
                "verification_required": result.get("verification_required", False),
            },
            status=status.HTTP_201_CREATED,
        )


class SetLoginPinView(generics.GenericAPIView):
    """Configure the authenticated account's 4-digit login PIN.

    Offered right after the first email+password sign-in (and re-runnable to
    change it). The PIN is hashed server-side; the response carries no PIN
    material.
    """

    serializer_class = SetLoginPinSerializer
    permission_classes = [IsAuthenticatedRespectStatus]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(status=status.HTTP_204_NO_CONTENT)


class LoginPinView(generics.GenericAPIView):
    """PIN sign-in for a device-remembered identity (email/phone + 4 digits).

    Uniform failure responses so account existence/PIN state is never disclosed
    (NFR-SEC-007); auth-throttled per identity to bound PIN guessing.
    """

    serializer_class = LoginPinSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        tokens = serializer.validated_data["tokens"]
        return Response(
            {
                "access": tokens["access"],
                "refresh": tokens["refresh"],
                "user": UserSummarySerializer(user, context={"request": request}).data,
            }
        )


class LoginView(generics.GenericAPIView):
    """Email-or-phone login (§ API design). Uniform failure responses so an
    account's existence is never disclosed (NFR-SEC-007)."""

    serializer_class = LoginSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        tokens = serializer.validated_data["tokens"]
        return Response(
            {
                "access": tokens["access"],
                "refresh": tokens["refresh"],
                "user": UserSummarySerializer(user, context={"request": request}).data,
            }
        )


class LogoutView(generics.GenericAPIView):
    """Revoke the presented refresh token (denylist its jti) so the session
    cannot be replayed. Requires the refresh token in the body."""

    serializer_class = LogoutSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({"detail": "Signed out."}, status=status.HTTP_205_RESET_CONTENT)


class RefreshView(TokenRefreshView):
    """Rotate the JWT refresh token (admin-aware TTL §4.16) and re-check that
    the account status still permits access."""

    serializer_class = RefreshRotationSerializer
    throttle_classes = [AuthThrottle]


class MeView(generics.RetrieveAPIView):
    """Authenticated identity + safe profile. Client state source for role-
    aware navigation (4.4): returns roles + account_status server-side only."""

    serializer_class = UserSummarySerializer
    permission_classes = [IsAuthenticatedRespectStatus]

    def get_object(self):
        return self.request.user


class MeUploadPhotoView(APIView):
    """Upload (or replace) the authenticated user's profile photo.

    Accepts ``multipart/form-data`` with a single ``image`` file (JPEG/PNG/
    WebP ≤ 5 MB). The exact same server-side validation + JPEG re-encoding as
    news covers is applied, the normalized file is stored under the user's uid
    (overwriting prior avatars), and ``profile_photo_url`` is set so the new
    photo is picked up by ``/me`` and every subsequent login response. Only the
    owner may upload (characteristic-of-the-requestor gate, §35).
    """

    permission_classes = [IsAuthenticatedRespectStatus]
    throttle_classes = [AuthThrottle]
    serializer_class = ProfilePhotoSerializer

    @staticmethod
    def _stored_name_from_url(url):
        """Recover the storage key from a previously stored absolute URL."""
        if not url:
            return ""
        path = urlparse(url).path or ""
        prefix = settings.MEDIA_URL
        if prefix and path.startswith(prefix):
            return path[len(prefix):]
        # Tolerate a legacy relative "media/" prefix written before MEDIA_URL
        # was corrected, so old rows can still be cleaned up.
        if path.startswith("media/"):
            return path[len("media/"):]
        return ""

    @transaction.atomic
    def post(self, request):
        serializer = self.serializer_class(data=request.data)
        serializer.is_valid(raise_exception=True)
        image = serializer.validated_data["image"]
        user = request.user
        try:
            buffer, _content_type = upload_validation.normalize_cover_image(image)
        except DjangoValidationError as exc:
            raise ValidationError({"image": exc.messages})
        storage_key = f"accounts/avatars/{user.uid}.jpg"
        previous_name = self._stored_name_from_url(user.profile_photo_url)
        # `default_storage.save()` never overwrites — when the name already
        # exists it appends a random suffix. Left alone, every photo change
        # would orphan the previous object *and* leave the URL moving to a new
        # suffixed name on every upload. Clear both the deterministic key and
        # any legacy name the account was pointing at, so one stable object
        # per user is always served.
        replaced = False
        for stale in {storage_key, previous_name or ""}:
            if not stale or not default_storage.exists(stale):
                continue
            try:
                default_storage.delete(stale)
            except Exception:  # pragma: no cover - storage backend failure
                logger.warning("Could not delete previous avatar %s", stale, exc_info=True)
            replaced = True
        stored_name = default_storage.save(storage_key, ContentFile(buffer.getvalue()))
        # Persist the backend-relative path only. The absolute form is built
        # when the response is rendered (core.media), so a stale or internal
        # request Host can never be pinned into the row.
        user.profile_photo_url = store_media_path(stored_name)
        # Durable copy alongside the storage file (see User.profile_photo_data):
        # on ephemeral hosts the file vanishes on redeploy, while these bytes
        # keep every visible avatar rendering.
        user.profile_photo_data = buffer.getvalue()
        user.save(
            update_fields=["profile_photo_url", "profile_photo_data", "updated_at"]
        )
        record_audit(
            actor=user,
            action_code="accounts.profile_photo_updated",
            resource_type="user",
            resource_id=user.pk,
            request=request,
            # Non-PHI: a photo change is audited, never the image itself.
            details={"replaced_previous": replaced, "stored_name": stored_name[:200]},
        )
        SecurityEvent.objects.create(user=user, event_type="PROFILE_UPDATED")
        return Response(
            UserSummarySerializer(user, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )


class ProfilePhotoView(APIView):
    """GET ``/media/accounts/avatars/{uid}.jpg`` — durable public avatar route.

    Registered in ``config/urls.py`` *independently* of ``SERVE_MEDIA`` so
    profile pictures keep rendering in production, where that switch is off and
    the disk is wiped on every redeploy — the combination that once made every
    visible avatar a 404. The route is deliberately limited to this one
    deterministic avatar path: avatars are identity-only, non-PHI profile
    images (network clients fetch them without auth headers, so the view is
    anonymous-readable), and every other uploaded file still follows the
    ``SERVE_MEDIA`` switch or authenticated flows.

    Bytes come from ``User.profile_photo_data`` first; rows written before that
    column existed fall back to the storage-backend file. A missing photo is a
    plain 404.
    """

    authentication_classes: list = []
    permission_classes = [permissions.AllowAny]

    def get(self, request, uid):
        user = get_user_model().objects.filter(
            uid=uid, deleted_at__isnull=True
        ).first()
        if user is None or not user.profile_photo_url:
            raise NotFound("Not found.")
        payload = bytes(user.profile_photo_data) if user.profile_photo_data else b""
        if not payload:
            stored = MeUploadPhotoView._stored_name_from_url(user.profile_photo_url)
            if not stored or not default_storage.exists(stored):
                raise NotFound("Not found.")
            try:
                with default_storage.open(stored) as handle:
                    payload = handle.read()
            except OSError:
                raise NotFound("Not found.")
        return HttpResponse(
            payload,
            content_type="image/jpeg",
            headers={"Cache-Control": "private, max-age=300"},
        )


class VerificationDocumentUploadView(APIView):
    """Upload one government-issued verification document (C5 pipeline).

    Any authenticated applicant (usually a just-registered professional or
    facility role) uploads a scan/photo of a single document. Images are
    re-encoded to JPEG and therefore legible for a reviewer; PDFs are stored
    raw but magic-byte-validated. The response returns ``doc_type`` +
    ``file_url`` (a storage key) ready to attach to the doctors/facilities
    verification-submit endpoints — the document is not part of the profile
    until the applicant submits the full verification bundle.
    """

    permission_classes = [IsAuthenticatedRespectStatus]
    serializer_class = VerificationDocumentUploadSerializer
    throttle_classes = [AuthThrottle]

    @transaction.atomic
    def post(self, request):
        serializer = self.serializer_class(data=request.data)
        serializer.is_valid(raise_exception=True)
        doc_type = serializer.validated_data["doc_type"]
        upload = serializer.validated_data["file"]
        user = request.user
        try:
            buffer, content_type, ext = normalize_verification_document(upload)
        except DjangoValidationError as exc:
            raise ValidationError({"file": exc.messages})
        storage_key = f"certification_verification/{user.uid}/{uuid.uuid4().hex}.{ext}"
        stored_name = default_storage.save(
            storage_key, ContentFile(buffer.getvalue())
        )
        record_audit(
            actor=user,
            action_code="accounts.verification_document_uploaded",
            resource_type="user",
            resource_id=user.pk,
            request=request,
            details={"doc_type": doc_type, "stored_name": stored_name[:200]},
        )
        SecurityEvent.objects.create(user=user, event_type="PROFILE_UPDATED")
        return Response(
            {
                "doc_type": doc_type,
                "file_url": store_media_path(stored_name),
                "file_name": getattr(upload, "name", "") or "",
                "content_type": content_type,
            },
            status=status.HTTP_201_CREATED,
        )


class AdminVerificationDocumentView(APIView):
    """GET /admin/verification-documents/{pk} — stream one submitted document.

    A C6 reviewer (``doctors.verify`` / ``facilities.verify``) opens the exact
    file an applicant attached so the approve/reject decision rests on the
    evidence, not on a summary. The stored object is streamed through Django —
    never a public URL — and every open is written to the audit trail so access
    to a government ID / license is always accounted for.
    """

    permission_classes = [IsAuthenticatedRespectStatus, CanReviewVerificationDocuments]

    @extend_schema(responses={(200, "application/octet-stream"): OpenApiTypes.BINARY})
    def get(self, request, pk=None):
        doc = (
            VerificationDocument.objects.filter(pk=pk).select_related("user").first()
        )
        if doc is None:
            raise NotFound("Verification document not found.")
        name = _verification_storage_name(doc.file_url)
        if name is None:
            raise NotFound("The stored document is unavailable.")
        try:
            handle = default_storage.open(name, "rb")
        except (FileNotFoundError, OSError):
            raise NotFound("The stored document is no longer available.")
        content_type = mimetypes.guess_type(name)[0] or "application/octet-stream"
        record_audit(
            actor=request.user,
            action_code="accounts.verification_document_viewed",
            resource_type="verification_document",
            resource_id=doc.pk,
            request=request,
            details={"doc_type": doc.doc_type, "applicant_uid": str(doc.user.uid)},
        )
        response = FileResponse(handle, content_type=content_type)
        response["Content-Disposition"] = f'inline; filename="{os.path.basename(name)}"'
        return response


class PasswordResetRequestView(generics.GenericAPIView):
    """Always returns 202 and a uniform body so account existence is never
    disclosed (§87 / NFR-SEC-007). Emits a one-time hashed token via email."""

    serializer_class = PasswordResetRequestSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(
            {"detail": "If that account exists, a reset link has been sent."},
            status=status.HTTP_202_ACCEPTED,
        )


class PasswordResetConfirmView(generics.GenericAPIView):
    """Confirm a password reset with a valid one-time token, set the new
    passwordفق (server-side). Denylists prior sessions."""

    serializer_class = PasswordResetConfirmSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({"detail": "Your password has been reset. Please sign in."})


class ChangePasswordView(generics.GenericAPIView):
    """Authenticated password change; requires the current password."""

    serializer_class = ChangePasswordSerializer
    permission_classes = [IsAuthenticatedRespectStatus]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({"detail": "Password updated."})


__all__ = [
    "RegisterView",
    "LoginView",
    "LogoutView",
    "RefreshView",
    "MeView",
    "MeUploadPhotoView",
    "VerificationDocumentUploadView",
    "EmailVerifyView",
    "EmailVerifyResendView",
    "PasswordResetRequestView",
    "PasswordResetConfirmView",
    "ChangePasswordView",
]
