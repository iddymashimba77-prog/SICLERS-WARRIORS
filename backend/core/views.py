"""
Health check endpoints for Sickler's Warriors.

- GET /api/v1/health/   — liveness (app is running)
- GET /api/v1/health/ready/ — readiness  (app + database reachable)
"""

import logging

from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework import status as http_status
from django.db import connection

logger = logging.getLogger("sicklers.health")

APP_VERSION = "1.0.0-dev"


@extend_schema(responses={200: OpenApiTypes.OBJECT})
@api_view(["GET"])
@permission_classes([AllowAny])
def health_live(request):
    """Basic liveness probe — returns 200 when the application is running."""
    return Response({"status": "ok", "version": APP_VERSION})


@extend_schema(responses={200: OpenApiTypes.OBJECT})
@api_view(["GET"])
@permission_classes([AllowAny])
def health_ready(request):
    """Readiness probe — checks database connectivity.

    Returns 200 when healthy, 503 when degraded.
    """
    checks = {}
    overall = "ok"
    status_code = http_status.HTTP_200_OK

    # Database check
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception as exc:
        logger.warning("Health check — database unavailable: %s", exc)
        checks["database"] = "unavailable"
        overall = "degraded"
        status_code = http_status.HTTP_503_SERVICE_UNAVAILABLE

    # Cache check (Stage 4.18): a read/write round-trip must succeed for the
    # cache backend actually in use (LocMem or Redis). Never raises; a cache
    # failure degrades readiness so orchestrators pull the process while the
    # cache-dependent hot paths still serve from the database.
    try:
        from django.core.cache import cache

        cache.set("healthcheck_probe", 1, timeout=5)
        value = cache.get("healthcheck_probe")
        checks["cache"] = "ok" if value == 1 else "unavailable"
        if value != 1:
            overall = "degraded"
            status_code = http_status.HTTP_503_SERVICE_UNAVAILABLE
    except Exception as exc:
        logger.warning("Health check — cache unavailable: %s", exc)
        checks["cache"] = "unavailable"
        overall = "degraded"
        status_code = http_status.HTTP_503_SERVICE_UNAVAILABLE

    return Response(
        {"status": overall, "version": APP_VERSION, "checks": checks},
        status=status_code,
    )
