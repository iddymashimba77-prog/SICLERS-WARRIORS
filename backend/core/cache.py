"""Reference-data caching helpers (Stage 4.18 — NFR-PERF-001).

Two hard rules:

1. **Only NON-personal, non-user-scoped reference data may be cached.** Medical
   records, notifications, dashboards and anything that varies per user must
   NEVER go through these helpers — putting one patient's data into a shared
   cache (or a LocMem/Redis key that another request could read) would be a
   privacy regression from Stage 4.17. "deny by default".

2. **A cache failure never breaks a request.** These helpers catch and log
   cache surprises and always fall back to the direct loader. A misconfigured
   or unavailable Redis must degrade to "uncached" rather than 5xx.

Keys are explicit, namespaced strings (``ref:<domain>:<name>``) and the stored
values are picklable plain Python data (lists/dicts), never ORM model
instances, so partial updates cannot ship a stale, half-loaded row.
"""

import logging

from django.core.cache import cache

logger = logging.getLogger("sicklers.performance")


def reference_get(cache_key: str, default=None):
    """Read a reference-cache key; never raises. Returns ``default`` on miss/error."""
    if not cache_key:
        return default
    try:
        value = cache.get(cache_key)
    except Exception:
        logger.warning("cache.get(%s) failed; serving uncached", cache_key, exc_info=True)
        return default
    return default if value is None else value


def reference_set(cache_key: str, value, ttl: int) -> bool:
    """Store reference data under ``cache_key`` with a bounded TTL; never raises."""
    if not cache_key:
        return False
    try:
        cache.set(cache_key, value, timeout=ttl)
        return True
    except Exception:
        logger.warning("cache.set(%s) failed; reference stays uncached", cache_key, exc_info=True)
        return False


def reference_fetch(cache_key: str, ttl: int, loader, invalidate=False):
    """Get cached reference data, else build it via ``loader()`` and store it.

    ``invalidate=True`` bypasses the read, rebuilds from ``loader()`` and
    overwrites the key (used by write paths that must not serve stale data).
    ``loader`` must return picklable plain data (dict/list/scalars).
    """
    if not invalidate:
        cached = reference_get(cache_key)
        if cached is not None:
            return cached
    value = loader()
    reference_set(cache_key, value, ttl=ttl)
    return value


def invalidate_reference(cache_key: str) -> bool:
    """Drop a reference cache key; never raises. Returns True on success."""
    if not cache_key:
        return False
    try:
        cache.delete(cache_key)
        return True
    except Exception:
        logger.warning("cache.delete(%s) failed", cache_key, exc_info=True)
        return False


# Reference key constants (each app registers its own keys here).
KEY_EDUCATION_CATEGORIES = "ref:education:categories"
KEY_SYMPTOM_TYPES = "ref:medications:symptom_types"
KEY_HEALTH_READY = "ref:health:ready_cache_probe"

# Bounded TTLs (seconds) — short enough to self-heal, long enough to matter.
TTL_REFERENCE_15M = 900
TTL_REFERENCE_5M = 300