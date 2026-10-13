"""
Public landing/utility endpoints.
"""
from django.http import HttpResponse
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .views import APP_VERSION


@api_view(["GET"])
@permission_classes([AllowAny])
def root_index(request):
    accept = request.headers.get("Accept", "")
    html = (
        "<!doctype html><html><head><title>Sickler's Warriors</title>"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        "<style>body{font-family:sans-serif;margin:40px}a{color:#0d6efd}</style>"
        "</head><body>"
        f"<h1>Sickler's Warriors</h1><p>API is up (version {APP_VERSION}).</p>"
        "<ul>"
        "<li><a href=\"/admin/login/\">Admin (Django)</a></li>"
        "<li><a href=\"/api/v1/health/\">Health</a></li>"
        "</ul></body></html>"
    )
    if "text/html" in accept and "application/json" not in accept:
        return HttpResponse(html)
    return Response(
        {"status": "ok", "version": APP_VERSION, "links": {"admin": "/admin/login/", "health": "/api/v1/health/"}}
    )
