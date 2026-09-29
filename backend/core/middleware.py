"""Middleware for Sickler's Warriors API foundation."""

import re
import time
import uuid
import logging

from django.conf import settings
from django.db import connection

request_logger = logging.getLogger("sicklers.api")
performance_logger = logging.getLogger("sicklers.performance")

_CORRELATION_RE = re.compile(r"^[A-Za-z0-9._-]{8,64}$")


class CorrelationIdMiddleware:
    """Attach a unique correlation ID to every request for tracing.

    Stage 4.17 (§26): a caller-supplied header is never echoed verbatim — only
    a strict, bounded format is honored, otherwise the server generates one.
    This prevents log-injection and cross-request correlation spoofing.
    """

    HEADER = "X-Correlation-ID"

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        header = request.headers.get(self.HEADER)
        correlation_id = header if header and _CORRELATION_RE.fullmatch(header) else uuid.uuid4().hex[:16]
        request.correlation_id = correlation_id
        response = self.get_response(request)
        response[self.HEADER] = correlation_id
        return response


class PerformanceLogMiddleware:
    """Per-request duration + query-count logging (Stage 4.18, opt-in).

    Enabled by ``PERF_LOG_ENABLED=1``; off by default so production noise stays
    zero until a deployer asks. The query count relies on ``connection.queries``
    (DEBUG captures), so when DEBUG is off only the wall-clock duration is
    logged. Attaches ``X-Query-Count`` / ``X-Duration-Ms`` response headers so
    a load-test harness can assert on them without parsing logs.

    This middleware never blocks or alters a response; measurement is best
    effort and must never leak request bodies (only path + status + timing).
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        enabled = getattr(settings, "PERF_LOG_ENABLED", False)
        start = time.perf_counter()
        queries_before = (
            len(connection.queries) if connection.queries or enabled else 0
        )
        try:
            response = self.get_response(request)
        finally:
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            try:
                query_count = len(connection.queries) - queries_before
            except Exception:
                query_count = 0
            try:
                response["X-Duration-Ms"] = f"{elapsed_ms:.1f}"
                response["X-Query-Count"] = str(query_count)
            except Exception:
                pass
            if enabled:
                performance_logger.info(
                    "perf method=%s path=%s status=%s duration_ms=%.1f queries=%s",
                    getattr(request, "method", "?"),
                    getattr(request, "path", "?"),
                    getattr(response, "status_code", "?"),
                    elapsed_ms,
                    query_count,
                )
        return response
