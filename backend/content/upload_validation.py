"""News cover image upload validation + normalization (content CMS).

Server-side authority only: MIME content type and byte-size limits, plus a
Pillow decode probe (real magic bytes, not just the extension). Every upload is
re-encoded to a flat, ≤1600px JPEG so no untrusted bytes are ever served back
raw and the field is uniform regardless of source format.

Declared vs actual type
----------------------
The declared ``Content-Type`` of a multipart part is a *hint*, not evidence —
a legitimate mobile client that does not set a part type (Flutter's
``MultipartFile.fromPath`` without ``contentType``) sends
``application/octet-stream`` for perfectly valid JPEG bytes. Rejecting on the
declared type alone is what made profile pictures and cover uploads "refuse to
work" from the app. So:

* a declared type that is a *known non-image* (text/html, application/pdf, …)
  is still rejected outright;
* ``application/octet-stream``/empty is treated as "unknown" and decided by the
  Pillow decode probe, which is the real authority;
* anything Pillow can decode as JPEG/PNG/WebP is accepted and re-encoded.

This is not a loosening: the decoded bytes must still be a real image of an
allowed format, still within the size limit, still re-encoded by us.
"""

import io

from django.core.exceptions import ValidationError
from PIL import Image, UnidentifiedImageError

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
# Clients that send no meaningful part type fall back to octet-stream.
GENERIC_CONTENT_TYPES = {
    "",
    "application/octet-stream",
    "binary/octet-stream",
    "application/binary",
    "application/x-binary",
}
ALLOWED_IMAGE_FORMATS = ("JPEG", "PNG", "WEBP")
MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_DIMENSION = 1600
# Decompression-bomb guard: reject before `load()` allocates the pixel buffer.
MAX_IMAGE_PIXELS = 40_000_000
JPEG_QUALITY = 85

_MESSAGE = (
    "Unsupported image. Upload a JPEG, PNG or WebP file up to 5 MB "
    "(max 1600px on the longest side)."
)


def normalize_cover_image(upload):
    """Validate ``upload`` and return ``(bytes_buffer, 'image/jpeg')``.

    Raises :class:`django.core.exceptions.ValidationError` on any rejection.
    """
    if getattr(upload, "size", 0) > MAX_IMAGE_BYTES:
        raise ValidationError("Cover image exceeds the 5 MB limit.")
    content_type = (getattr(upload, "content_type", "") or "").strip().lower()
    if content_type not in ALLOWED_CONTENT_TYPES and content_type not in GENERIC_CONTENT_TYPES:
        raise ValidationError(_MESSAGE)
    try:
        upload.seek(0)
        probe = Image.open(upload)
        # Size check before load(): `load()` is what allocates the pixels.
        if (probe.width * probe.height) > MAX_IMAGE_PIXELS:
            raise ValidationError("That image is too large to process.")
        probe.load()
    except ValidationError:
        raise
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise ValidationError(_MESSAGE) from exc
    if probe.format not in ALLOWED_IMAGE_FORMATS:
        raise ValidationError(_MESSAGE)
    probe.thumbnail((MAX_IMAGE_DIMENSION, MAX_IMAGE_DIMENSION))
    if probe.mode == "RGBA":
        canvas = Image.new("RGB", probe.size, (255, 255, 255))
        canvas.paste(probe, mask=probe.split()[-1])
        probe = canvas
    elif probe.mode != "RGB":
        probe = probe.convert("RGB")
    buffer = io.BytesIO()
    probe.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    buffer.seek(0)
    return buffer, "image/jpeg"