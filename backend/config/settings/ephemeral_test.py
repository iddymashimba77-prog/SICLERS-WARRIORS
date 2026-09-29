"""Ephemeral, in-memory test settings — for the 4.3 automated suite ONLY.

Guarantees (enforced by layout, not intent):
* `DATABASES` = SQLite `:memory:` — this module can NEVER reach Postgres.
  `sw_db`, `sw_db_test`, `sw_db_staging` are untouched by construction.
* No destructive Postgres op is ever issued from this path (§ 31).
* Non-persistent: the entire DB lives for the lifetime of one test run and is
  discarded on exit (§ 10/§ 34 ephemeral).
"""

import os

from .base import *  # noqa: F401,F403  (approved base settings § 24/§ 34)
from .base import INSTALLED_APPS, MIDDLEWARE  # noqa: F401  (explicit re-export)

SECRET_KEY = "ephemeral-test-key-not-for-production"  # noqa: S105 (test-only)

DEBUG = False

ALLOWED_HOSTS = ["testserver"]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
        "TEST": {"NAME": ":memory:"},
    }
}

# LocMem so rate-limit + throttling tests never need redis nor Postgres.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
    }
}

# Fast, non-competition hashing for the ephemeral suite (NEVER production;
# § base PASSWORD_HASHERS already prefer Argon2/PBKDF2 for real runs).
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]

# Stage 4.17: the auth (login/register/reset/refresh) throttle scope is
# intentionally unbounded in the ephemeral suite so thousands of per-account
# logins across the run never trip the real-world brute-force budget.
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]["auth"] = "1000000/minute"  # noqa: F405

EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.InMemoryStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}
