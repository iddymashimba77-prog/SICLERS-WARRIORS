"""Patient profile serializers (approved Stage 4.5 endpoints).

SSoT field set: `docs/sdlc/03-system-design/database-design.md` row 162.
Field-level handling:
* ALL row-162 fields belong to the profile owner — a patient GETs and PATCHes
  their own 1:1 row only (owner scope, role-perm §8). No cross-profile reads.
* Server-side validation only (§13): genotype/gender vocabulary is enforced
  here even though the model also declares CHECKs — the API never trusts
  Flutter-side validation.
* `notes` is private but owner-visible; it is never echoed into any shared/
  feed/admin serializer. Audit logs record the event, not the content (§21).
"""

from rest_framework import serializers

from patients.models import CaregiverRelationship, Patient


def _name(user) -> str:
    if user is None:
        return "Member"
    return f"{user.first_name} {user.last_name}".strip() or "Member"


class PatientSerializer(serializers.ModelSerializer):
    class Meta:
        model = Patient
        fields = [
            "date_of_birth",
            "gender",
            "genotype",
            "diagnosis_date",
            "primary_diagnosis",
            "emergency_contact_name",
            "emergency_contact_phone",
            "emergency_contact_relation",
            "address_region",
            "address_city",
            "notes",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def validate_genotype(self, value):
        allowed = {"SS", "SC", "SBetaThal", "SBetaC", "unknown"}
        if value is not None and value not in allowed:
            raise serializers.ValidationError("Unsupported genotype value.")
        return value

    def validate_gender(self, value):
        allowed = {"FEMALE", "MALE", "OTHER", "UNSPECIFIED"}
        if value is not None and value not in allowed:
            raise serializers.ValidationError("Unsupported gender value.")
        return value


# ---------------------------------------------------------------------------
# Caregiver relationship (AUTH-1; database-design §8.1, endpoint-matrix §7)
# ---------------------------------------------------------------------------


class CaregiverRelationshipSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    caregiver_uid = serializers.UUIDField(source="user.uid", read_only=True)
    caregiver_name = serializers.SerializerMethodField()
    invited_by_name = serializers.SerializerMethodField()

    class Meta:
        model = CaregiverRelationship
        fields = [
            "id", "patient_uid", "patient_name", "caregiver_uid", "caregiver_name",
            "relationship_type", "status", "invited_by_name", "accepted_at",
            "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_patient_name(self, obj) -> str:
        return _name(obj.patient.user)

    def get_caregiver_name(self, obj) -> str:
        return _name(obj.user)

    def get_invited_by_name(self, obj) -> str:
        return _name(obj.invited_by)


class CaregiverInviteSerializer(serializers.Serializer):
    user_uid = serializers.UUIDField()
    relationship_type = serializers.ChoiceField(
        choices=[c for c, _ in CaregiverRelationship.RELATIONSHIP_TYPE]
    )


class CaregiverPermissionsSerializer(serializers.Serializer):
    """PATCH /caregivers/{id}/permissions — consent scope for the link (§10)."""

    resource_type = serializers.ChoiceField(
        choices=[
            "patients", "medical_records", "medications", "symptoms",
            "appointments", "health_timeline", "emergency",
        ],
    )
    permission_scope = serializers.ListField(
        child=serializers.CharField(max_length=120), allow_empty=False,
    )
    expires_at = serializers.DateTimeField()

    def validate_permission_scope(self, value):
        for code in value:
            parts = str(code).split(".")
            # Approved codes are `module.resource.action`; legacy matrix codes
            # are 2-part (`patients.view`, `caregivers.modify`).
            if len(parts) not in (2, 3) or not all(parts):
                raise serializers.ValidationError(
                    f"Invalid permission code: {code} (expected module.resource.action)."
                )
        return value


class CaregiverPatientBasicsSerializer(serializers.Serializer):
    """Consent-gated caregiver view of a linked patient's profile basics.

    PHI-free by construction: no DOB/genotype/diagnosis (data-classification:
    public basics only). The ACTIVE relationship + ACTIVE `patients.view`
    consent guard every read (C14).
    """

    patient_uid = serializers.UUIDField()
    first_name = serializers.CharField()
    last_name = serializers.CharField()
    relationship_type = serializers.CharField()