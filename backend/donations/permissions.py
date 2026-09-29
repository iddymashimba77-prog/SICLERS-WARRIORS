"""Donations / payments authorization (approved Stage 4.12).

Mapping (role-permission-matrix §3.10/§3.11):

    campaigns.create   SUP/ADM (A), PATIENT/ORGANIZATION (C11)  -> create DRAFT
    campaigns.view     all roles (A)                             -> public verified stream
    campaigns.verify   SUP/ADM/VO (A)                            -> admin review surface
    donations.create   all roles (A)                             -> POST /donations
    donations.view     SUP/ADM/FIN/ORG (A)                       -> oversight; donor own always
    donations.refund   SUP/ADM (A)                               -> admin refund
    payments.view      SUP/ADM/FIN/ORG (A)                       -> oversight; donor own always
    payments.refund    SUP/ADM (A)                               -> not granted to a route yet
    payments.verify    service-internal (no role)                -> webhook signature auth

Enforcement notes:
* Ownership (donor / campaign owner) is object-level and always allowed on the
  own resource even when the role matrix cell is D (matrix "donor" rows).
* The webhook watcher runs unauthenticated and is authorised ONLY by HMAC
  signature + timestamp TTL + optional IP allowlist (security-design §21/§22).

The webhook path is intentionally routed without JWT: DRF permission classes
never grant it, a human cannot acquire ``payments.verify`` from any role.
"""

from django.conf import settings
from rest_framework import permissions
from rest_framework.exceptions import APIException, NotFound, ValidationError

from accounts.permissions import IsAuthenticatedRespectStatus
from accounts.permissions import require  # noqa: F401  (re-exported for views)

from .providers import (
    ProviderConfigurationError,
    ProviderSignatureError,
    ProviderValidationError,
    get_provider,
)

__all__ = [
    "require",
    "IsAuthenticatedRespectStatus",
    "CampaignOwnerAccess",
    "PublicCampaignAccess",
    "AdminCampaignAccess",
    "DonationDetailAccess",
    "DonationReceiptAccess",
    "DonationRefundAccess",
    "PaymentDetailAccess",
    "PaymentRetryAccess",
    "PaymentWebhookAccess",
]


class CampaignOwnerAccess(permissions.BasePermission):
    """Object-level campaign ownership (PATCH/submit, owner C11)."""

    message = "Only the campaign owner can perform this action."

    def has_object_permission(self, request, view, obj) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        return obj.owner_id == user.pk


class PublicCampaignAccess(permissions.BasePermission):
    """Public stream shows ACTIVE/CLOSED campaigns only (BR-007).

    On object retrieval the owner is granted access regardless of status so a
    draft/pending campaign remains visible to its creator.
    """

    message = "Not found."
    PUBLIC_STATUSES = {"ACTIVE", "CLOSED"}

    def has_permission(self, request, view) -> bool:
        return True

    def has_object_permission(self, request, view, obj) -> bool:
        if obj.status in self.PUBLIC_STATUSES:
            return True
        user = getattr(request, "user", None)
        return bool(
            user and user.is_authenticated
            and user.pk == obj.owner_id
            and IsAuthenticatedRespectStatus().has_permission(request, view)
        )


class AdminCampaignAccess(permissions.BasePermission):
    message = "You do not have permission to review campaigns."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("campaigns.verify"):
            return False
        from accounts.mfa import MfaPolicy

        return MfaPolicy().is_compliant(request, user)


class DonationDetailAccess(permissions.BasePermission):
    """Donation detail: the donor always; otherwise ``donations.view`` roles."""

    message = "You do not have permission to view this donation."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        return IsAuthenticatedRespectStatus().has_permission(request, view)

    def has_object_permission(self, request, view, obj) -> bool:
        user = request.user
        if user.pk == obj.donor_id:
            return True
        return user.has_perm_code("donations.view")


class DonationReceiptAccess(permissions.BasePermission):
    """Receipts are donor-only (FR-CAM-006, DON-008)."""

    message = "Not found."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        return IsAuthenticatedRespectStatus().has_permission(request, view)

    def has_object_permission(self, request, view, obj) -> bool:
        return request.user.pk == obj.donor_id


class DonationRefundAccess(permissions.BasePermission):
    message = "You do not have permission to refund donations."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("donations.refund"):
            return False
        # Money movement is a privileged mutation: require step-up compliance,
        # consistent with AdminCampaignAccess (Stage 4.17 §28).
        from accounts.mfa import MfaPolicy

        return MfaPolicy().is_compliant(request, user)


class PaymentDetailAccess(permissions.BasePermission):
    """Payment status lookup: the donor always; otherwise ``payments.view``."""

    message = "You do not have permission to view this payment."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        return IsAuthenticatedRespectStatus().has_permission(request, view)

    def has_object_permission(self, request, view, obj) -> bool:
        user = request.user
        if obj.donation.donor_id == user.pk:
            return True
        return user.has_perm_code("payments.view")


class PaymentRetryAccess(permissions.BasePermission):
    """Retry is donor-only (own PENDING/FAILED donation)."""

    message = "Not found."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        return IsAuthenticatedRespectStatus().has_permission(request, view)

    def has_object_permission(self, request, view, obj) -> bool:
        return request.user.pk == obj.donation.donor_id


class WebhookSignatureError(APIException):
    """401 that survives DRF's unauthenticated coercion (no auth header).

    DRF turns AuthenticationFailed/NotAuthenticated into 403 when the view has
    no WWW-Authenticate header — wrong for a hmac-authenticated provider
    callback, which must surface 401 per security-design §31.
    """

    status_code = 401
    default_detail = "Webhook signature verification failed."
    default_code = "webhook_signature_error"


class PaymentWebhookAccess(permissions.BasePermission):
    """HMAC + TTL + optional IP allowlist gate for provider callbacks.

    Runs unauthenticated; a successful verification stores the parsed payload
    on ``request.validated_payload`` for the view. Signature failures map to
    401, schema failures to 400, unknown providers to 404 — every rejection is
    audited as FAILED (security-design §31).
    """

    message = "Webhook signature verification failed."

    def _ip_allowed(self, request) -> bool:
        allowlist = getattr(settings, "PAYMENT_ALLOWED_IPS", None) or []
        if not allowlist:
            return True
        addr = (request.META.get("REMOTE_ADDR") or "").strip()
        return addr in allowlist

    def has_permission(self, request, view) -> bool:
        from audit.services import record_audit

        provider_name = view.kwargs.get("provider") or ""
        error = None

        if not self._ip_allowed(request):
            error = "webhook origin address not allowed"
        else:
            try:
                adapter = get_provider(provider_name)
            except ProviderConfigurationError as exc:
                raise NotFound("Unknown payment provider.")
            try:
                payload = adapter.verify_webhook(
                    request.body,
                    request.META.get("HTTP_X_PAYMENT_TIMESTAMP", "") or "",
                    request.META.get("HTTP_X_PAYMENT_SIGNATURE", "") or "",
                )
            except ProviderSignatureError as exc:
                error = str(exc)
            except ProviderValidationError as exc:
                record_audit(
                    actor=None, action_code="payments.webhook_rejected",
                    resource_type="payment", resource_id=None,
                    result="FAILURE", request=request, details={"error": str(exc)},
                )
                raise ValidationError({"webhook": str(exc)})
            except ProviderConfigurationError:
                raise NotFound("Payment provider unavailable.")
            else:
                setattr(request, "validated_payload", payload)
                return True

        record_audit(
            actor=None, action_code="payments.webhook_rejected",
            resource_type="payment", resource_id=None,
            result="FAILURE", request=request, details={"error": error},
        )
        raise WebhookSignatureError("Webhook signature verification failed.")