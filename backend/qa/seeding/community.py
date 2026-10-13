"""Phase 5 — community: posts, comments, reactions, moderation reports."""

from __future__ import annotations

import datetime as _dt

from django.utils import timezone

from community.models import Comment, CommunityPost, Reaction, Report

from .base import TAG, uuid_for

CATEGORIES = ["SUPPORT", "EDUCATION", "GENERAL", "VENTING"]
TITLES = [
    "Living well with sickle cell",
    "Pain crisis coping tips",
    "Hydration really helps",
    "School and treatment balance",
    "Nutrition questions",
    "Thank you, care team",
]
REASONS = [
    "Possible misinformation about treatment.",
    "Off-topic promotional content.",
    "Unkind language reported by a member.",
]


def seed(ctx) -> None:
    ctx.log("## Community")
    rng = ctx.rng
    now = timezone.now()
    authors = ctx.users_of("PATIENT") + ctx.users_of("CAREGIVER")
    if not authors:
        ctx.log("- skipped (no authors)")
        return

    posts = []
    for i, author in enumerate(authors, start=1):
        status = "PUBLISHED" if i % 5 else rng.choice(["HIDDEN", "PENDING_REVIEW"])
        post, _ = CommunityPost.objects.update_or_create(
            uid=uuid_for("post", i),
            defaults={
                "author": author,
                "title": f"{TITLES[i % len(TITLES)]}",
                "content": (
                    f"{TAG} community post #{i}. {author.first_name} shares experience so "
                    f"other warriors feel less alone."
                ),
                "category": CATEGORIES[i % len(CATEGORIES)],
                "status": status,
            },
        )
        ctx.track("community_posts")
        posts.append(post)

    commenters = authors
    for i, post in enumerate(posts, start=1):
        for k in range(1, 2 + (i % 2)):
            author = commenters[(i + k) % len(commenters)]
            Comment.objects.get_or_create(
                post=post, author=author, content=f"{TAG} supportive comment #{k}.",
                defaults={"status": "PUBLISHED" if i % 4 else "HIDDEN"},
            )
            ctx.track("comments")
        for voter in commenters[:3]:
            Reaction.objects.get_or_create(
                post=post, user=voter, reaction_type="LIKE",
            )
            ctx.track("reactions")

    for i, post in enumerate(posts[: max(3, len(posts) // 4)], start=1):
        reporter = commenters[(i + 1) % len(commenters)]
        status = ["OPEN", "IN_REVIEW", "RESOLVED", "DISMISSED"][i % 4]
        Report.objects.get_or_create(
            reporter=reporter, target_type="POST", target_id=post.pk,
            defaults={
                "reason": f"{TAG} {REASONS[i % len(REASONS)]}",
                "status": status,
                "reviewed_by": ctx.admin if status in ("RESOLVED", "DISMISSED") else None,
                "review_notes": f"{TAG} moderation note." if status != "OPEN" else "",
            },
        )
        ctx.track("reports")

    ctx.log(
        f"- posts={ctx.counts.get('community_posts', 0)} "
        f"comments={ctx.counts.get('comments', 0)} reports={ctx.counts.get('reports', 0)}"
    )
