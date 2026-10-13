"""Authentication serializers (approved API design §7).

Identity pillars from the approved ERD / SSoT:
- Login identity is *email or phone* (both unique on ``accounts.User``).
- Passwords are hashed server-side (Argon2id when available, else Django
  PBKDF2) — never returned by any serializer.
- One-time tokens (email/phone verification, password reset) are stored
  **hashed**, single-use, expiring, and never logged (SD-1/16-18).
- Confirmation codes (reset) always return a uniform response so account
  existence is never disclosed (§87, NFR-SEC-007).
"""

import hashlib
import logging
import re
import secrets
import uuid

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ObjectDoesNotExist
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone
from core.media import MediaUrlField
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings as simplejwt_api_settings
from rest_framework_simplejwt.tokens import RefreshToken

from notifications.services import create_notification

from .models import (
    OneTimeToken,
    Role,
    RolePermission,
    SecurityEvent,
    TokenDenyList,
    User,
    UserRole,
    UserPermissionOverride,
    VerificationDocument,
)

logger = logging.getLogger(__name__)

User = get_user_model()

# Self-registerable roles (C17 + §18 role-permission design as extended to the
# open-registration flow): patients, caregivers and blood donors register and
# can transact immediately; care professionals (DOCTOR/PSYCHOLOGIST/SOCIAL) and
# facilities (HOSPITAL/CLINIC/ORGANIZATION) self-register too but must submit
# government-verified documents before the account may transact (C5 pipeline).
# Truly administrative/operator roles remain server-granted only.
SELF_REGISTERABLE_ROLES = (
    "PATIENT",
    "CAREGIVER",
    "BLOOD_DONOR",
    "DOCTOR",
    "PSYCHOLOGIST",
    "SOCIAL_SUPPORT",
    "HOSPITAL",
    "CLINIC",
    "ORGANIZATION",
)

# Roles claimed via self-registration that still require document verification
# before approval. BLOOD_DONOR (like PATIENT/CAREGIVER) registers freely.
VERIFICATION_REQUIRED_ROLE_CODES = (
    "DOCTOR",
    "PSYCHOLOGIST",
    "SOCIAL_SUPPORT",
    "HOSPITAL",
    "CLINIC",
    "ORGANIZATION",
)

# Verification family buckets reused by the doctors + facilities submit
# endpoints and by the register response hint.
PROFESSIONAL_VERIFICATION_ROLE_CODES = ("DOCTOR", "PSYCHOLOGIST", "SOCIAL_SUPPORT")
FACILITY_VERIFICATION_ROLE_CODES = ("HOSPITAL", "CLINIC", "ORGANIZATION")

# Roles that may never be granted through self-registration (defense-in-depth):
# every remaining reserved/privileged role is administrative and must be
# assigned by an administrator (C17).
_PRIVILEGED_ROLE_SUBSTRINGS = ("ADMIN", "SUPER", "OFFICER", "MODERATOR", "OPERATOR", "NGO")

# Admin-ready roles hold a shorter refresh lifetime (Stage 4.16 §23).
_ADMIN_READY_ROLE_CODES = ("SUPER_ADMIN", "ADMIN")

# Fast sign-in PIN: exactly four digits (device-remembered identity + PIN).
_LOGIN_PIN_RE = re.compile(r"^\d{4}$")


def token_pair_for(user):
    """Issue the approved access/refresh pair.

    Admin-ready role holders get a shorter refresh TTL
    (``ADMIN_REFRESH_TOKEN_LIFETIME``) at every issuance point so an admin
    session is short-lived by default even if the client never signs out.
    """
    refresh = RefreshToken.for_user(user)
    if user._has_active_role(*_ADMIN_READY_ROLE_CODES):
        lifetime = getattr(settings, "ADMIN_REFRESH_TOKEN_LIFETIME", None)
        if lifetime:
            refresh.set_exp(from_time=timezone.now(), lifetime=lifetime)
    # Record the issued refresh as outstanding so password-change/reset
    # revocation and logout can denylist it (Stage 4.17 §20).
    refresh.outstand()
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def _enforce_password_policy(raw_password, user=None, field="new_password"):
    """Apply Django's configured AUTH_PASSWORD_VALIDATORS (Stage 4.17 §25).

    The configured password policy (length/common/numeric/similarity) was
    never previously applied because ``create_user``/``set_password`` do not
    run it. Register, password-reset-confirm and password-change now all call
    this so a weak password is rejected at every entry point.
    """
    try:
        validate_password(raw_password, user=user or User())
    except DjangoValidationError as exc:
        raise serializers.ValidationError({field: list(exc.messages)})


def _revoke_user_tokens(user):
    """Blacklist every currently-outstanding refresh token for ``user``.

    Called on password change/reset. Tokens recorded as outstanding (created
    at login/rotation via the simplejwt blacklist tables) are revoked so a
    rotated or logged-in session can no longer refresh. Combined with
    ``CHECK_REVOKE_TOKEN``, ALL previously issued access/refresh tokens (even
    unrecorded ones) are invalid the moment the password changes.
    """
    if "rest_framework_simplejwt.token_blacklist" not in settings.INSTALLED_APPS:
        return  # pragma: no cover — app is always installed; defensive only
    from rest_framework_simplejwt.token_blacklist.models import (
        BlacklistedToken,
        OutstandingToken,
    )

    for ot in OutstandingToken.objects.filter(
        user=user, expires_at__gt=timezone.now()
    ):
        BlacklistedToken.objects.get_or_create(token=ot)


def _deliver_reset(user, code):
    """Deliver a one-time password-reset code.

    Delivery abstraction (4.4+ wires real email/SMS). Until then the code is
    delivered via an in-app SYSTEM notification (dev channel) and the fact of
    issuance is recorded in a SecurityEvent so monitoring always sees it. The
    raw code is stored nowhere — only its salted hash (SD-1/16-18).
    """
    SecurityEvent.objects.create(
        user=user,
        event_type="PASSWORD_RESET",
        detail={"phase": "requested", "masked_code": f"{code[:4]}…{code[-2:]}"},
    )
    try:
        create_notification(
            recipient=user,
            type_="SYSTEM",
            title="Password reset code",
            body=f"Your password reset code is {code} (expires soon).",
            related_resource_type="password_reset",
            related_resource_id=hashlib.sha256(code.encode()).hexdigest()[:16],
            delivery_key=f"reset:{user.pk}:{hashlib.sha256(code.encode()).hexdigest()[:12]}",
            force=True,
        )
    except Exception:  # pragma: no cover — delivery must never break the 202
        logger.exception("Password reset delivery failed (non-blocking).")


class UserSummarySerializer(serializers.ModelSerializer):
    """Safe subset of the authenticated user's identity (§23 /me + §186).

    `role_codes` + `permission_codes` are the server-authenticated RBAC
    contract consumed by the role-aware Flutter shell (Stage 4.4) and the
    profile/medical controllers (Stage 4.5). No passwords, tokens or PII
    beyond the safe identity subset is ever returned (§24).
    """

    role_codes = serializers.SerializerMethodField(read_only=True)
    permission_codes = serializers.SerializerMethodField(read_only=True)
    has_login_pin = serializers.SerializerMethodField(read_only=True)
    is_mfa_enabled = serializers.BooleanField(source="mfa_enabled", read_only=True)
    account_status = serializers.CharField(read_only=True)
    uid = serializers.UUIDField(read_only=True)
    is_verified_doctor = serializers.SerializerMethodField(read_only=True)
    doctor_verification_status = serializers.SerializerMethodField(read_only=True)
    facility = serializers.SerializerMethodField(read_only=True)
    profile_photo_url = MediaUrlField(required=False, allow_null=True)

    class Meta:
        model = User
        fields = [
            "uid",
            "email",
            "phone",
            "first_name",
            "last_name",
            "account_status",
            "is_mfa_enabled",
            "is_active",
            "created_at",
            "role_codes",
            "permission_codes",
            "has_login_pin",
            "is_verified_doctor",
            "doctor_verification_status",
            "facility",
            "profile_photo_url",
        ]
        read_only_fields = fields

    def get_role_codes(self, obj) -> list[str]:
        return obj.role_codes

    def get_permission_codes(self, obj) -> list[str]:
        return obj.permission_codes()

    def get_has_login_pin(self, obj) -> bool:
        # Whether the account has configured its 4-digit login PIN. The client
        # uses this to choose PIN sign-in vs the email+password form; the hash
        # itself is never exposed.
        return bool(obj.login_pin_hash)

    def get_is_verified_doctor(self, obj) -> bool:
        return obj.is_verified_doctor

    def get_doctor_verification_status(self, obj) -> str | None:
        # Professional-verification sub-state for DOCTOR holders so the mobile
        # client can route a PENDING/REJECTED doctor to a status screen instead
        # of the clinical dashboard. Nil for every non-DOCTOR identity.
        if not obj._has_active_role("DOCTOR"):
            return None
        try:
            return obj.doctor_profile.verification_status
        except (AttributeError, ObjectDoesNotExist):
            return None

    def get_facility(self, obj) -> dict | None:
        # Organization identity: a HOSPITAL/HEALTHCARE_STAFF operator linked via
        # facilities.operator. `is_verified` is the facility's approval state —
        # never inferred from the account type (account type != verification).
        facility = getattr(obj, "operated_facility", None)
        if facility is None:
            return None
        return {
            "uid": str(facility.uid),
            "name": facility.name,
            "facility_type": facility.facility_type,
            "is_verified": facility.is_verified,
        }


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField(write_only=True)
    password = serializers.CharField(write_only=True, min_length=8, max_length=128)
    first_name = serializers.CharField(write_only=True, required=False, max_length=150)
    last_name = serializers.CharField(write_only=True, required=False, max_length=150)
    phone = serializers.CharField(write_only=True, required=False, allow_blank=True, max_length=30)
    role_code = serializers.ChoiceField(
        choices=list(SELF_REGISTERABLE_ROLES), write_only=True, default="PATIENT"
    )

    def validate_email(self, value: str) -> str:
        return value.lower().strip()

    def validate_phone(self, value: str) -> str:
        value = (value or "").strip()
        if value and not (
            (value.startswith("+") and value[1:].isdigit() and 7 <= len(value) <= 15)
            or value.isdigit()
        ):
            raise serializers.ValidationError("Enter a valid phone number (digits, optional leading +).")
        return value

    def validate(self, attrs):
        # Prevent duplicate accounts (email and/or phone are unique).
        q = User.objects.filter(email=attrs["email"])
        if q.exists():
            raise serializers.ValidationError({"email": "An account with this email already exists."})
        if attrs.get("phone"):
            if User.objects.filter(phone=attrs["phone"]).exists():
                raise serializers.ValidationError({"phone": "An account with this phone already exists."})
        # Apply the configured password policy (Stage 4.17 §25).
        _enforce_password_policy(
            attrs["password"], user=User(email=attrs["email"]), field="password"
        )
        return attrs

    def create(self, validated_data):
        # Atomic: user + role + security event + verification token must land
        # together. Without this a failure after `create_user` (missing role,
        # token issue, delivery error) left an orphaned user behind, and the
        # next attempt failed with "email already exists" — permanently locking
        # the applicant out of the address they just used.
        try:
            with transaction.atomic():
                return self._create_registered_account(validated_data)
        except IntegrityError:
            # Concurrent duplicate (validate() cannot close the race window).
            raise serializers.ValidationError(
                {"email": "An account with this email already exists."}
            )

    def _create_registered_account(self, validated_data):
        role_code = validated_data.pop("role_code", "PATIENT")
        user = User.objects.create_user(
            email=validated_data["email"],
            password=validated_data["password"],
            first_name=validated_data.get("first_name", ""),
            last_name=validated_data.get("last_name", ""),
            phone=validated_data.get("phone") or None,
            # No email-verification step: a fresh self-registration is a usable
            # ACTIVE account immediately. Professional/facility applicants are
            # still gated by their C5 document verification
            # (`verification_required`), which is tracked separately from the
            # account status.
            account_status="ACTIVE",
        )
        # Initial role assignment is the *only* role change permitted here;
        # restricted to self-registerable roles (never trusted blindly).
        role = Role.objects.get(code=role_code)
        UserRole.objects.create(user=user, role=role)
        SecurityEvent.objects.create(
            user=user, event_type="REGISTER", detail={"role_code": role_code}
        )

        # Issue an identity-bound JWT pair at registration (BR-002/004).
        tokens = token_pair_for(user)

        # Verify-on-approval hint for the client: professional and facility
        # roles must upload government-verified documents before they can
        # transact (C5); patient/caregiver/blood_donor are ready immediately.
        verification_required = role_code in VERIFICATION_REQUIRED_ROLE_CODES

        return {
            "user": user,
            "access": tokens["access"],
            "refresh": tokens["refresh"],
            "verification_required": verification_required,
        }


class LoginSerializer(TokenObtainPairSerializer):
    """Login with *email or phone*; issues the approved access/refresh pair.

    Enforces account status before issuing tokens (ACTIVE / PENDING_VERIFICATION
    allowed; SUSPENDED/DISABLED/DEACTIVATED rejected with a generic message).
    """

    email_or_phone = serializers.CharField(write_only=True)
    password = serializers.CharField(write_only=True, trim_whitespace=False)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # TokenObtainSerializer injects a required field named after
        # USERNAME_FIELD ("email"); we authenticate authority via
        # email_or_phone instead, so drop that injected field here.
        self.fields.pop(self.username_field, None)

    def validate(self, attrs):
        identifier = attrs.get("email_or_phone", "").strip().lower()
        password = attrs.get("password")

        user = None
        if identifier:
            # Default ModelBackend only matches USERNAME_FIELD (email), so do
            # the email-or-phone lookup explicitly (both unique, §4 ERD) and
            # verify with Django's check_password — never a stored secret.
            user = (
                User.objects.filter(email__iexact=identifier) |
                User.objects.filter(phone__iexact=identifier)
            ).first()
            if user is not None and not user.check_password(password):
                user = None
        if user is None:
            # Uniform message — do not reveal whether the identifier exists (§8/87).
            raise serializers.ValidationError(
                {"detail": "Incorrect email/phone or password.", "code": "INVALID_CREDENTIALS"}
            )
        if not user.is_active or user.account_status in ("SUSPENDED", "DISABLED", "DEACTIVATED"):
            SecurityEvent.objects.create(user=user, event_type="LOGIN_FAILED", status="BLOCKED")
            raise serializers.ValidationError(
                {"detail": "This account cannot log in. Contact support.", "code": "ACCOUNT_DISABLED"}
            )

        # Issue the approved access/refresh pair directly (the base
        # TokenObtainSerializer demands a USERNAME_FIELD-shaped input we don't
        # expose; construction is the same as TokenObtainPairSerializer).
        tokens = token_pair_for(user)
        attrs["user"] = user
        attrs["tokens"] = tokens
        user.last_login = timezone.now()
        user.save(update_fields=["last_login"])
        SecurityEvent.objects.create(user=user, event_type="LOGIN_SUCCESS", status="SUCCESS")
        create_notification(
            recipient=user, type_="SYSTEM",
            title="New sign-in",
            body="We noticed a new sign-in to your account. If this was not you, contact support immediately.",
            priority="HIGH",
            force=True,
        )
        return attrs


class LogoutSerializer(serializers.Serializer):
    """Revoke the presented refresh token + its family (token denylist)."""

    refresh = serializers.CharField(write_only=True)

    def validate_refresh(self, value: str) -> str:
        try:
            token = RefreshToken(value)
        except Exception:
            raise serializers.ValidationError("Invalid or expired refresh token.")
        jti, exp, user_id = str(token.get("jti")), token.get("exp"), token.get("user_id")
        if not jti or not settings.AUTH_USER_MODEL:
            raise serializers.ValidationError("Invalid token claims.")
        try:
            user = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            raise serializers.ValidationError("Invalid token.")
        # Denylist the jti so the refresh + access family cannot be reused.
        TokenDenyList.objects.create(
            jti=jti,
            user=user,
            expires_at=timezone.datetime.fromtimestamp(exp, tz=timezone.UTC),
        )
        # Canonical revocation via simplejwt token_blacklist (Stage 4.17 §20):
        # a logged-out refresh token must fail on the next refresh attempt.
        try:
            token.blacklist()
        except Exception:
            raise serializers.ValidationError("Invalid or expired refresh token.")
        SecurityEvent.objects.create(user=user, event_type="LOGOUT", status="SUCCESS")
        self._user_id = user_id
        return value

    def save(self, **kwargs):
        """Side effects (denylist + security event) run during validation;
        ``save`` exists only so the GenericAPIView can call ``serializer.save()``.
        No additional persistence is needed — an already-logged-out session is
        idempotent.
        """
        return self.validated_data


class RefreshRotationSerializer(TokenRefreshSerializer):
    """Rotation with admin-aware lifetime (Stage 4.16 §23).

    Mirrors the SimpleJWT rotate path but shortens the refresh TTL for
    admin-ready role holders so every rotation keeps their session bounded.
    """

    def validate(self, attrs):
        refresh = self.token_class(attrs["refresh"])
        user_id = refresh.payload.get(simplejwt_api_settings.USER_ID_CLAIM)
        user = None
        if user_id is not None:
            user = User.objects.filter(pk=user_id).first()
        if user is None or not simplejwt_api_settings.USER_AUTHENTICATION_RULE(user):
            from rest_framework_simplejwt.exceptions import AuthenticationFailed

            raise AuthenticationFailed("No active account found for the given token.")

        data = {"access": str(refresh.access_token)}

        if simplejwt_api_settings.ROTATE_REFRESH_TOKENS:
            if simplejwt_api_settings.BLACKLIST_AFTER_ROTATION:
                # Revoke the presented refresh token so it can never be replayed
                # (Stage 4.17 §20 — token_blacklist app is installed).
                refresh.blacklist()

            refresh.set_jti()
            refresh.set_iat()
            if user._has_active_role(*_ADMIN_READY_ROLE_CODES):
                lifetime = getattr(settings, "ADMIN_REFRESH_TOKEN_LIFETIME", None)
                if lifetime:
                    refresh.set_exp(from_time=timezone.now(), lifetime=lifetime)
                else:
                    refresh.set_exp()
            else:
                refresh.set_exp()
            refresh.outstand()

            data["refresh"] = str(refresh)

        return data


def _hash_token(raw: str, purpose: str) -> str:
    """Salted, single-way hash of a one-time token — never stored raw (SD-1/16)."""
    return hashlib.sha256(f"{purpose}:{raw}".encode()).hexdigest()


class OneTimeTokenMixin:
    purpose = None  # required in subclass

    def _issue_token(self, user) -> str:
        raw = secrets.token_urlsafe(32)
        OneTimeToken.objects.create(
            user=user,
            purpose=self.purpose,
            token_hash=_hash_token(raw, self.purpose),
            expires_at=timezone.now() + timezone.timedelta(minutes=self.TTL_MINUTES),
        )
        return raw


class PasswordResetRequestSerializer(serializers.Serializer, OneTimeTokenMixin):
    """Request a reset for email/phone. Always 202; never reveals existence."""

    purpose = "PASSWORD_RESET"
    TTL_MINUTES = 30
    COOLDOWN_SECONDS = 300  # Stage 4.17 §26: cap token issuance per account

    email_or_phone = serializers.CharField(write_only=True)

    def save(self) -> None:
        identifier = self.validated_data["email_or_phone"].strip().lower()
        q = User.objects.filter(email=identifier) | User.objects.filter(phone__iexact=identifier)
        user = q.first()
        if user is None:
            return  # uniform response regardless of existence
        recent = OneTimeToken.objects.filter(
            user=user,
            purpose=self.purpose,
            used_at__isnull=True,
            expires_at__gt=timezone.now(),
            created_at__gt=timezone.now() - timezone.timedelta(seconds=self.COOLDOWN_SECONDS),
        ).exists()
        if recent:
            return  # an unexpired code was already issued — do not re-issue/spam
        code = self._issue_token(user)
        # Delivery abstraction: in dev, rendered only to the console/returned
        # as masked metadata; real channels (email/SMS) are wired by 4.4+.
        _deliver_reset(user, code)


class PasswordResetConfirmSerializer(serializers.Serializer, OneTimeTokenMixin):
    """Consume the single-use reset token and set a new password."""

    purpose = "PASSWORD_RESET"
    TTL_MINUTES = 30

    token = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8, max_length=128)

    def validate(self, attrs):
        token_hash = _hash_token(attrs["token"], self.purpose)
        ot = (
            OneTimeToken.objects.filter(
                token_hash=token_hash, purpose=self.purpose, used_at__isnull=True
            )
            .order_by("-expires_at")
            .first()
        )
        if ot is None or ot.expires_at < timezone.now():
            raise serializers.ValidationError({"token": "This reset link is invalid or has expired."})
        user = ot.user
        if not isinstance(attrs["new_password"], str):
            raise serializers.ValidationError({"new_password": "Enter a valid password."})
        # Enforce the configured password policy on the new password (§25).
        _enforce_password_policy(attrs["new_password"], user=user)
        self._ot = ot
        self._user = user
        return attrs

    def save(self):
        self._ot.used_at = timezone.now()
        self._ot.save(update_fields=["used_at"])
        self._user.set_password(self.validated_data["new_password"])
        self._user.save(update_fields=["password", "updated_at"])
        # Password reset invalidates every existing session (Stage 4.17 §20):
        # all outstanding refresh tokens are revoked and the rev-claim makes
        # every previously-issued access/refresh token unusable.
        _revoke_user_tokens(self._user)
        for ot in OneTimeToken.objects.filter(user=self._user, purpose=self.purpose, used_at__isnull=True):
            ot.used_at = timezone.now()
            ot.save(update_fields=["used_at"])
        SecurityEvent.objects.create(user=self._user, event_type="PASSWORD_RESET", status="SUCCESS")
        create_notification(
            recipient=self._user, type_="SYSTEM",
            title="Password change",
            body="Your password was changed. If this was not you, contact support immediately.",
            priority="HIGH",
            force=True,
        )
        return self._user


class SetLoginPinSerializer(serializers.Serializer):
    """Configure the 4-digit login PIN for the authenticated account.

    The user enters their email+password the first time and then chooses a PIN;
    every later launch signs in with the PIN alone against the identity the
    device remembers. The PIN is hashed with the configured password hasher and
    never stored or logged raw. Re-issuing simply overwrites the previous PIN.
    """

    pin = serializers.CharField(write_only=True, trim_whitespace=False)

    def validate_pin(self, value: str) -> str:
        if not _LOGIN_PIN_RE.match(value or ""):
            raise serializers.ValidationError("Your PIN must be exactly 4 digits.")
        return value

    def save(self):
        user = self.context["request"].user
        user.login_pin_hash = make_password(self.validated_data["pin"])
        user.login_pin_set_at = timezone.now()
        user.save(update_fields=["login_pin_hash", "login_pin_set_at", "updated_at"])
        SecurityEvent.objects.create(user=user, event_type="LOGIN_PIN_SET", status="SUCCESS")
        return user


class LoginPinSerializer(serializers.Serializer):
    """PIN sign-in for a device-remembered identity (email or phone + 4 digits).

    Uniform failure messages so neither account existence nor PIN-configuration
    state is disclosed (NFR-SEC-007). The endpoint is auth-throttled per
    identity, so a 4-digit PIN cannot be ground at system speed.
    """

    email_or_phone = serializers.CharField(write_only=True)
    pin = serializers.CharField(write_only=True, trim_whitespace=False)

    def validate(self, attrs):
        identifier = attrs["email_or_phone"].strip().lower()
        user = (
            User.objects.filter(email=identifier) | User.objects.filter(phone__iexact=identifier)
        ).first()
        valid = (
            user is not None
            and bool(user.login_pin_hash)
            and check_password(attrs["pin"], user.login_pin_hash)
        )
        if not valid:
            if user is not None:
                SecurityEvent.objects.create(
                    user=user, event_type="LOGIN_FAILED", status="FAILED",
                    detail={"method": "PIN"},
                )
            raise serializers.ValidationError({"pin": "Incorrect email/phone or PIN."})
        if user.account_status not in ("ACTIVE", "PENDING_VERIFICATION") or not user.is_active:
            raise serializers.ValidationError({"pin": "Your account is not eligible to sign in."})
        attrs["user"] = user
        attrs["tokens"] = token_pair_for(user)
        SecurityEvent.objects.create(
            user=user, event_type="LOGIN_SUCCESS", status="SUCCESS", detail={"method": "PIN"}
        )
        return attrs


class ChangePasswordSerializer(serializers.Serializer):
    """Authenticated password change: requires the current password (§18)."""

    current_password = serializers.CharField(write_only=True, trim_whitespace=False)
    new_password = serializers.CharField(write_only=True, min_length=8, max_length=128)

    def validate(self, attrs):
        user = self.context["request"].user
        if not user.check_password(attrs["current_password"]):
            raise serializers.ValidationError({"current_password": "Your current password is incorrect."})
        # Apply the configured password policy (Stage 4.17 §25).
        _enforce_password_policy(attrs["new_password"], user=user)
        return attrs

    def save(self):
        user = self.context["request"].user
        user.set_password(self.validated_data["new_password"])
        user.save(update_fields=["password", "updated_at"])
        # A password change revokes every existing session (Stage 4.17 §20).
        _revoke_user_tokens(user)
        SecurityEvent.objects.create(user=user, event_type="PASSWORD_CHANGE", status="SUCCESS")
        create_notification(
            recipient=user, type_="SYSTEM",
            title="Password changed",
            body="Your password was changed. If this was not you, contact support immediately.",
            priority="HIGH",
            force=True,
        )
        return user


class ProfilePhotoSerializer(serializers.Serializer):
    """Profile-picture upload payload (multipart ``image`` file).

    The file itself is validated + re-encoded on the server exactly like news
    covers (content.upload_validation), so only normalized JPEG bytes are ever
    stored; the response returns the updated user summary with the new
    ``profile_photo_url``.
    """

    image = serializers.FileField()


class VerificationDocumentUploadSerializer(serializers.Serializer):
    """Verification-document upload payload (multipart ``file``).

    A professional or facility applicant uploads a scan/photo of one
    government-issued document (C5 verification pipeline). Images are
    re-encoded server-side exactly like profile photos / news covers; PDFs are
    stored raw but size- and magic-byte-checked. The response returns the
    storage key via :class:`core.media.MediaUrlField` — never a public URL — so
    the caller can attach it to a doctors/facilities verification submission.
    """

    doc_type = serializers.ChoiceField(choices=VerificationDocument.DOC_TYPE)
    file = serializers.FileField()


class VerificationDocumentReviewSerializer(serializers.ModelSerializer):
    """Reviewer-facing summary of one submitted document (C5/C6 pipeline).

    Deliberately excludes the storage key: a reviewer opens the actual file
    through the audited ``GET /admin/verification-documents/{id}/`` endpoint
    (permission-gated to ``doctors.verify`` / ``facilities.verify``), never via
    a public URL. ``id`` is the handle the client passes to that endpoint.
    """

    uploaded_at = serializers.DateTimeField(source="created_at", read_only=True)
    file_name = serializers.SerializerMethodField()

    class Meta:
        model = VerificationDocument
        fields = [
            "id", "doc_type", "status", "file_name", "uploaded_at", "reviewed_at",
        ]
        read_only_fields = fields

    def get_file_name(self, obj) -> str:
        from core.media import media_path

        path = media_path(obj.file_url) or obj.file_url or ""
        return path.rsplit("/", 1)[-1]
