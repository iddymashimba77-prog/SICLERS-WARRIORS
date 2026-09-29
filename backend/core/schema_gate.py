"""Gate for the OpenAPI schema / Swagger UI (Stage 4.17 §33).

The API surface is highly-sensitive PHI; its discovery documents (schema JSON
and the Swagger UI) must not be public in a deployed environment. Access rule:

  * DEBUG environments (development): open, so local tooling still works.
  * Anywhere else: authenticated SUPER_ADMIN/ADMIN only (admin.audit.read).

Rejects are silent (404) so non-privileged visitors cannot even confirm the
endpoint exists.
"""

from django.conf import settings
from rest_framework.exceptions import NotFound
from rest_framework.permissions import BasePermission


class SchemaAccess(BasePermission):
    message = "Not found."

    def has_permission(self, request, view) -> bool:
        if settings.DEBUG:
            return True
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            raise NotFound("Not found.")
        if not user.has_perm_code("admin.audit.read"):
            raise NotFound("Not found.")
        return True