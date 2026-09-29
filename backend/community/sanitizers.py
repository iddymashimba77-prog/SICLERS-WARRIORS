"""Allow-list HTML sanitizer for community/chat text (§ security-design §279).

Community and chat bodies may carry lightweight formatting. There is no HTML
templating library in the approved dependency set, so this is a small,
self-contained allow-list built on the standard-library parser: unknown tags
are dropped (their text is kept), attributes are stripped except a safe `href`
on anchors, and any residual markup characters in text/attribute values are
escaped.

Approved allow-list is intentionally minimal; it does not permit scripts,
styles, event handlers, iframes, images or external embeddings.
"""

from html import escape
from html.parser import HTMLParser

ALLOWED_TAGS = {
    "p", "br", "b", "strong", "i", "em", "u", "s",
    "ul", "ol", "li", "blockquote", "code", "pre", "a",
}
VOID_TAGS = {"br"}
ALLOWED_HREF_SCHEMES = ("http://", "https://", "mailto:")


class _AllowListSanitizer(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag not in ALLOWED_TAGS:
            return
        safe_attrs = ""
        if tag == "a":
            href = next((value for key, value in attrs if key.lower() == "href"), None)
            if href and href.strip().lower().startswith(ALLOWED_HREF_SCHEMES):
                safe_attrs = f' href="{escape(href.strip(), quote=True)}" rel="noopener noreferrer"'
        self._parts.append(f"<{tag}{safe_attrs}>")

    def handle_startendtag(self, tag, attrs):
        if tag in VOID_TAGS:
            self._parts.append(f"<{tag}>")

    def handle_endtag(self, tag):
        if tag in ALLOWED_TAGS and tag not in VOID_TAGS:
            self._parts.append(f"</{tag}>")

    def handle_data(self, data):
        self._parts.append(escape(data))

    def result(self) -> str:
        return "".join(self._parts)


def sanitize_html(value: str, *, max_length: int | None = None) -> str:
    """Return an allow-listed rendering of ``value`` (plain text is preserved)."""
    if not value:
        return ""
    parser = _AllowListSanitizer()
    parser.feed(str(value))
    parser.close()
    cleaned = parser.result().strip()
    if max_length is not None:
        cleaned = cleaned[:max_length]
    return cleaned
