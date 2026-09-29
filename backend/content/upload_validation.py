"""News cover image upload validation + normalization (content CMS).

Server-side authority only: MIME content type and byte-size limits, plus a
Pillow decode probe (real magic bytes, not just the extension). Every upload is
re-encoded to a flat, ≤1600px JPEG so no untrusted bytes are ever served back
raw and the field is uniform regardless of source format.
"""

import io

from django.core.exceptions import ValidationError
from PIL import Image, UnidentifiedImageError

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_DIMENSION = 1600
JPEG_QUALITY = 85

_MESSAGE = "Unsupported image. Use a JPEG, PNG or WebP up to 5 MB."


def normalize_cover_image(upload):
    """Validate ``upload`` and return ``(bytes_buffer, 'image/jpeg')``.

    Raises :class:`django.core.exceptions.ValidationError` on any rejection.
    """
    if getattr(upload, "size", 0) > MAX_IMAGE_BYTES:
        raise ValidationError("Cover image exceeds the 5 MB limit.")
    content_type = (getattr(upload, "content_type", "") or "").lower()
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise ValidationError(_MESSAGE)
    try:
        upload.seek(0)
        probe = Image.open(upload)
        probe.load()
    except (UnidentifiedImageError, OSError) as exc:
        raise ValidationError(_MESSAGE) from exc
    if probe.format not in ("JPEG", "PNG", "WEBP"):
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