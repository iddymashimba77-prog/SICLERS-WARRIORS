"""Development settings."""

from .base import *  # noqa: F401,F403

DEBUG = True

ALLOWED_HOSTS = ["*"]

SECRET_KEY = os.environ.get(  # noqa: F405
    "DJANGO_SECRET_KEY",
    "django-insecure-dev-only-key-not-for-production",
)

# Allow all origins in development (relaxed CORS)
CORS_ALLOW_ALL_ORIGINS = True  # noqa: F405

# More permissive throttling in dev
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {  # noqa: F405
    "anon": "1000/minute",
    "user": "2000/minute",
    "auth": "120/minute",
}

# Console email in dev
EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"  # noqa: F405

LOGGING["loggers"][""]["level"] = "DEBUG"  # noqa: F405
