"""Verification-document upload validation + normalization (C5 pipeline).

Professionals and facilities self-register, then submit government-issued
scans/photos before their account is approved. Authority is always server-side,
mirroring ``content.upload_validation``:

* real byte probing (Pillow decode for images, ``%PDF-`` magic for PDFs) — the
  declared multipart ``Content-Type`` is only a hint and may legitimately be
  ``application/octet-stream`` from Flutter clients;
* images are re-encoded to a single safe JPEG (no untrusted bytes served back
  raw) but at a higher resolution than avatars/covers so a certificate or NIDA
  scan stays legible for the reviewer;
* PDFs are validated (magic + size) and stored raw.

Anything else — HTML, executables, oversized payloads, unreadable images — is
rejected outright.
"""

import io

from django.core.exceptions import ValidationError
from PIL import Image, UnidentifiedImageError

MAX_DOC_BYTES = 8 * 1024 * 1024
MAX_DOC_DIMENSION = 2600
MAX_DOC_PIXELS = 60_000_000
JPEG_QUALITY = 90

_IMAGE_MESSAGE = (
    "Unsupported document. Upload a JPEG, PNG or WebP scan/photo up to 8 MB."
)
_PDF_MESSAGE = "Unsupported document. PDFs must be real PDF files up to 8 MB."
_PDF_MAGIC = b"%PDF-"


def normalize_verification_document(upload):
    """Validate ``upload`` and return ``(bytes_buffer, content_type, extension)``.

    Images are returned as re-encoded JPEG bytes; PDFs as raw bytes. Raises
    :class:`django.core.exceptions.ValidationError` on any rejection.
    """
    if getattr(upload, "size", 0) > MAX_DOC_BYTES:
        raise ValidationError("That document is larger than the 8 MB limit.")

    head = _read_head(upload)
    if head.startswith(_PDF_MAGIC):
        return _normalize_pdf(upload)
    return _normalize_image(upload)


def _read_head(upload):
    upload.seek(0)
    head = upload.read(len(_PDF_MAGIC))
    upload.seek(0)
    return head


def _normalize_pdf(upload):
    raw = upload.read()
    if not raw.startswith(_PDF_MAGIC):
        raise ValidationError(_PDF_MESSAGE)
    if len(raw) > MAX_DOC_BYTES:
        raise ValidationError("That PDF is larger than the 8 MB limit.")
    buffer = io.BytesIO(raw)
    buffer.seek(0)
    return buffer, "application/pdf", "pdf"


def _normalize_image(upload):
    try:
        probe = Image.open(upload)
        if (probe.width * probe.height) > MAX_DOC_PIXELS:
            raise ValidationError("That document image is too large to process.")
        probe.load()
    except ValidationError:
        raise
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise ValidationError(_IMAGE_MESSAGE) from exc
    if probe.format not in ("JPEG", "PNG", "WEBP"):
        raise ValidationError(_IMAGE_MESSAGE)
    probe.thumbnail((MAX_DOC_DIMENSION, MAX_DOC_DIMENSION))
    if probe.mode == "RGBA":
        canvas = Image.new("RGB", probe.size, (255, 255, 255))
        canvas.paste(probe, mask=probe.split()[-1])
        probe = canvas
    elif probe.mode != "RGB":
        probe = probe.convert("RGB")
    buffer = io.BytesIO()
    probe.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    buffer.seek(0)
    return buffer, "image/jpeg", "jpg"