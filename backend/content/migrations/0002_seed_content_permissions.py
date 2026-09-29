"""Seed approved content CMS permissions (public home milestone).

    content.news.manage   -> SUPER_ADMIN, ADMIN
    content.ticker.manage -> SUPER_ADMIN, ADMIN

Least privilege: no other role gets CMS write access; MODERATOR continues to
moderate community content only. Public reading requires no permission (the
views are AllowAny and expose PUBLISHED/ACTIVE rows only).
"""

from django.db import migrations

CODES = [
    "content.news.manage",
    "content.ticker.manage",
]

ROLE_GRANTS = {
    "SUPER_ADMIN": list(CODES),
    "ADMIN": list(CODES),
}


def seed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        parts = code.split(".")
        Permission.objects.get_or_create(
            code=code, defaults={"module": parts[0], "resource": parts[1], "action": parts[-1]},
        )
    for role_code, codes in ROLE_GRANTS.items():
        role = Role.objects.get(code=role_code)
        for code in codes:
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code),
            )


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]