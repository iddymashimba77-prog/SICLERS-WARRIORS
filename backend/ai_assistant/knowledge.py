"""Approved-knowledge grounding for the assistant (FR-AI-001, stage §16).

Deterministic retrieval over the **published** Warrior Academy / education
catalog (``educational_content``, status=PUBLISHED — the approved knowledge
source). This is honest, simple keyword ranking — NOT an external RAG or vector
service (none exists or is claimed anywhere in this build).

Contract:
* Only PUBLISHED, reviewed content is ever a source.
* A snippet is truncated to a bounded size (settings) so the provider never
  ships huge context; sources carry ``uid``/``title`` for citation.
* No match → empty list; the assistant then answers without claiming a source
  (never pretends a knowledge source was used when it wasn't).
"""

import re

from django.conf import settings

from education.models import EducationalContent

_STOPWORDS = frozenset({
    "the", "a", "an", "and", "or", "for", "to", "of", "in", "on", "with",
    "what", "why", "how", "is", "are", "do", "does", "can", "i", "me", "my",
    "you", "it", "this", "that", "about", "please", "tell", "help", "mean",
    "explain", "simple", "language", "questions", "doctor", "appointment",
    "explain", "understand",
})

_TOKEN_RE = re.compile(r"[a-z][a-z0-9]{1,}")


def _tokens(text: str) -> set[str]:
    words = _TOKEN_RE.findall((text or "").lower())
    return {w for w in words if w not in _STOPWORDS and len(w) > 1}


def search_approved_knowledge(query, *, limit=None) -> list[dict]:
    """Return up to ``limit`` published content snippets ranked by relevance."""
    limit = limit or settings.AI_KNOWLEDGE_SEARCH_LIMIT
    tokens = _tokens(query)
    if not tokens:
        return []

    published = EducationalContent.objects.filter(status="PUBLISHED").select_related("category")
    scored = []
    for content in published:
        body = re.sub(r"\s+", " ", content.body or "").lower()
        title = (content.title or "").lower()
        hay = f"{title}\n{body} {content.category.code.lower() if content.category_id else ''}"
        score = 0
        for token in tokens:
            if token in title:
                score += 3
            score += min(hay.count(token), 4)
        if score:
            scored.append((score, content))

    scored.sort(key=lambda pair: pair[0], reverse=True)
    results = []
    for score, content in scored[:limit]:
        snippet = re.sub(r"\s+", " ", content.body or "")[: settings.AI_KNOWLEDGE_SNIPPET_CHARS]
        results.append({
            "uid": str(content.uid),
            "title": content.title,
            "snippet": snippet,
            "score": score,
        })
    return results