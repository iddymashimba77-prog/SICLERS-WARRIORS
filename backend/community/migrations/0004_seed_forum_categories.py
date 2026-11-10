"""Seed database-managed forum categories and map legacy posts.

The legacy four-value ``community_posts.category`` CHECK is retained for
backward-compatible API clients. New clients read these rows from
``GET /api/community/categories/``.
"""

from django.db import migrations
from django.utils import timezone

CATEGORIES = [
    {
        "slug": "sickle-cell-education",
        "name": "Sickle Cell Education",
        "description": "Understand sickle cell disease, treatments and self-care.",
        "legacy_code": "EDUCATION",
        "sort_order": 10,
    },
    {
        "slug": "treatment-and-care",
        "name": "Treatment & Care",
        "description": "Share experiences about care plans, appointments and medication.",
        "legacy_code": "",
        "sort_order": 20,
    },
    {
        "slug": "pain-and-crises",
        "name": "Pain & Crises",
        "description": "Support around pain episodes, crises and recovery.",
        "legacy_code": "VENTING",
        "sort_order": 30,
    },
    {
        "slug": "daily-living",
        "name": "Daily Living",
        "description": "School, work, nutrition, hydration and everyday routines.",
        "legacy_code": "",
        "sort_order": 40,
    },
    {
        "slug": "emotional-support",
        "name": "Emotional Support",
        "description": "A kind place to be heard and encourage one another.",
        "legacy_code": "SUPPORT",
        "sort_order": 50,
    },
    {
        "slug": "caregiving-and-family",
        "name": "Caregiving & Family",
        "description": "For caregivers, families and loved ones supporting a warrior.",
        "legacy_code": "",
        "sort_order": 60,
    },
    {
        "slug": "community-voices",
        "name": "Community Voices",
        "description": "General conversations, stories and community updates.",
        "legacy_code": "GENERAL",
        "sort_order": 70,
    },
]

LEGACY_MAP = {
    "EDUCATION": "sickle-cell-education",
    "VENTING": "pain-and-crises",
    "SUPPORT": "emotional-support",
    "GENERAL": "community-voices",
}


def seed(apps, schema_editor):
    ForumCategory = apps.get_model("community", "ForumCategory")
    CommunityPost = apps.get_model("community", "CommunityPost")

    categories = {}
    for row in CATEGORIES:
        category, _ = ForumCategory.objects.update_or_create(
            slug=row["slug"],
            defaults={
                "name": row["name"],
                "description": row["description"],
                "legacy_code": row["legacy_code"],
                "is_active": True,
                "sort_order": row["sort_order"],
            },
        )
        categories[row["slug"]] = category

    for post in CommunityPost.objects.all().iterator():
        slug = LEGACY_MAP.get(post.category)
        updates = []
        if slug and post.forum_category_id is None:
            post.forum_category_id = categories[slug].pk
            updates.append("forum_category")
        if post.last_activity_at is None or post.last_activity_at > timezone.now():
            post.last_activity_at = post.created_at
            updates.append("last_activity_at")
        if updates:
            post.save(update_fields=updates)


def unseed(apps, schema_editor):
    ForumCategory = apps.get_model("community", "ForumCategory")
    CommunityPost = apps.get_model("community", "CommunityPost")
    slugs = [row["slug"] for row in CATEGORIES]
    CommunityPost.objects.filter(forum_category__slug__in=slugs).update(forum_category=None)
    ForumCategory.objects.filter(slug__in=slugs).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("community", "0003_forumcategory_comment_depth_comment_is_edited_and_more"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
