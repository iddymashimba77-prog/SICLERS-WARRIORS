"""
Standardized JSON renderer for the Sickler's Warriors API.

Wraps all success responses in:

    {"data": <payload>, "meta": {"correlation_id": "..."}}

Error responses are already in the correct envelope shape
(see core.handlers) and are passed through unchanged.
"""

from rest_framework.renderers import JSONRenderer


class ApiEnvelopeRenderer(JSONRenderer):
    def render(self, data, accepted_media_type=None, renderer_context=None):
        response = renderer_context.get("response") if renderer_context else None
        status = getattr(response, "status_code", 200)

        # Pass error envelopes (4xx/5xx) through unchanged.
        # The exception handler already formats them correctly.
        if status >= 400 and isinstance(data, dict) and "error" in data:
            return super().render(data, accepted_media_type, renderer_context)

        correlation_id = ""
        request = renderer_context.get("request") if renderer_context else None
        if request and hasattr(request, "correlation_id"):
            correlation_id = request.correlation_id

        envelope = {
            "data": data,
            "meta": {"correlation_id": correlation_id},
        }
        return super().render(envelope, accepted_media_type, renderer_context)
