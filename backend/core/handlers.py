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
    (http_status.HTTP_502_BAD_GATEWAY, None): "BAD_GATEWAY",
    (http_status.HTTP_503_SERVICE_UNAVAILABLE, None): "SERVICE_UNAVAILABLE",
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


def _primary_message(detail, fallback):
    """Pick one clean, human-readable sentence out of a DRF detail.

    Field validation errors arrive as ``{field: [message, ...]}``. Rendering
    that dict directly (``str(exc)``) leaks a Python repr into the client's UI,
    so callers get the first real message instead — the machine-readable
    per-field list still travels in ``error.details``.
    """
    if not isinstance(detail, dict):
        return fallback
    if "detail" in detail:
        return _flatten_message(detail["detail"]) or fallback
    for value in detail.values():
        message = _flatten_message(value)
        if message:
            return message
    return fallback


def _flatten_message(value):
    if isinstance(value, (list, tuple)):
        return str(value[0]) if value else ""
    if value is None:
        return ""
    return str(value)


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

    safe_detail = _safe_detail(exc)
    envelope = {
        "error": {
            "code": error_code,
            "message": _primary_message(safe_detail, str(exc)),
            "details": {k: v for k, v in safe_detail.items() if k != "detail"},
            "correlation_id": getattr(context.get("request"), "correlation_id", ""),
        }
    }
    response.data = envelope
    return response


# ----------------------------------------------------------- URL-level catch-all
#
# DRF's exception handler covers everything that reaches a view. URLs that
# match *no* route (typos, retired endpoints, the versioned alias of a path
# that does not exist) never reach DRF — Django raises Resolver404 and the
# default handler answers with an HTML error page. Every client of this API is
# a JSON consumer (Flutter, the admin panel), so /api/… misses must answer in
# the same envelope a view would have produced.

def _envelope(request, code: str, message: str) -> dict:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": {},
            "correlation_id": getattr(request, "correlation_id", ""),
        }
    }


def api_not_found(request, exception=None):
    """``handler404`` — JSON envelope for /api/ paths, Django's page otherwise."""
    if request.path.startswith("/api/"):
        from django.http import JsonResponse

        return JsonResponse(
            _envelope(request, "NOT_FOUND", "That endpoint does not exist."),
            status=404,
        )
    from django.views.defaults import page_not_found

    return page_not_found(request, exception)


def api_server_error(request):
    """``handler500`` — JSON envelope for /api/ paths, Django's page otherwise."""
    if request.path.startswith("/api/"):
        from django.http import JsonResponse

        return JsonResponse(
            _envelope(
                request,
                "INTERNAL_ERROR",
                "An unexpected error occurred. Please try again later.",
            ),
            status=500,
        )
    from django.views.defaults import server_error

    return server_error(request)
