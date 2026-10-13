"""core.media tests — media URLs without Host pinning.

Run::

    venv/bin/python manage.py test core.tests_media --settings=config.settings.ephemeral_test

Covers the three failure modes documented in ``core.media``: the upload Host
never lands in a stored row, ``//media/...`` never becomes host ``media``, and
externally supplied http(s) covers pass through untouched.
"""

from django.test import SimpleTestCase, TestCase, override_settings
from django.test import RequestFactory

from core.media import media_path, media_url, store_media_path


class MediaPathTests(SimpleTestCase):
    def test_relative_path_passes_through(self):
        self.assertEqual(media_path("/media/accounts/avatars/a.jpg"), "/media/accounts/avatars/a.jpg")

    def test_legacy_media_url_without_leading_slash_is_normalised(self):
        self.assertEqual(media_path("media/accounts/avatars/a.jpg"), "/media/accounts/avatars/a.jpg")

    def test_pinned_absolute_row_is_stripped_to_path(self):
        self.assertEqual(
            media_path("http://old-internal-host:8000/media/content/news/n.jpg"),
            "/media/content/news/n.jpg",
        )

    def test_double_slash_bug_artifact_is_healed(self):
        # `f"/{MEDIA_URL}{name}"` produced `//media/<name>`, which
        # build_absolute_uri parsed as scheme-relative with host `media`.
        self.assertEqual(
            media_path("http://media/content/news/n.jpg"),
            "/media/content/news/n.jpg",
        )

    def test_external_cover_url_is_not_ours(self):
        self.assertIsNone(media_path("https://cdn.example.org/pic.png"))
        self.assertIsNone(media_path(""))

    def test_media_prefix_guarantees_leading_slash(self):
        self.assertTrue(store_media_path("content/news/n.jpg").startswith("/media/"))
        self.assertEqual(store_media_path("/media/x.jpg"), "/media/x.jpg")


class MediaUrlResolutionTests(SimpleTestCase):
    @override_settings(ALLOWED_HOSTS=["api.example.org"])
    def test_uses_request_origin_when_no_config(self):
        request = RequestFactory().get("/api/content/news/", HTTP_HOST="api.example.org")
        self.assertEqual(media_url("/media/a.jpg", request), "http://api.example.org/media/a.jpg")

    @override_settings(ALLOWED_HOSTS=["internal-lb"])
    def test_configured_public_base_wins_over_request_host(self):
        request = RequestFactory().get("/api/content/news/", HTTP_HOST="internal-lb")
        with override_settings(PUBLIC_API_BASE="https://api.example.org"):
            self.assertEqual(
                media_url("/media/a.jpg", request),
                "https://api.example.org/media/a.jpg",
            )

    def test_no_request_returns_relative_path(self):
        self.assertEqual(media_url("/media/a.jpg"), "/media/a.jpg")

    def test_external_url_never_rewritten(self):
        request = RequestFactory().get("/", HTTP_HOST="testserver")
        self.assertEqual(
            media_url("https://cdn.example.org/x.png", request),
            "https://cdn.example.org/x.png",
        )


class JsonNotFoundEnvelopeTests(TestCase):
    """The catch-all handler must answer API consumers in the error envelope."""

    def test_unknown_api_route_returns_error_envelope(self):
        resp = self.client.get("/api/definitely-not-a-route/")
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp["Content-Type"], "application/json")
        payload = resp.json()
        self.assertEqual(payload["error"]["code"], "NOT_FOUND")
        self.assertIn("correlation_id", payload["error"])

    def test_unknown_versioned_api_route_returns_error_envelope(self):
        resp = self.client.get("/api/v1/definitely-not-a-route/")
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["error"]["code"], "NOT_FOUND")

    def test_non_api_route_keeps_the_html_page(self):
        resp = self.client.get("/definitely-not-a-route/")
        self.assertEqual(resp.status_code, 404)
        self.assertIn("text/html", resp["Content-Type"])
