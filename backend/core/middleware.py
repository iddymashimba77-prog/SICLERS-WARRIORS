"""Middleware for Sickler's Warriors API foundation."""

import uuid
import logging

request_logger = logging.getLogger("sicklers.api")


class CorrelationIdMiddleware:
    """Attach a unique correlation ID to every request for tracing."""

    HEADER = "X-Correlation-ID"

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        correlation_id = request.headers.get(self.HEADER) or uuid.uuid4().hex[:12]
        request.correlation_id = correlation_id
        response = self.get_response(request)
        response[self.HEADER] = correlation_id
        return response
