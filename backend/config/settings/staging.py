"""Staging settings — fail-closed secret/signing verification (§ 4.17 §27/§30).

Staging may legitimately use the sandbox payment adapter, but it must never
boot with the dev placeholder secret key or webhook signing secret.
"""

from django.core.exceptions import ImproperlyConfigured

from .base import *  # noqa: F401,F403

DEBUG = False

ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")  # noqa: F405

CORS_ALLOWED_ORIGINS = os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")  # noqa: F405

# ---------------------------------------------------------------------------
# Fail-closed secret/payment signing verification (Stage 4.17)
# ---------------------------------------------------------------------------

_PLACEHOLDER_SECRET = "change-me-in-production"
_PLACEHOLDER_PAYMENT_SECRET = "dev-webhook-secret-not-for-production"

_staging_secret_key = os.environ.get("DJANGO_SECRET_KEY", "")
if not _staging_secret_key or _staging_secret_key == _PLACEHOLDER_SECRET:
    raise ImproperlyConfigured(
        "Staging requires DJANGO_SECRET_KEY (a real, unique secret). "
        "The base placeholder is refused."
    )
SECRET_KEY = _staging_secret_key

# The payment environment must be explicit in staging too; the base fallback
# (sandbox) is only ever a local-dev convenience.
if not os.environ.get("PAYMENT_ENV", ""):
    raise ImproperlyConfigured(
        "Staging requires PAYMENT_ENV to be set explicitly (sandbox or production)."
    )

_payment_secret = os.environ.get("PAYMENT_SECRET_KEY", "")
_provider_secrets = [
    os.environ.get(f"PAYMENT_PROVIDER_SECRET_{provider}", "")
    for provider in ("M_PESA", "AIRTEL", "TIGO", "CLICKPESA", "SELCOM")
]
if (
    not _payment_secret or _payment_secret == _PLACEHOLDER_PAYMENT_SECRET
) and not any(_provider_secrets):
    raise ImproperlyConfigured(
        "Staging requires payment signing secrets via PAYMENT_SECRET_KEY or "
        "PAYMENT_PROVIDER_SECRET_* (the dev placeholder is refused)."
    )

# Auth brute-force budget is tighter than local development.
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {  # noqa: F405
    "anon": "100/minute",
    "user": "200/minute",
    "auth": "30/minute",
}

# ---------------------------------------------------------------------------
# Render deployment: static files, proxy headers, CSRF
# ---------------------------------------------------------------------------
MIDDLEWARE = list(MIDDLEWARE)  # noqa: F405
if "whitenoise.middleware.WhiteNoiseMiddleware" not in MIDDLEWARE:
    MIDDLEWARE.insert(1, "whitenoise.middleware.WhiteNoiseMiddleware")

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
CSRF_TRUSTED_ORIGINS = [
    o for o in os.environ.get("CSRF_TRUSTED_ORIGINS", "").split(",") if o  # noqa: F405
]
