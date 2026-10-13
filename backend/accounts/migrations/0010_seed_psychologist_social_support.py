"""Seed PSYCHOLOGIST and SOCIAL_SUPPORT roles with permissions.

This migration adds two new healthcare support roles to the RBAC system:
- PSYCHOLOGIST: Mental health professionals providing psychological support
- SOCIAL_SUPPORT: Social workers and support coordinators

These roles extend the healthcare team to provide holistic care for sickle cell patients.
"""

from django.db import migrations


# New roles to add
NEW_ROLES = [
    ("PSYCHOLOGIST", "Psychologist", True, False),
    ("SOCIAL_SUPPORT", "Social Support Worker", True, False),
]

# Permissions for PSYCHOLOGIST role
PSYCHOLOGIST_PERMISSIONS = [
    "auth.profile_view",
    "patients.view",
    # Mental health-specific permissions
    "psychology.assessments.create",
    "psychology.assessments.read",
    "psychology.assessments.update",
    "psychology.counseling.manage",
    "psychology.progress_notes.create",
    "psychology.progress_notes.read",
    "psychology.progress_notes.update",
]

# Permissions for SOCIAL_SUPPORT role
SOCIAL_SUPPORT_PERMISSIONS = [
    "auth.profile_view",
    "patients.view",
    # Social work-specific permissions
    "social.cases.create",
    "social.cases.read",
    "social.cases.update",
    "social.resources.manage",
    "social.referrals.create",
    "social.referrals.read",
    "social.referrals.update",
    "social.family_support.manage",
]


def seed_new_roles(apps, schema_editor):
    """Seed PSYCHOLOGIST and SOCIAL_SUPPORT roles with their permissions."""
    Role = apps.get_model("accounts", "Role")
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")

    # Create the new roles
    for code, name, is_system, self_registerable in NEW_ROLES:
        role, _ = Role.objects.get_or_create(
            code=code,
            defaults={"name": name, "is_system": is_system},
        )

    # Create and assign permissions for PSYCHOLOGIST
    psychologist_role = Role.objects.get(code="PSYCHOLOGIST")
    for perm_code in PSYCHOLOGIST_PERMISSIONS:
        parts = perm_code.split(".")
        permission, _ = Permission.objects.get_or_create(
            code=perm_code,
            defaults={
                "module": parts[0],
                "resource": parts[1] if len(parts) > 1 else "",
                "action": parts[-1],
            },
        )
        RolePermission.objects.get_or_create(
            role=psychologist_role, permission=permission
        )

    # Create and assign permissions for SOCIAL_SUPPORT
    social_support_role = Role.objects.get(code="SOCIAL_SUPPORT")
    for perm_code in SOCIAL_SUPPORT_PERMISSIONS:
        parts = perm_code.split(".")
        permission, _ = Permission.objects.get_or_create(
            code=perm_code,
            defaults={
                "module": parts[0],
                "resource": parts[1] if len(parts) > 1 else "",
                "action": parts[-1],
            },
        )
        RolePermission.objects.get_or_create(
            role=social_support_role, permission=permission
        )


def unseed_new_roles(apps, schema_editor):
    """Remove PSYCHOLOGIST and SOCIAL_SUPPORT roles and their permissions."""
    Role = apps.get_model("accounts", "Role")
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")

    # Remove role-permission associations
    for role_code in ["PSYCHOLOGIST", "SOCIAL_SUPPORT"]:
        RolePermission.objects.filter(role__code=role_code).delete()

    # Remove the roles
    Role.objects.filter(code__in=[r[0] for r in NEW_ROLES]).delete()

    # Remove the permissions (only if not used by other roles)
    all_perms = PSYCHOLOGIST_PERMISSIONS + SOCIAL_SUPPORT_PERMISSIONS
    for perm_code in all_perms:
        # Only delete if no other role uses this permission
        if not RolePermission.objects.filter(permission__code=perm_code).exists():
            Permission.objects.filter(code=perm_code).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0009_alter_securityevent_event_type"),
    ]

    operations = [
        migrations.RunPython(seed_new_roles, unseed_new_roles),
    ]
