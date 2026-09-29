"""Payment provider abstraction (approved security-design §21/§22).

Responsibilities:
* ``BasePaymentProvider``   — contract every adapter implements.
* ``SandboxPaymentProvider`` — default local adapter: deterministic
  ``SANDBOX-…`` references and HMAC-SHA256 signed webhooks so the whole
  initiate → confirm/refund flow is testable with zero credentials.
* ``get_provider(name)``     — registry returning the configured adapter.

Security contract (never weakened in live adapters):
* No raw card/PAN data is ever accepted or stored (payload is redacted).
* Provider webhooks must pass HMAC-SHA256 signature verification over
  ``{timestamp}.{raw_body}`` with a ±5 minute timestamp TTL and a per-provider
  secret; unsigned requests are rejected (BR-008).
* Confirmation of a donation happens ONLY via a verified provider webhook —
  an adapter never fakes success.
"""

import hashlib
import hmac
import json
import logging
import time
import uuid

from django.conf import settings

from .models import PaymentProvider

logger = logging.getLogger(__name__)

WEBHOOK_MAX_AGE_SECONDS = 300  # §22: timestamp TTL ±5 min


class PaymentProviderError(Exception):
    """Base error for payment provider operations."""


class ProviderConfigurationError(PaymentProviderError):
    """Provider is not usable in this environment (e.g. live creds absent)."""


class ProviderSignatureError(PaymentProviderError):
    """Webhook failed HMAC/timestamp verification."""


class ProviderValidationError(PaymentProviderError):
    """Webhook payload failed schema/amount/reference validation."""


def _secret(provider: str) -> str:
    """Env secret per provider, falling back to the shared webhook secret.

    Fail-closed (Stage 4.17 §27): in the ``production`` payment environment a
    per-provider secret is REQUIRED — the shared/default webhook secret (which
    ships as a well-known dev placeholder) is never used to verify live
    webhooks. Attempting to verify with no configured secret raises instead of
    silently accepting the dev default.
    """
    env = getattr(settings, "PAYMENT_ENV", "sandbox")
    providers_secret = getattr(settings, "PAYMENT_PROVIDER_SECRETS", None) or {}
    key = providers_secret.get(provider)
    if env == "production":
        if not key:
            raise ProviderConfigurationError(
                f"{provider}: no live webhook secret configured for the production environment"
            )
        if key == "dev-webhook-secret-not-for-production":
            raise ProviderConfigurationError(
                f"{provider}: refusing to use the shared/dev webhook secret in production"
            )
        return key
    if not key:
        key = settings.PAYMENT_SECRET_KEY
    return key


def _redact(payload: dict) -> dict:
    """Return a safe, non-PHI copy of a provider payload for storage."""
    allowed = {"event", "provider_ref", "random", "timestamp", "status", "currency"}
    return {k: v for k, v in payload.items() if k in allowed}


def build_webhook(provider_name: str, payload: dict, timestamp: int | None = None):
    """Sign a payload the way a real provider would (tests / gates only).

    Returns ``(body_bytes, {"X-Payment-Timestamp": …, "X-Payment-Signature": …})``
    ready to POST to the webhook endpoint.
    """
    if "timestamp" not in payload:
        payload = {**payload, "timestamp": timestamp or int(time.time())}
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ts = str(payload["timestamp"]).encode("utf-8")
    sig = hmac.new(_secret(provider_name).encode("utf-8"), ts + b"." + body, hashlib.sha256).hexdigest()
    headers = {
        "X-Payment-Timestamp": str(payload["timestamp"]),
        "X-Payment-Signature": sig,
    }
    return body, headers


class BasePaymentProvider:
    """Interface every live adapter (M-Pesa, Airtel Money, Tigo Pesa,
    ClickPesa, Selcom) implements per provider-approved flows."""

    provider = None

    def initiate(self, *, transaction_ref, amount, currency, attempt):
        """Begin a payment with the provider.

        Returns the provider reference of the in-flight transaction.
        Must NOT report success before a verified webhook confirms it.
        """
        raise NotImplementedError

    def verify_webhook(self, body: bytes, timestamp: str, signature: str) -> dict:
        """Verify signature + TTL and return the parsed, validated payload.

        Raises ProviderSignatureError / ProviderValidationError on failure.
        """
        raise NotImplementedError

    def get_truncated_status(self, provider_ref):
        """Optional reconciliation probe (nightly). Not required in sandbox."""
        raise NotImplementedError


class SandboxPaymentProvider(BasePaymentProvider):
    """Deterministic local adapter — sandbox environment only."""

    provider = PaymentProvider.M_PESA

    def _ensure_sandbox(self):
        env = getattr(settings, "PAYMENT_ENV", "sandbox")
        if env == "production":
            raise ProviderConfigurationError(
                f"{self.provider}: sandbox adapter refused in production env"
            )

    def initiate(self, *, transaction_ref, amount, currency, attempt):
        self._ensure_sandbox()
        return f"SANDBOX-{uuid.uuid4().hex[:16].upper()}"

    def verify_webhook(self, body: bytes, timestamp: str, signature: str) -> dict:
        self._ensure_sandbox()
        try:
            ts = int(timestamp)
        except (TypeError, ValueError):
            raise ProviderSignatureError("webhook timestamp missing or non-numeric")

        if abs(int(time.time()) - ts) > WEBHOOK_MAX_AGE_SECONDS:
            raise ProviderSignatureError("webhook timestamp outside the ±5 minute window")

        expected = hmac.new(
            _secret(self.provider).encode("utf-8"),
            timestamp.encode("utf-8") + b"." + body,
            hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(expected, (signature or "").lower()):
            raise ProviderSignatureError("HMAC signature mismatch")

        try:
            data = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ProviderValidationError("webhook body is not valid JSON")

        needs = {"event", "transaction_ref", "provider_ref", "amount", "currency"}
        missing = needs - set(data)
        if missing:
            raise ProviderValidationError(f"webhook missing fields: {sorted(missing)}")

        if data.get("timestamp") != ts:
            raise ProviderValidationError("webhook timestamp field does not match header")
        if data.get("event") not in {"payment.success", "payment.failed"}:
            raise ProviderValidationError("webhook event not supported")
        return data


class FallbackProvider(BasePaymentProvider):
    """Placeholder for live adapters not yet wired to credentials.

    Live adapters MUST be implemented with provider-approved integration
    (usually a backend token exchange + HTTPS API + callback/webhook). Until
    M-Pesa/Airtel/Tigo/ClickPesa/Selcom SDKs + credentials exist, they fail
    closed so a donation is never left dangling as implicitly confirmed.
    """

    def __init__(self, provider):
        self.provider = provider

    def initiate(self, *, transaction_ref, amount, currency, attempt):
        raise ProviderConfigurationError(
            f"{self.provider}: live integration not configured in this build"
        )

    def get_truncated_status(self, provider_ref):
        raise ProviderConfigurationError(f"{self.provider}: reconciliation not configured")


_REGISTRY = {
    PaymentProvider.M_PESA: lambda: SandboxPaymentProvider(),
    PaymentProvider.AIRTEL: lambda: FallbackProvider(PaymentProvider.AIRTEL),
    PaymentProvider.TIGO: lambda: FallbackProvider(PaymentProvider.TIGO),
    PaymentProvider.CLICKPESA: lambda: FallbackProvider(PaymentProvider.CLICKPESA),
    PaymentProvider.SELCOM: lambda: FallbackProvider(PaymentProvider.SELCOM),
}


def get_provider(provider_name: str) -> BasePaymentProvider:
    if provider_name not in _REGISTRY:
        raise ProviderConfigurationError(f"unknown payment provider: {provider_name}")
    return _REGISTRY[provider_name]()