"""Facility directory (approved Stage 4.8 support surface).

Source of truth — docs/sdlc/03-system-design/database-design.md §5 (line 178):
  facilities | uid, name, facility_type CHECK(HOSPITAL CLINIC LABORATORY
               BLOOD_BANK PHARMACY OTHER), region, city, address,
               registration_number, is_verified, verified_by FK, verified_at,
               created_at, updated_at

`facilities` replaces the staged `hospitals` entity (unified facility; the
HOSPITAL role account links to its facility via operator).
"""

import uuid

from django.conf import settings
from django.db import models


class Facility(models.Model):
    FACILITY_TYPE = [
        ("HOSPITAL", "HOSPITAL"),
        ("CLINIC", "CLINIC"),
        ("LABORATORY", "LABORATORY"),
        ("BLOOD_BANK", "BLOOD_BANK"),
        ("PHARMACY", "PHARMACY"),
        ("OTHER", "OTHER"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    name = models.CharField(max_length=200)
    facility_type = models.CharField(max_length=30, choices=FACILITY_TYPE)
    region = models.CharField(max_length=100, blank=True)
    city = models.CharField(max_length=100, blank=True)
    address = models.TextField(blank=True)
    registration_number = models.CharField(max_length=100, blank=True)
    is_verified = models.BooleanField(default=False)
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="verified_facilities",
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    operator = models.OneToOneField(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="operated_facility",
        help_text="HOSPITAL role user linked to this facility.",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "facilities"
        ordering = ["name"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(facility_type__in=[
                    "HOSPITAL", "CLINIC", "LABORATORY", "BLOOD_BANK", "PHARMACY", "OTHER",
                ]),
                name="facility_type_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["region", "city"], name="facility_region_city_idx"),
        ]

    def __str__(self):
        return f"{self.name} ({self.facility_type})"
