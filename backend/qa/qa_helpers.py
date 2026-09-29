"""Shared helpers for the Stage 4.19 QA-integration suite.

Test-only; never imported by production code. Uses the same established
patterns as the per-app suites (`_orm_user` + JWT clients) so the cross-app
QA suite stays deterministic on ephemeral SQLite.
"""

import uuid as _uuid

from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from facilities.models import Facility
from notifications.models import Notification

_PASSWORD = "Str0ng!Pass9"


class JsonAPIClient(APIClient):
    """APIClient that sends request bodies as application/json by default."""

    def _json(self, kwargs):
        kwargs.setdefault("format", "json")

    def post(self, *args, **kwargs):
        self._json(kwargs)
        return super().post(*args, **kwargs)

    def put(self, *args, **kwargs):
        self._json(kwargs)
        return super().put(*args, **kwargs)

    def patch(self, *args, **kwargs):
        self._json(kwargs)
        return super().patch(*args, **kwargs)

    def delete(self, *args, **kwargs):
        self._json(kwargs)
        return super().delete(*args, **kwargs)


def orm_user(role_code, email=None, account_status="ACTIVE", **extra):
    """Create an active user with an active role (fast, ORM-only)."""
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status=account_status,
        **extra,
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def client(user):
    c = JsonAPIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return c


def register(role="PATIENT", password=_PASSWORD, email=None):
    """End-to-end registration via the real auth endpoint (E2E journeys)."""
    c = APIClient()
    resp = c.post(
        "/api/auth/register/",
        {
            "email": email or f"{role.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
            "password": password,
            "first_name": "Test",
            "last_name": "User",
            "role_code": role,
        },
        format="json",
    )
    return c, resp


def facility(name="St. Joseph Clinic", city="Accra", facility_type="CLINIC", verified=True):
    return Facility.objects.create(
        name=name, facility_type=facility_type, city=city, is_verified=verified,
    )


def last_notification(user, ntype="SYSTEM"):
    return Notification.objects.filter(recipient=user, type=ntype).order_by("-created_at").first()