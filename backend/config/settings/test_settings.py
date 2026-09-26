"""Test settings."""

from .base import *  # noqa: F401,F403

DEBUG = False

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "test-only-key")  # noqa: F405

DATABASES["default"]["NAME"] = os.environ.get("DB_TEST_NAME", "test_sickle_cell")  # noqa: F405

PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]

EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"  # noqa: F405
