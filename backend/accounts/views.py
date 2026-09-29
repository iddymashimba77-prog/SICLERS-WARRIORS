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

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from rest_framework import generics, permissions, status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from content import upload_validation
from .permissions import IsAuthenticatedRespectStatus
from .throttles import AuthThrottle
from .serializers import (
    ChangePasswordSerializer,
    EmailVerifyResendSerializer,
    EmailVerifySerializer,
    LoginSerializer,
    LogoutSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    ProfilePhotoSerializer,
    RefreshRotationSerializer,
    RegisterSerializer,
    UserSummarySerializer,
)

User = get_user_model()

REGISTER_SHORTCODES = {"PATIENT", "CAREGIVER"}


class RegisterView(generics.CreateAPIView):
    """Public self-registration. Only SELF_REGISTERABLE roles (PATIENT,
    CAREGIVER). Response returns the signed-in JWT pair + safe user summary;
    never role/permission claims granted beyond the serializer's approval."""

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
                "user": UserSummarySerializer(result["user"]).data,
                "email_verification_pending": result.get("email_verification_pending", False),
                "verify_token": result.get("verify_token"),
            },
            status=status.HTTP_201_CREATED,
        )


class EmailVerifyView(generics.GenericAPIView):
    """Consume the single-use email-verification code (FR-AUTH-004, AUTH-005).

    Transitions the account PENDING_VERIFICATION → ACTIVE. Idempotent for an
    already-verified account; invalid/expired codes are rejected uniformly.
    """

    serializer_class = EmailVerifySerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(status=status.HTTP_204_NO_CONTENT)


class EmailVerifyResendView(generics.GenericAPIView):
    """Re-issue an email-verification code. Always 202 + a uniform body so an
    account's existence is never disclosed (NFR-SEC-007); rate-limited."""

    serializer_class = EmailVerifyResendSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthThrottle]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(
            {"detail": "If that account is awaiting verification, a new code has been sent."},
            status=status.HTTP_202_ACCEPTED,
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
                "user": UserSummarySerializer(user).data,
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
        stored_name = default_storage.save(
            f"accounts/avatars/{user.uid}.jpg",
            ContentFile(buffer.getvalue()),
        )
        media_prefix = settings.MEDIA_URL
        if not media_prefix.startswith("/"):
            media_prefix = f"/{media_prefix}"
        user.profile_photo_url = request.build_absolute_uri(
            f"{media_prefix}{stored_name}"
        )
        user.save(update_fields=["profile_photo_url", "updated_at"])
        return Response(
            UserSummarySerializer(user, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )


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
    "EmailVerifyView",
    "EmailVerifyResendView",
    "PasswordResetRequestView",
    "PasswordResetConfirmView",
    "ChangePasswordView",
]
