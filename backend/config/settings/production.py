"""Production settings — no defaults for secrets; all from environment.

Stage 4.17 hardening: fail-closed at import time. If production is booted
without an operator-supplied secret key, a verified live payment environment
and payment signing secrets, it refuses to start rather than silently using
the sandbox/dev defaults from ``base``. Nothing here can be satisfied by a
commit — every value comes from the deployment environment.
"""

from django.core.exceptions import ImproperlyConfigured

from .base import *  # noqa: F401,F403

DEBUG = False

ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")  # noqa: F405

CORS_ALLOWED_ORIGINS = os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")  # noqa: F405

# SECURITY — enforce in production
SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# ---------------------------------------------------------------------------
# Fail-closed secret/payment verification (Stage 4.17 §27/§30)
# ---------------------------------------------------------------------------

_PLACEHOLDER_SECRET = "change-me-in-production"
_PLACEHOLDER_PAYMENT_SECRET = "dev-webhook-secret-not-for-production"

_prod_secret_key = os.environ.get("DJANGO_SECRET_KEY", "")
if not _prod_secret_key or _prod_secret_key == _PLACEHOLDER_SECRET:
    raise ImproperlyConfigured(
        "Production requires DJANGO_SECRET_KEY (a real, unique secret). "
        "The base placeholder is refused."
    )
SECRET_KEY = _prod_secret_key

# The live payment environment must be explicit: the base default is the
# sandbox adapter and must never run in production (security-design §21).
_payment_env = os.environ.get("PAYMENT_ENV", "")
if _payment_env != "production":
    raise ImproperlyConfigured(
        "Production requires PAYMENT_ENV=production; the sandbox default is "
        "refused in this environment."
    )
PAYMENT_ENV = _payment_env

_payment_secret = os.environ.get("PAYMENT_SECRET_KEY", "")
_provider_secrets = [
    os.environ.get(f"PAYMENT_PROVIDER_SECRET_{provider}", "")
    for provider in ("M_PESA", "AIRTEL", "TIGO", "CLICKPESA", "SELCOM")
]
if (
    not _payment_secret or _payment_secret == _PLACEHOLDER_PAYMENT_SECRET
) and not any(_provider_secrets):
    raise ImproperlyConfigured(
        "Production requires payment signing secrets via PAYMENT_SECRET_KEY "
        "or PAYMENT_PROVIDER_SECRET_* (the dev placeholder is refused)."
    )

# Auth brute-force budget is tighter in production.
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {  # noqa: F405
    "anon": "60/minute",
    "user": "120/minute",
    "auth": "10/minute",
}

# Static
STATICFILES_STORAGE = "django.contrib.staticfiles.storage.ManifestStaticFilesStorage"  # noqa: F405
