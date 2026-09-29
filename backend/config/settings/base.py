"""
Base settings shared across all environments.

All environment-specific settings override values defined here.
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent

# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "change-me-in-production")

DEBUG = False  # overridden per environment

ALLOWED_HOSTS: list[str] = []

# ---------------------------------------------------------------------------
# Application definition
# ---------------------------------------------------------------------------

PROJECT_APPS = [
    "accounts",
    "patients",
    "medical_records",
    "medications",
    "appointments",
    "doctors",
    "blood_network",
    "donations",
    "emergencies",
    "facilities",
    "community",
    "content",
    "education",
    "notifications",
    "ai_assistant",
    "analytics",
    "audit",
    "security_hardening",
    "performance",
    "qa",
]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "drf_spectacular",
    "rest_framework_simplejwt.token_blacklist",
    "core",
    *PROJECT_APPS,
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "core.middleware.CorrelationIdMiddleware",
    "core.middleware.PerformanceLogMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("DB_NAME", "sickle_cell"),
        "USER": os.environ.get("DB_USER", "sw_db_user"),
        "PASSWORD": os.environ.get("DB_PASSWORD", "sw_db_dev_password"),
        "HOST": os.environ.get("DB_HOST", "127.0.0.1"),
        "PORT": os.environ.get("DB_PORT", "5432"),
        # Connection reuse (Stage 4.18): persistent connections cut per-request
        # connect cost. Env-controlled; 0 (default) keeps Django's short-lived
        # behavior until a deployer opts in.
        "CONN_MAX_AGE": int(os.environ.get("DB_CONN_MAX_AGE", "0")),
    }
}

# ---------------------------------------------------------------------------
# Cache (Stage 4.18 — NFR-PERF-001)
# ---------------------------------------------------------------------------
# Dependency-free by default: the LocMem backend ships with Django and needs no
# external service, so the empty-default deploy works out of the box and every
# test suite (incl. config.settings.ephemeral_test which defines its own
# LocMem) is unaffected. A deployer may switch to the built-in Django Redis
# cache by setting CACHE_URL (and installing ``redis``); the generated key
# prefix keeps prod caches safely namespaced. LocMem is per-process, so it is
# only a shared cache when a single process serves traffic.
_CACHE_BACKEND = os.environ.get("CACHE_BACKEND", "locmem")
CACHE_TIMEOUT = int(os.environ.get("CACHE_TIMEOUT", "300"))

CACHES = {}
if _CACHE_BACKEND == "redis":
    CACHES["default"] = {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": os.environ.get("CACHE_URL", "redis://127.0.0.1:6379/1"),
        "KEY_PREFIX": os.environ.get("CACHE_KEY_PREFIX", "sw"),
        "TIMEOUT": CACHE_TIMEOUT,
    }
else:
    CACHES["default"] = {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "sickler-warriors",
        "KEY_PREFIX": os.environ.get("CACHE_KEY_PREFIX", "sw"),
        "TIMEOUT": CACHE_TIMEOUT,
    }

# ---------------------------------------------------------------------------
# Request/resource limits (Stage 4.18 — NFR-PERF-002)
# ---------------------------------------------------------------------------
# Bounded request bodies and form fields: oversized payloads are rejected
# before the envelope/view layer can allocate unbounded memory.
DATA_UPLOAD_MAX_MEMORY_SIZE = int(os.environ.get("DATA_UPLOAD_MAX_MEMORY_SIZE", "2621440"))
DATA_UPLOAD_MAX_NUMBER_FIELDS = int(os.environ.get("DATA_UPLOAD_MAX_NUMBER_FIELDS", "1000"))

# ---------------------------------------------------------------------------
# Observability (Stage 4.18)
# ---------------------------------------------------------------------------
# Opt-in per-request duration/query-count logging (PERF_LOG_ENABLED=1). Off by
# default so nothing is logged in production until a deployer asks.
PERF_LOG_ENABLED = os.environ.get("PERF_LOG_ENABLED", "") == "1"

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# ---------------------------------------------------------------------------
# i18n
# ---------------------------------------------------------------------------

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

# ---------------------------------------------------------------------------
# Static / Media
# ---------------------------------------------------------------------------

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ---------------------------------------------------------------------------
# Django REST Framework
# ---------------------------------------------------------------------------

REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": [
        "core.renderers.ApiEnvelopeRenderer",
    ],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.FormParser",
        "rest_framework.parsers.MultiPartParser",
    ],
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_PAGINATION_CLASS": "core.pagination.CorePageNumberPagination",
    "PAGE_SIZE": 20,
    "EXCEPTION_HANDLER": "core.handlers.custom_exception_handler",
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "100/minute",
        "user": "200/minute",
        "auth": "10/minute",
    },
    "EXCEPTION_HANDLER": "core.handlers.custom_exception_handler",
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}

# ---------------------------------------------------------------------------
# SimpleJWT
# ---------------------------------------------------------------------------

from datetime import timedelta

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.environ.get("SIMPLE_JWT_ACCESS_TOKEN_LIFETIME", "300"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(seconds=int(os.environ.get("SIMPLE_JWT_REFRESH_TOKEN_LIFETIME", "86400"))),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "AUTH_HEADER_TYPES": ("Bearer",),
    # Session invalidation on password change/reset (Stage 4.17 §32): every
    # issued token embeds an HMAC of the password hash, so changing the
    # password instantly revokes all previously-issued access/refresh tokens
    # without enumeration (identity-bound auth, simplejwt rev-claim).
    "CHECK_REVOKE_TOKEN": True,
    "REVOKE_TOKEN_CLAIM": "rev",
}

# Admin-ready sessions (SUPER_ADMIN/ADMIN) rotate on a *shorter* refresh TTL
# than general users (Stage 4.16 §23 — tighter admin session lifetime). Applies
# at login and every refresh rotation for admin-ready role holders only.
ADMIN_REFRESH_TOKEN_LIFETIME = timedelta(
    hours=int(os.environ.get("ADMIN_REFRESH_TOKEN_LIFETIME_HOURS", "8"))
)

# ---------------------------------------------------------------------------
# drf-spectacular
# ---------------------------------------------------------------------------

SPECTACULAR_SETTINGS = {
    "TITLE": "Sickler's Warriors API",
    "DESCRIPTION": "Healthcare platform for the sickle cell warrior community",
    "VERSION": "1.0.0-dev",
    "SERVE_INCLUDE_SCHEMA": False,
}

# ---------------------------------------------------------------------------
# Payments / donations (Stage 4.12)
# ---------------------------------------------------------------------------
# Sandbox-first: no live provider credentials ship in this build. Adapters
# read per-provider secrets and fail closed when a live provider is requested
# (see donations.providers._secret). Webhook signing uses HMAC-SHA256 over
# {timestamp}.{raw_body} with a ±5 min TTL (security-design §21/§22).
PAYMENT_ENV = os.environ.get("PAYMENT_ENV", "sandbox")
PAYMENT_SECRET_KEY = os.environ.get(  # noqa: S105 — dev shared webhook secret
    "PAYMENT_SECRET_KEY", "dev-webhook-secret-not-for-production",
)
PAYMENT_PROVIDER_SECRETS = {
    provider: os.environ.get(f"PAYMENT_PROVIDER_SECRET_{provider}", "")
    for provider in ("M_PESA", "AIRTEL", "TIGO", "CLICKPESA", "SELCOM")
}
# Remote addresses allowed to POST webhooks; when empty, signature is the guard.
PAYMENT_ALLOWED_IPS = [
    ip.strip() for ip in os.environ.get("PAYMENT_ALLOWED_IPS", "").split(",") if ip.strip()
]

# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------

CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS: list[str] = []

# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "[{asctime}] {levelname} {name} {message}",
            "style": "{",
        },
    },
    "filters": {
        "require_debug_true": {
            "()": "django.utils.log.RequireDebugTrue",
        },
    },
    "handlers": {
        "console": {
            "level": "INFO",
            "class": "logging.StreamHandler",
            "formatter": "verbose",
        },
    },
    "loggers": {
        "": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": True,
        },
        "django.security": {
            "handlers": ["console"],
            "level": "WARNING",
            "propagate": False,
        },
        "sicklers.security": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
        "sicklers.audit": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}

# ---------------------------------------------------------------------------
# Custom user model — MUST precede any feature migration (approved §27 (a)).
# ---------------------------------------------------------------------------
AUTH_USER_MODEL = "accounts.User"

# ---------------------------------------------------------------------------
# AI Assistant (Stage 4.15) — provider abstraction, never secrets here.
#
# `AI_PROVIDER` selects the provider through the factory in ai_assistant.providers.
# Only ``rule_based`` ships in this build (deterministic, no external calls, no
# keys). External LLM providers are the documented extension point and are NOT
# configured — no provider API key exists in any environment variable here.
# ---------------------------------------------------------------------------
AI_PROVIDER = os.environ.get("AI_PROVIDER", "rule_based")
AI_MAX_MESSAGE_CHARS = int(os.environ.get("AI_MAX_MESSAGE_CHARS", "2000"))
AI_CONTEXT_DAYS = int(os.environ.get("AI_CONTEXT_DAYS", "30"))
AI_TRENDS_DEFAULT_WINDOW_DAYS = int(os.environ.get("AI_TRENDS_WINDOW_DAYS", "30"))
AI_TRENDS_MAX_WINDOW_DAYS = int(os.environ.get("AI_TRENDS_MAX_WINDOW_DAYS", "90"))
AI_SYMPTONS_HISTORY_LIMIT = 5
AI_TIMELINE_HISTORY_LIMIT = 10
AI_MEDICATION_EDUCATION_LIMIT = 10
AI_KNOWLEDGE_SEARCH_LIMIT = 3
AI_KNOWLEDGE_SNIPPET_CHARS = 400
AI_DISCLAIMER = (
    "AI-generated health information is for education and support only, and is "
    "not a medical diagnosis, prescription, or substitute for professional care. "
    "For diagnosis, treatment decisions, or urgent symptoms, consult a qualified "
    "healthcare professional."
)
