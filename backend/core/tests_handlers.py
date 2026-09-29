"""Error-envelope handler tests (core.handlers).

Run::

    venv/bin/python manage.py test core.tests_handlers --settings=config.settings.ephemeral_test

Checks the stable machine-readable codes for every HTTP status the API can
emit — including BAD_GATEWAY (502) which gateways can surface when the
upstream is unreachable.
"""

from django.test import SimpleTestCase
from rest_framework import status as http_status
from rest_framework.exceptions import NotFound, PermissionDenied

from core.handlers import _get_error_code


class ErrorCodeMappingTests(SimpleTestCase):
    """Mixed via Django's discovery; asserts the status → code table."""

    def test_known_status_codes_map_to_stable_codes(self):
        cases = [
            (http_status.HTTP_400_BAD_REQUEST, "VALIDATION_ERROR"),
            (http_status.HTTP_401_UNAUTHORIZED, "UNAUTHORIZED"),
            (http_status.HTTP_403_FORBIDDEN, "FORBIDDEN"),
            (http_status.HTTP_404_NOT_FOUND, "NOT_FOUND"),
            (http_status.HTTP_409_CONFLICT, "CONFLICT"),
            (http_status.HTTP_429_TOO_MANY_REQUESTS, "RATE_LIMITED"),
            (http_status.HTTP_500_INTERNAL_SERVER_ERROR, "INTERNAL_ERROR"),
            (http_status.HTTP_502_BAD_GATEWAY, "BAD_GATEWAY"),
            (http_status.HTTP_503_SERVICE_UNAVAILABLE, "SERVICE_UNAVAILABLE"),
        ]
        for status_code, expected in cases:
            self.assertEqual(
                _get_error_code(Exception(), status_code), expected,
                f"status {status_code} should map to {expected}",
            )

    def test_exception_class_is_ignored_when_status_is_known(self):
        self.assertEqual(
            _get_error_code(NotFound("x"), http_status.HTTP_404_NOT_FOUND),
            "NOT_FOUND",
        )
        self.assertEqual(
            _get_error_code(PermissionDenied("x"), http_status.HTTP_403_FORBIDDEN),
            "FORBIDDEN",
        )

    def test_unmapped_status_falls_back_to_api_error(self):
        self.assertEqual(
            _get_error_code(Exception(), http_status.HTTP_302_FOUND), "API_ERROR"
        )