"""Phase 6 — editorial content: news articles, ticker, education library."""

from __future__ import annotations

import datetime as _dt

from django.utils import timezone

from content.models import NewsArticle, TickerAnnouncement
from education.models import EducationCategory, EducationalContent

from .base import TAG, uuid_for

NEWS_CATEGORIES = ["HEALTH", "BLOOD", "COMMUNITY", "EDUCATION", "EVENTS", "ANNOUNCEMENTS", "FUNDRAISING"]
EDU_CATEGORIES = [
    ("BASICS", "Sickle Cell Basics"),
    ("PAIN", "Pain & Crisis Management"),
    ("NUTRITION", "Nutrition & Hydration"),
    ("LIFESTYLE", "Living Well"),
    ("CAREGIVING", "Caregiving"),
    ("SCHOOL", "School & Work"),
]
TICKER_TYPES = ["INFO", "URGENT", "BLOOD", "EVENT", "DONATION", "SUCCESS"]


def _edu_categories():
    cats = []
    for order, (code, name) in enumerate(EDU_CATEGORIES):
        cat, _ = EducationCategory.objects.get_or_create(
            code=code, defaults={"name": name, "sort_order": order},
        )
        cats.append(cat)
    return cats


def seed(ctx) -> None:
    ctx.log("## Content & education")
    rng = ctx.rng
    now = timezone.now()

    for i, category in enumerate(NEWS_CATEGORIES, start=1):
        status = "PUBLISHED" if i % 4 else rng.choice(["DRAFT", "ARCHIVED"])
        NewsArticle.objects.update_or_create(
            uid=uuid_for("news", i),
            defaults={
                "title": f"{category.title()} update from {TAG}",
                "category": category,
                "excerpt": f"{TAG} short summary for the {category.lower()} desk.",
                "body": (
                    f"{TAG} demo article body. This synthetic piece exists only to "
                    f"populate the public news feed for QA of the {category.lower()} category."
                ),
                "cover_url": f"https://picsum.photos/seed/swqa-news-{i}/800/450",
                "cover_alt": f"{TAG} cover image {i}",
                "tags": [TAG, category.lower()],
                "featured": i <= 2,
                "pinned": i == 1,
                "pinned_at": now - _dt.timedelta(days=2) if i == 1 else None,
                "pinned_by": ctx.admin if i == 1 else None,
                "author": ctx.admin,
                "status": status,
                "published_at": now - _dt.timedelta(days=i) if status == "PUBLISHED" else None,
            },
        )
        ctx.track("news_articles")

    for i in range(1, 4):
        TickerAnnouncement.objects.update_or_create(
            uid=uuid_for("ticker", i),
            defaults={
                "message": f"{TAG} announcement #{i} — clinic hours and blood drive reminders.",
                "announcement_type": TICKER_TYPES[i % len(TICKER_TYPES)],
                "link_url": "",
                "is_active": i != 3,
                "priority": 10 - i,
            },
        )
        ctx.track("ticker_announcements")

    cats = _edu_categories()
    authors = ctx.users_of("DOCTOR") + ctx.users_of("PSYCHOLOGIST") + ctx.users_of("SOCIAL_SUPPORT")
    if not authors:
        authors = [ctx.admin]
    published = 0
    for i in range(1, 16):
        cat = cats[i % len(cats)]
        author = authors[i % len(authors)]
        if i <= 10:
            status = "PUBLISHED"
        else:
            status = ["DRAFT", "IN_REVIEW", "ARCHIVED", "REJECTED"][i % 4]
        EducationalContent.objects.update_or_create(
            uid=uuid_for("edu", i),
            defaults={
                "title": f"{TAG} {cat.name} guide #{i}",
                "body": (
                    f"{TAG} educational content on {cat.name.lower()}. Informational only, "
                    "not a substitute for professional medical advice."
                ),
                "category": cat,
                "author": author,
                "status": status,
                "reviewed_by": ctx.admin if status in ("PUBLISHED", "ARCHIVED", "REJECTED") else None,
                "reviewed_at": now - _dt.timedelta(days=3) if status in ("PUBLISHED", "REJECTED") else None,
                "rejection_reason": f"{TAG} needs a citation." if status == "REJECTED" else "",
                "cover_url": f"https://picsum.photos/seed/swqa-edu-{i}/800/450",
                "published_at": now - _dt.timedelta(days=i) if status == "PUBLISHED" else None,
            },
        )
        published += status == "PUBLISHED"
        ctx.track("educational_contents")

    ctx.log(
        f"- news={ctx.counts.get('news_articles', 0)} "
        f"ticker={ctx.counts.get('ticker_announcements', 0)} "
        f"education={ctx.counts.get('educational_contents', 0)} ({published} published)"
    )
