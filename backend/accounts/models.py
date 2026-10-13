"""Accounts / identity & access foundation.

Approved source of truth (Stage 4.2):
- docs/sdlc/03-system-design/erd/identity-access-erd.md  (users, roles, ...)
- docs/sdlc/03-system-design/database-design.md          (column types, §4-§22)
- docs/sdlc/03-system-design/role-permission-design.md   (RBAC matrix, §3)
- AUTH_USER_MODEL = "accounts.User"  (approved §27 migration strategy (a): migrate a fresh/empty DB)
"""

import uuid

from django.contrib.auth.base_user import AbstractBaseUser
from django.contrib.auth.models import PermissionsMixin
from django.core.exceptions import ObjectDoesNotExist
from django.db import models


from django.contrib.auth.base_user import BaseUserManager


# Roles whose members are verified professionals (C5). Each still carries its own
# permission bundle; this tuple only answers "is this identity a professional
# whose registration has been confirmed", which is what the chat partner gate and
# the clinical-writer gate need.
PROFESSIONAL_ROLE_CODES = ("DOCTOR", "PSYCHOLOGIST", "SOCIAL_SUPPORT")

# Facility-operator role that runs on another role's permission bundle. CLINIC
# keeps its own identity code (role-aware navigation + registration card) but
# exercises exactly HOSPITAL's operating surface at the permission layer — so
# clinics and hospitals always behave identically, even as later seed migrations
# widen the operating bundle.
ROLE_GRANT_ALIASES = {"CLINIC": "HOSPITAL"}


class SWUserManager(BaseUserManager):
    """Custom manager — identity is `email` (unique, citext; login identity)."""

    use_in_migrations = True

    def _create_user(self, email, password=None, **extra_fields):
        # Deny-by-default: identities created through the manager start
        # PENDING_VERIFICATION unless the caller explicitly declares an
        # approved active/verified identity (e.g. a bootstrap superuser).
        extra_fields.setdefault(
            "account_status",
            "ACTIVE" if extra_fields.get("is_superuser") else "PENDING_VERIFICATION",
        )
        user = User(email=self.normalize_email(email), **extra_fields)
        if password:
            user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("account_status", "ACTIVE")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        user = self._create_user(email, password, **extra_fields)
        # Admin ability is NOT an unapproved `is_staff` column; it is the
        # RBAC gate: SUPER_ADMIN role via the approved user_roles join.
        if not UserRole.objects.filter(user=user, role__code="SUPER_ADMIN").exists():
            role = Role.objects.get(code="SUPER_ADMIN")
            UserRole.objects.create(user=user, role=role)
        return user


class User(AbstractBaseUser, PermissionsMixin):
    """Custom user — approved `accounts.User` (AUTH_USER_MODEL).

    Identity fields only (roles are M2M via `user_roles`, never a column;
    no bleeding role into a single-user model per approved ERD §5).
    """

    class Meta:
        db_table = "users"
        indexes = [
            models.Index(fields=["account_status"], name="users_account_status_idx"),
            models.Index(fields=["email"], name="users_email_lookup_idx"),
        ]
        constraints = [
            models.CheckConstraint(
                name="users_account_status_ck",
                condition=models.Q(account_status__in=[
                    "ACTIVE", "PENDING_VERIFICATION", "SUSPENDED",
                    "DISABLED", "DEACTIVATED",
                ]),
            ),
        ]

    id = models.BigAutoField(primary_key=True)
    uid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False, db_index=True)
    email = models.EmailField(max_length=255, unique=True, db_index=True)
    phone = models.CharField(max_length=30, unique=True, null=True, blank=True, db_index=True)
    # Optional 4-digit login PIN (hashed with the configured password hasher,
    # never stored or logged raw). Set by the user after their first
    # email+password sign-in so later launches can sign in with the PIN alone.
    # An empty hash means "PIN not configured" and the account uses password auth.
    login_pin_hash = models.CharField(max_length=128, blank=True, default="")
    login_pin_set_at = models.DateTimeField(null=True, blank=True)

    password_hash_legacy = models.CharField(max_length=255, blank=True)  # reserved; symmetric w/ Django password mgmt

    first_name = models.CharField(max_length=150, blank=True)
    last_name = models.CharField(max_length=150, blank=True)

    ACCOUNT_STATUS = (
        ("ACTIVE", "ACTIVE"),
        ("PENDING_VERIFICATION", "PENDING_VERIFICATION"),
        ("SUSPENDED", "SUSPENDED"),
        ("DISABLED", "DISABLED"),
        ("DEACTIVATED", "DEACTIVATED"),
    )
    account_status = models.CharField(max_length=40, choices=ACCOUNT_STATUS, default="PENDING_VERIFICATION")
    is_active = models.BooleanField(default=True)

    # Privacy: MFA secret stored encrypted (AES-GCM), never plaintext; bytea-esque via BinaryField.
    mfa_enabled = models.BooleanField(default=False)
    mfa_secret_encrypted = models.BinaryField(null=True, blank=True)

    profile_photo_url = models.CharField(max_length=500, null=True, blank=True)

    last_login_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)  # soft delete (§20)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    # Per-request permission cache (computed lazily; never stored).
    _perm_code_cache = None  # set in has_perm_code()

    objects = SWUserManager()

    def __str__(self):
        return self.email

    # --- Role & permission helpers (RBAC, Stage 4.4/4.5) ---------------------
    # These back the DRF permission gates (`accounts/permissions.py`) and the
    # profile/medical controllers. Computed from the approved `user_roles` →
    # `role_permissions` join + audited `user_permissions` overrides; nothing
    # is trusted from the client (§ role-permission design §21).

    @property
    def role_codes(self) -> list[str]:
        return [
            ur.role.code
            for ur in self.user_roles.filter(is_active=True).select_related("role")
        ]

    def _has_active_role(self, *codes: str) -> bool:
        active = {
            ur.role.code
            for ur in self.user_roles.filter(is_active=True).select_related("role")
        }
        expanded = set(active)
        for code in active:
            alias = ROLE_GRANT_ALIASES.get(code)
            if alias:
                expanded.add(alias)
        return bool(expanded & set(codes))

    @property
    def is_patient(self) -> bool:
        return self._has_active_role("PATIENT")

    @property
    def is_verified_patient(self) -> bool:
        # A patient may read/write health data only while ACTIVE; the doctors
        # professional-verification sub-state (doctors.verification_status)
        # connects here when the doctors model lands (Stage 4.x).
        return self.is_patient and self.account_status == "ACTIVE"

    @property
    def is_caregiver(self) -> bool:
        return self._has_active_role("CAREGIVER")

    @property
    def is_verified_professional(self) -> bool:
        """Any APPROVED professional: doctor, psychologist or support worker (C5).

        This is the gate that says "a human being has confirmed this identity".
        It is deliberately *not* the gate for clinical privileges: what someone
        may do clinically still comes from their role's permission bundle
        (C2/C3/C15), so being verified never widens access on its own.
        """
        if not (
            self._has_active_role(*PROFESSIONAL_ROLE_CODES)
            and self.account_status == "ACTIVE"
        ):
            return False
        try:
            profile = self.doctor_profile
        except (AttributeError, ObjectDoesNotExist):
            return False
        return profile.verification_status == "APPROVED"

    @property
    def is_verified_doctor(self) -> bool:
        # Role + account status + professional verification (BR-001, C5).
        # The `doctors` registry row must be APPROVED — registration never
        # auto-approves a DOCTOR (database-design §3.4, role-perm §20).
        # Strictly narrower than `is_verified_professional`: a psychologist with
        # an APPROVED registry row is not a doctor and must not satisfy a
        # doctor-only gate such as prescribing.
        if not self._has_active_role("DOCTOR"):
            return False
        try:
            profile = self.doctor_profile
        except (AttributeError, ObjectDoesNotExist):
            return False
        return (
            self.account_status == "ACTIVE"
            and profile.professional_type == "DOCTOR"
            and profile.verification_status == "APPROVED"
        )

    @property
    def is_verified_psychologist(self) -> bool:
        if not self._has_active_role("PSYCHOLOGIST"):
            return False
        try:
            profile = self.doctor_profile
        except (AttributeError, ObjectDoesNotExist):
            return False
        return (
            self.account_status == "ACTIVE"
            and profile.professional_type == "PSYCHOLOGIST"
            and profile.verification_status == "APPROVED"
        )

    @property
    def is_blood_donor(self) -> bool:
        return self._has_active_role("BLOOD_DONOR")

    @property
    def is_financial_donor(self) -> bool:
        return self._has_active_role("FINANCIAL_DONOR")

    @property
    def is_admin(self) -> bool:
        return self._has_active_role("SUPER_ADMIN", "ADMIN")

    @property
    def is_psychologist(self) -> bool:
        return self._has_active_role("PSYCHOLOGIST")

    @property
    def is_social_support(self) -> bool:
        return self._has_active_role("SOCIAL_SUPPORT")

    def permission_codes(self) -> list[str]:
        """Effective permission codes = role grants + ALLOW overrides, minus
        DENY overrides (deny-by-default; overrides are audited, §21).

        A role that is a grant alias (CLINIC == HOSPITAL operating bundle)
        resolves through its alias, so both facility labels always exercise the
        same abilities even as later seed migrations widen the operating bundle.
        """
        role_rows = list(
            self.user_roles.filter(is_active=True).select_related("role")
        )
        grant_role_ids = {ur.role_id for ur in role_rows}
        for ur in role_rows:
            alias = ROLE_GRANT_ALIASES.get(ur.role.code)
            if alias:
                grant_role_ids.update(
                    Role.objects.filter(code=alias).values_list("id", flat=True)
                )
        granted = set(
            Permission.objects.filter(
                role_permissions__role__id__in=grant_role_ids
            ).values_list("code", flat=True)
        )
        denied = set(
            Permission.objects.filter(
                user_overrides__user=self, user_overrides__effect="DENY"
            ).values_list("code", flat=True)
        )
        allowed = set(
            Permission.objects.filter(
                user_overrides__user=self, user_overrides__effect="ALLOW"
            ).values_list("code", flat=True)
        )
        return sorted((granted | allowed) - denied)

    def has_perm_code(self, code: str) -> bool:
        """True when the user holds the exact permission code (any active role
        or an audited ALLOW override), unless a DENY override hard-blocks it."""
        if self._perm_code_cache is None:
            self._perm_code_cache = set(self.permission_codes())
        return code in self._perm_code_cache


class Role(models.Model):
    code = models.CharField(max_length=50, unique=True)  # e.g. SUPER_ADMIN, DOCTOR, PATIENT (12 codes, §3)
    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    is_system = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "roles"

    def __str__(self):
        return self.code


class Permission(models.Model):
    code = models.CharField(max_length=120, unique=True)  # module.resource.action
    module = models.CharField(max_length=60)
    resource = models.CharField(max_length=60)
    action = models.CharField(max_length=40)

    class Meta:
        db_table = "permissions"
        constraints = [
            models.UniqueConstraint(fields=["module", "resource", "action"], name="permissions_mod_res_act_uk"),
        ]

    def __str__(self):
        return self.code


class RolePermission(models.Model):
    role = models.ForeignKey(Role, on_delete=models.CASCADE, related_name="role_permissions")
    permission = models.ForeignKey(Permission, on_delete=models.CASCADE, related_name="role_permissions")

    class Meta:
        db_table = "role_permissions"
        constraints = [
            models.UniqueConstraint(fields=["role", "permission"], name="role_permissions_role_perm_uk"),
        ]

    def __str__(self):
        return f"{self.role.code}:{self.permission.code}"


class UserRole(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="user_roles")
    role = models.ForeignKey(Role, on_delete=models.CASCADE, related_name="user_roles")
    is_active = models.BooleanField(default=True)
    granted_by = models.ForeignKey(User, null=True, on_delete=models.PROTECT, related_name="granted_user_roles")
    granted_at = models.DateTimeField(auto_now_add=True)
    revoked_at = models.DateTimeField(null=True, blank=True)  # soft revoke; audit keeps history

    class Meta:
        db_table = "user_roles"
        constraints = [
            models.UniqueConstraint(fields=["user", "role"], name="user_roles_user_role_uk"),
        ]

    def __str__(self):
        return f"{self.user.email}:{self.role.code}"


class UserPermissionOverride(models.Model):
    """Per-user permission grant/deny override (audited, rare; §5 §21)."""

    EFFECT = (
        ("ALLOW", "ALLOW"),
        ("DENY", "DENY"),
    )
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="permission_overrides")
    permission = models.ForeignKey(Permission, on_delete=models.CASCADE, related_name="user_overrides")
    effect = models.CharField(max_length=8, choices=EFFECT)
    granted_by = models.ForeignKey(User, null=True, on_delete=models.PROTECT, related_name="granted_overrides")
    reason = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "user_permissions"
        constraints = [
            models.UniqueConstraint(fields=["user", "permission"], name="user_permissions_user_perm_uk"),
        ]

    def __str__(self):
        return f"{self.user.email}:{self.permission.code}={self.effect}"


class VerificationDocument(models.Model):
    DOC_TYPE = (
        ("LICENSE", "LICENSE"),
        ("NATIONAL_ID", "NATIONAL_ID"),
        ("CERTIFICATE", "CERTIFICATE"),
        ("FACILITY_REGISTRATION", "FACILITY_REGISTRATION"),
        ("OTHER", "OTHER"),
    )
    STATUS = (
        ("PENDING", "PENDING"),
        ("VERIFIED", "VERIFIED"),
        ("REJECTED", "REJECTED"),
    )
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="verification_documents")
    doc_type = models.CharField(max_length=40, choices=DOC_TYPE)
    file_url = models.CharField(max_length=500)  # secure-storage key, never a public URL
    status = models.CharField(max_length=16, choices=STATUS, default="PENDING")
    rejection_reason = models.TextField(blank=True)
    reviewed_by = models.ForeignKey(User, null=True, on_delete=models.PROTECT, related_name="reviewed_docs")
    reviewed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "verification_documents"

    def __str__(self):
        return f"{self.user.email}:{self.doc_type}"


class TokenDenyList(models.Model):
    """JWT jti denylist (black-list on logout/refresh rotation); token invalidated. Only PK `jti`."""

    jti = models.CharField(max_length=64, primary_key=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="denied_tokens")
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "token_denylist"

    def __str__(self):
        return self.jti


class SecurityEvent(models.Model):
    """Auth/security event log for audit (SD-8; FR § emergency/security). Not for medical payload."""

    KIND = (
        ("LOGIN_SUCCESS", "LOGIN_SUCCESS"),
        ("LOGIN_FAILED", "LOGIN_FAILED"),
        ("MFA_CHALLENGE", "MFA_CHALLENGE"),
        ("MFA_FAILED", "MFA_FAILED"),
        ("REGISTER", "REGISTER"),
        ("LOGOUT", "LOGOUT"),
        ("PASSWORD_CHANGE", "PASSWORD_CHANGE"),
        ("PASSWORD_RESET", "PASSWORD_RESET"),
        ("EMAIL_VERIFY_ISSUED", "EMAIL_VERIFY_ISSUED"),
        ("EMAIL_VERIFIED", "EMAIL_VERIFIED"),
        ("LOGIN_PIN_SET", "LOGIN_PIN_SET"),
        ("ROLE_CHANGE", "ROLE_CHANGE"),
        ("TOKEN_REFRESH", "TOKEN_REFRESH"),
        ("ADMIN_ACTION", "ADMIN_ACTION"),
        ("PROFILE_CREATED", "PROFILE_CREATED"),
        ("PROFILE_UPDATED", "PROFILE_UPDATED"),
        ("PROFILE_VIEWED", "PROFILE_VIEWED"),
        ("MEDICATION_CREATED", "MEDICATION_CREATED"),
        ("MEDICATION_UPDATED", "MEDICATION_UPDATED"),
        ("MEDICATION_DEACTIVATED", "MEDICATION_DEACTIVATED"),
        ("DOSE_LOGGED", "DOSE_LOGGED"),
        ("SYMPTOM_RECORDED", "SYMPTOM_RECORDED"),
        ("BLOOD_DONOR_CREATED", "BLOOD_DONOR_CREATED"),
        ("BLOOD_DONOR_UPDATED", "BLOOD_DONOR_UPDATED"),
        ("BLOOD_REQUEST_CREATED", "BLOOD_REQUEST_CREATED"),
        ("BLOOD_REQUEST_VERIFIED", "BLOOD_REQUEST_VERIFIED"),
        ("BLOOD_REQUEST_REJECTED", "BLOOD_REQUEST_REJECTED"),
        ("BLOOD_REQUEST_CANCELLED", "BLOOD_REQUEST_CANCELLED"),
        ("BLOOD_MATCH_RUN", "BLOOD_MATCH_RUN"),
        ("BLOOD_MATCH_RESPONDED", "BLOOD_MATCH_RESPONDED"),
        ("DONATION_RECORDED", "DONATION_RECORDED"),
        ("EMERGENCY_CREATED", "EMERGENCY_CREATED"),
        ("EMERGENCY_VALIDATED", "EMERGENCY_VALIDATED"),
        ("EMERGENCY_VIEWED", "EMERGENCY_VIEWED"),
        ("EMERGENCY_RESPONDED", "EMERGENCY_RESPONDED"),
        ("EMERGENCY_ESCALATED", "EMERGENCY_ESCALATED"),
        ("EMERGENCY_RESOLVED", "EMERGENCY_RESOLVED"),
        ("EMERGENCY_CANCELLED", "EMERGENCY_CANCELLED"),
        ("EMERGENCY_ACCESS_GRANTED", "EMERGENCY_ACCESS_GRANTED"),
        ("EMERGENCY_ACCESS_REVOKED", "EMERGENCY_ACCESS_REVOKED"),
        ("DOCTOR_VERIFICATION_SUBMITTED", "DOCTOR_VERIFICATION_SUBMITTED"),
        ("DOCTOR_VERIFIED", "DOCTOR_VERIFIED"),
        ("DOCTOR_REJECTED", "DOCTOR_REJECTED"),
        ("DOCTOR_SUSPENDED", "DOCTOR_SUSPENDED"),
        ("CONSENT_GRANTED", "CONSENT_GRANTED"),
        ("CONSENT_RENEWED", "CONSENT_RENEWED"),
        ("CONSENT_REVOKED", "CONSENT_REVOKED"),
        ("CAREGIVER_INVITED", "CAREGIVER_INVITED"),
        ("CAREGIVER_ACCEPTED", "CAREGIVER_ACCEPTED"),
        ("CAREGIVER_DECLINED", "CAREGIVER_DECLINED"),
        ("CAREGIVER_REVOKED", "CAREGIVER_REVOKED"),
    )
    KINDS = [k for k, _ in KIND]

    user = models.ForeignKey(User, null=True, on_delete=models.SET_NULL, related_name="security_events")
    event_type = models.CharField(max_length=40, choices=KIND)
    status = models.CharField(max_length=20, default="SUCCESS")
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    detail = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "security_events"
        indexes = [
            models.Index(fields=["user", "-created_at"], name="security_events_user_idx"),
        ]

    def __str__(self):
        return f"{self.event_type}:{self.user}"

class OneTimeToken(models.Model):
    """Single-use, expiring, hashed one-time token (email/phone verify,
    password reset). Raw value never stored — only a SHA-256 hash (SD-16/§30).
    Consumption is atomic via used_at guard; expiry enforced at query time."""

    PURPOSE = (
        ("EMAIL_VERIFY", "EMAIL_VERIFY"),
        ("PHONE_VERIFY", "PHONE_VERIFY"),
        ("PASSWORD_RESET", "PASSWORD_RESET"),
    )
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="one_time_tokens")
    purpose = models.CharField(max_length=30, choices=PURPOSE, db_index=True)
    token_hash = models.CharField(max_length=64, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(db_index=True)
    used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "one_time_tokens"
        indexes = [
            models.Index(fields=["token_hash", "purpose"], name="ott_hash_purpose_idx"),
            models.Index(fields=["user", "purpose", "-created_at"], name="ott_user_purpose_idx"),
        ]

    @property
    def is_valid(self):
        return self.used_at is None and self.expires_at > timezone.now()

    def __str__(self):
        return f"{self.user}:{self.purpose}"
