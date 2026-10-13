"""Media URL construction — no request-Host pinning (Stage 4.x correctness).

Uploaded objects (avatars, news covers, education attachments) are *stored*
as backend-relative paths (``/media/...``) and only ever *served* as absolute
URLs, resolved when a response is built. Two failure modes this module exists
to prevent:

1. **Host pinning.** Building the absolute URL at upload time with
   ``request.build_absolute_uri()`` bakes whatever ``Host`` header happened to
   arrive (an internal LB name, ``localhost``, a staging domain) into the row
   forever — every later client then receives a URL pointing at the wrong
   origin. The origin is a property of the *response*, not of the upload.
2. **Double-slash paths.** ``f"/{settings.MEDIA_URL}{name}"`` produced
   ``//media/...``, which ``build_absolute_uri`` parsed as a scheme-relative
   URL and turned into ``http://media/...`` (host literally ``media``).

Resolution order for the origin: ``PUBLIC_API_BASE`` (operator-pinned, config
is the authority) → the current request's origin → nothing (return the
relative path; every client — Flutter's ``_resolveMedia``, the admin panel —
resolves ``/media/...`` against the API origin).

Rows written before this existed may still hold an absolute URL with a stale
host, or the ``http://media/...`` artifact; :func:`media_url` normalises both
on read so they heal without a data migration.
"""

from __future__ import annotations

from urllib.parse import urlparse

from django.conf import settings
from rest_framework import serializers


def media_prefix() -> str:
    """``MEDIA_URL`` guaranteed to start with a single slash."""
    prefix = settings.MEDIA_URL or "/media/"
    return prefix if prefix.startswith("/") else f"/{prefix}"


def media_path(value) -> str | None:
    """Return the ``/media/...`` path when *value* refers to one of our uploads.

    ``None`` means "not ours" — an externally supplied absolute URL (news and
    education covers accept arbitrary http(s) links) must pass through
    untouched.
    """
    if not value or not isinstance(value, str):
        return None
    prefix = media_prefix()
    parsed = urlparse(value)
    path = parsed.path or value
    if path.startswith(prefix):
        return path
    # Legacy rows written while MEDIA_URL was the relative "media/".
    if path.startswith("media/"):
        return f"/{path}"
    # Rows written by the double-slash bug: `//media/<name>` parsed as a
    # scheme-relative URL, so the host swallowed the first path segment.
    if parsed.netloc and parsed.netloc == prefix.strip("/"):
        return f"{prefix}{path.lstrip('/')}"
    return None


def _origin(request) -> str:
    """Public origin for media links: config first, then the request."""
    configured = (getattr(settings, "PUBLIC_API_BASE", "") or "").rstrip("/")
    if configured:
        return configured
    if request is not None:
        return request.build_absolute_uri("/").rstrip("/")
    return ""


def media_url(value, request=None) -> str | None:
    """Absolute URL for our uploads; unchanged for anything else.

    Read-time resolution: the stored row stays host-free (or is healed if an
    older row pinned one), and the caller's origin is used.
    """
    if not value or not isinstance(value, str):
        return value
    path = media_path(value)
    if path is None:
        return value
    origin = _origin(request)
    return f"{origin}{path}" if origin else path


def store_media_path(name: str) -> str:
    """Storage key → backend-relative path to persist (never absolute)."""
    name = (name or "").lstrip("/")
    prefix = media_prefix()
    if name.startswith(prefix.lstrip("/")):
        return f"/{name}"
    return f"{prefix}{name}"


class MediaUrlField(serializers.CharField):
    """``CharField`` that serves a stored media value through :func:`media_url`.

    Needs the serializer's ``request`` context (every DRF generic view
    provides it); without one the stored relative path is returned as-is,
    which every client resolves against the API origin anyway.
    """

    def to_representation(self, value):
        if value in (None, ""):
            return super().to_representation(value)
        if not isinstance(value, str):
            # An ImageFieldField/FieldFile arrives when the source column is a
            # real Image/FileField (ticker artwork) — reduce it to its stored
            # path so media_url can build the absolute URL.
            value = str(value)
        return media_url(value, self.context.get("request"))
