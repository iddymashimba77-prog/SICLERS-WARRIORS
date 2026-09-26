"""
Custom DRF exception handler for the Sickler's Warriors API.

Standardises all error responses into:

    {"error": {"code": "...", "message": "...", "details": {}, "correlation_id": "..."}}
"""

import logging

from rest_framework.views import exception_handler
from rest_framework import status as http_status

security_logger = logging.getLogger("sicklers.security")

# Map (status_code, exception_class) → stable machine-readable error code
_ERROR_CODE_MAP = {
    (http_status.HTTP_400_BAD_REQUEST, None): "VALIDATION_ERROR",
    (http_status.HTTP_401_UNAUTHORIZED, None): "UNAUTHORIZED",
    (http_status.HTTP_403_FORBIDDEN, None): "FORBIDDEN",
    (http_status.HTTP_404_NOT_FOUND, None): "NOT_FOUND",
    (http_status.HTTP_409_CONFLICT, None): "CONFLICT",
    (http_status.HTTP_429_TOO_MANY_REQUESTS, None): "RATE_LIMITED",
    (http_status.HTTP_500_INTERNAL_SERVER_ERROR, None): "INTERNAL_ERROR",
}


def _get_error_code(exc, status_code):
    """Resolve a stable machine-readable error code."""
    cls = type(exc)
    return (
        _ERROR_CODE_MAP.get((status_code, cls))
        or _ERROR_CODE_MAP.get((status_code, None))
        or "API_ERROR"
    )


def _safe_detail(exc):
    """Return a safe, user-facing error detail dict (never expose internals)."""
    if hasattr(exc, "detail"):
        detail = exc.detail
        if isinstance(detail, dict):
            return detail
        if isinstance(detail, list):
            return {"non_field_errors": [str(d) for d in detail]}
        return {"detail": str(detail)}
    return {}


def custom_exception_handler(exc, context):
    """Wrap DRF's default handler with the standard error envelope."""
    response = exception_handler(exc, context)

    if response is None:
        status_code = http_status.HTTP_500_INTERNAL_SERVER_ERROR
    else:
        status_code = response.status_code

    if response is None:
        # Unhandled exception — log full detail, return safe 500
        security_logger.exception(
            "Unhandled exception: %s",
            exc,
            extra={"status_code": status_code},
        )
        response = {
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "An unexpected error occurred. Please try again later.",
                "details": {},
                "correlation_id": getattr(context.get("request"), "correlation_id", ""),
            }
        }
        from rest_framework.response import Response

        return Response(response, status=http_status.HTTP_500_INTERNAL_SERVER_ERROR)

    error_code = _get_error_code(exc, status_code)

    # Log security-relevant errors
    if status_code in (http_status.HTTP_401_UNAUTHORIZED, http_status.HTTP_403_FORBIDDEN):
        security_logger.warning(
            "Auth error: code=%s status=%d",
            error_code,
            status_code,
            extra={"correlation_id": getattr(context.get("request"), "correlation_id", "")},
        )

    envelope = {
        "error": {
            "code": error_code,
            "message": str(exc) if not hasattr(exc, "detail") else _safe_detail(exc).get("detail", str(exc)),
            "details": {k: v for k, v in _safe_detail(exc).items() if k != "detail"},
            "correlation_id": getattr(context.get("request"), "correlation_id", ""),
        }
    }
    response.data = envelope
    return response
