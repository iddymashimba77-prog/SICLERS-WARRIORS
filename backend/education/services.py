"""Education domain services (approved Stage 4.11).

Thin state-transition helpers so the review workflow (DRAFT -> IN_REVIEW ->
PUBLISHED/REJECTED, C12) is testable and the views never hand-roll status math.
Invalid transitions raise ``ValueError``; the view maps that to a 400.
"""

from django.utils import timezone

from notifications.services import create_notification

from . import models


def create_content(*, author, title, body, category, cover_url=""):
    return models.EducationalContent.objects.create(
        author=author, title=title, body=body,
        category=category, cover_url=cover_url or "",
        status="DRAFT",
    )


def update_content(content, *, title=None, body=None, category=None, cover_url=None):
    if title is not None:
        content.title = title
    if body is not None:
        content.body = body
    if category is not None:
        content.category = category
    if cover_url is not None:
        content.cover_url = cover_url
    content.save(
        update_fields=[
            "title", "body", "category", "cover_url", "updated_at",
        ]
    )
    return content


def submit_content(content):
    """Move an author-editable piece into the review queue (C12)."""
    if content.status not in models.SUBMITTABLE_STATUSES:
        raise ValueError("Only draft or rejected content can be submitted for review.")
    content.status = "IN_REVIEW"
    content.save(update_fields=["status", "updated_at"])
    return content


def admin_publish_content(content, *, actor):
    """One-step admin publish (DRAFT/ARCHIVED/REJECTED -> PUBLISHED).

    Mirrors the news CMS flow so an admin who authors {{content}} straight on
    the admin console can take it live without the two-step submit+review.
    Rejects publishing something already live.
    """
    if content.status == "PUBLISHED":
        raise ValueError("This content is already published.")
    now = timezone.now()
    content.status = "PUBLISHED"
    content.published_at = content.published_at or now
    content.reviewed_by = actor
    content.reviewed_at = now
    content.rejection_reason = ""
    content.save(
        update_fields=[
            "status", "published_at", "reviewed_by", "reviewed_at",
            "rejection_reason", "updated_at",
        ]
    )
    return content


def review_content(content, *, actor, decision, reason=""):
    """Approve (-> PUBLISHED) or reject (-> REJECTED). Only IN_REVIEW input."""
    if content.status != "IN_REVIEW":
        raise ValueError("Content is not pending review.")
    now = timezone.now()
    if decision == "reject":
        if not reason:
            raise ValueError("A reason is required to reject content.")
        content.status = "REJECTED"
        content.rejection_reason = reason
    else:
        content.status = "PUBLISHED"
        content.published_at = content.published_at or now
        content.rejection_reason = ""
    content.reviewed_by = actor
    content.reviewed_at = now
    content.save(
        update_fields=[
            "status", "reviewed_by", "reviewed_at",
            "rejection_reason", "published_at", "updated_at",
        ]
    )
    if content.author_id and content.author_id != actor.pk and content.status in ("PUBLISHED", "REJECTED"):
        phase = "published" if content.status == "PUBLISHED" else "needs review"
        create_notification(
            recipient=content.author,
            type_="SYSTEM",
            title="Warrior Academy update",
            body="Your submitted content was reviewed by the academy team.",
            data={"route": "education", "resource_type": "education_content"},
            related_resource_type="education_content",
            related_resource_id=str(content.uid),
            delivery_key=f"edu:{content.status.lower()}:{content.uid}",
        )
    return content

# ------------------------------------------------------- document attachments

# Documents warriors actually download with an article: printable handouts and
# slide decks. Anything that can execute or embed is refused so a public
# download can never become a stored-XSS or macro vector.
DOCUMENT_MAX_BYTES = 10 * 1024 * 1024  # 10 MB (matches DATA_UPLOAD_MAX_MEMORY_SIZE)
DOCUMENT_ALLOWED_CONTENT_TYPES = {
    "application/pdf": ".pdf",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": ".pptx",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}

# Magic-byte prefixes, mirroring ``content/upload_validation`` for images and
# adding the ZIP container used by OOXML. The declared MIME type is only a hint;
# the bytes decide.
_MAGIC_PREFIXES = (
    (b"%PDF-", "application/pdf"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"PK\x03\x04", "application/zip"),
)


class DocumentRejected(ValueError):
    """Raised when an uploaded document fails validation.

    Carries a ``field``/``reason`` pair so the view can return a structured 400
    the Flutter client can show verbatim instead of a generic "upload failed".
    """

    def __init__(self, reason, *, field="document"):
        super().__init__(reason)
        self.reason = reason
        self.field = field


def _sniff_content_type(head: bytes) -> str | None:
    for prefix, content_type in _MAGIC_PREFIXES:
        if head.startswith(prefix):
            return content_type
    return None


def validate_document_upload(uploaded):
    """Validate an uploaded education document.

    Checks, in order: presence, size ceiling, declared content type, and the
    actual leading bytes. A document whose declared type disagrees with its
    bytes is rejected rather than corrected — silently rewriting what a user
    uploaded would make the stored metadata a lie.
    """
    if uploaded is None:
        raise DocumentRejected("No document was uploaded.", field="document")

    size = getattr(uploaded, "size", 0) or 0
    if size <= 0:
        raise DocumentRejected("The document is empty.", field="document")
    if size > DOCUMENT_MAX_BYTES:
        raise DocumentRejected(
            f"The document is larger than {DOCUMENT_MAX_BYTES // (1024 * 1024)} MB.",
            field="document",
        )

    declared = (getattr(uploaded, "content_type", "") or "").split(";")[0].strip().lower()
    # Mobile pickers and some browsers report application/octet-stream for a
    # perfectly ordinary .pptx. That is an unknown hint, not a refusal — the
    # magic bytes below still have to prove the file is what it claims.
    if declared in ("", "application/octet-stream", "binary/octet-stream"):
        declared = ""
    if declared and declared not in DOCUMENT_ALLOWED_CONTENT_TYPES:
        raise DocumentRejected(
            "Unsupported document type. Use PDF, PPTX, DOCX, JPEG, PNG or WebP.",
            field="document",
        )

    head = uploaded.read(16)
    try:
        uploaded.seek(0)
    except (AttributeError, ValueError):  # pragma: no cover — non-seekable upload
        pass
    sniffed = _sniff_content_type(head)
    if sniffed is None:
        raise DocumentRejected(
            "That file is not a supported document.", field="document"
        )
    if sniffed == "application/zip":
        # OOXML (pptx/docx) is a ZIP container; the extension pair decides which,
        # and anything else zipped is refused.
        extension = (getattr(uploaded, "name", "") or "").lower()
        if not any(extension.endswith(suffix) for suffix in (".pptx", ".docx")):
            raise DocumentRejected(
                "Unsupported document type. Use PDF, PPTX, DOCX, JPEG, PNG or WebP.",
                field="document",
            )
        content_type = declared if declared in DOCUMENT_ALLOWED_CONTENT_TYPES else (
            "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            if extension.endswith(".pptx")
            else "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )
    else:
        content_type = sniffed

    name = _safe_document_name(getattr(uploaded, "name", "") or "document")
    _reject_extension_mismatch(name, content_type)
    return {"content_type": content_type, "size": size, "name": name}


# The extension a download must carry, per resolved content type. Enforcing it
# on the *stored* name is what stops `invoice.pdf.exe` from being served to a
# patient as an executable-looking attachment.
DOCUMENT_ALLOWED_EXTENSIONS = {
    "application/pdf": (".pdf",),
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": (".pptx",),
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": (".docx",),
    "image/jpeg": (".jpg", ".jpeg"),
    "image/png": (".png",),
    "image/webp": (".webp",),
}


def _reject_extension_mismatch(name: str, content_type: str) -> None:
    allowed = DOCUMENT_ALLOWED_EXTENSIONS.get(content_type)
    if allowed is None:  # pragma: no cover — content types above are exhaustive
        return
    if not name.lower().endswith(allowed):
        raise DocumentRejected(
            "The file name does not match the document type. Rename it to a "
            + "/".join(allowed)
            + " file and try again.",
            field="document",
        )


def _safe_document_name(raw_name: str) -> str:
    """Strip any path component and control characters from the filename."""
    base = raw_name.replace("\\", "/").split("/")[-1]
    cleaned = "".join(ch for ch in base if ch.isprintable()).strip()
    cleaned = cleaned.lstrip(".")[:255]
    return cleaned or "document"


def attach_document(content, *, uploaded, actor, meta=None):
    """Store a document against an education item.

    ``meta`` lets a caller validate once up front (before it opens a
    transaction or writes anything) instead of re-reading the upload here.

    Replaces — and deletes — any previously attached document so a content row
    never accumulates orphaned files in storage.
    """
    meta = meta or validate_document_upload(uploaded)
    previous = content.document_file.name if content.document_file else ""
    content.document_file = uploaded
    content.document_name = meta["name"]
    content.document_content_type = meta["content_type"]
    content.document_size = meta["size"]
    content.document_uploaded_at = timezone.now()
    content.document_uploaded_by = actor
    content.save(update_fields=[
        "document_file", "document_name", "document_content_type", "document_size",
        "document_uploaded_at", "document_uploaded_by", "updated_at",
    ])
    if previous:
        _delete_stored_file(previous)
    return content


def remove_document(content, *, actor=None):
    name = content.document_file.name if content.document_file else ""
    content.document_file = None
    content.document_name = ""
    content.document_content_type = ""
    content.document_size = None
    content.document_uploaded_at = None
    content.document_uploaded_by = None
    content.save(update_fields=[
        "document_file", "document_name", "document_content_type", "document_size",
        "document_uploaded_at", "document_uploaded_by", "updated_at",
    ])
    if name:
        _delete_stored_file(name)


def _delete_stored_file(name: str) -> None:
    from django.core.files.storage import default_storage

    try:
        if name and default_storage.exists(name):
            default_storage.delete(name)
    except OSError:  # pragma: no cover — storage backend failure is not fatal
        pass
