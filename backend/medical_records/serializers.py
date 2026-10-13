"""Consent serializers (AUTH-1; database-design §9, api-design consent rows)."""

from rest_framework import serializers

from accounts.models import Role
from . import models
from .permissions import MedicalRecordScope


class ConsentSerializer(serializers.ModelSerializer):
    granted_to_uid = serializers.UUIDField(source="granted_to.uid", read_only=True)
    granted_to_email = serializers.EmailField(source="granted_to.email", read_only=True)
    granted_to_name = serializers.SerializerMethodField()
    authorized_role_code = serializers.CharField(source="authorized_role.code", read_only=True)

    class Meta:
        model = models.Consent
        fields = [
            "uid", "resource_type", "resource_ids", "permission_scope", "purpose",
            "start_date", "expires_at", "status", "revoked_at",
            "authorized_role_code", "granted_to_uid", "granted_to_email",
            "granted_to_name", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_granted_to_name(self, obj) -> str:
        name = f"{obj.granted_to.first_name} {obj.granted_to.last_name}".strip()
        return name or "Member"


class ConsentCreateSerializer(serializers.Serializer):
    granted_to_uid = serializers.UUIDField()
    authorized_role_code = serializers.CharField(required=False, allow_blank=True, max_length=50)
    resource_type = serializers.ChoiceField(choices=[c for c, _ in models.Consent.RESOURCE_TYPE])
    resource_ids = serializers.ListField(child=serializers.IntegerField(), required=False)
    permission_scope = serializers.ListField(
        child=serializers.CharField(max_length=120), allow_empty=False,
    )
    purpose = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    start_date = serializers.DateTimeField(required=False)
    expires_at = serializers.DateTimeField()

    def validate_permission_scope(self, value):
        for code in value:
            parts = str(code).split(".")
            # Approved codes are `module.resource.action`; legacy matrix codes
            # are 2-part (`patients.view`, `auth.profile_view`).
            if len(parts) not in (2, 3) or not all(parts):
                raise serializers.ValidationError(
                    f"Invalid permission code: {code} (expected module.resource.action)."
                )
        return value


class ConsentPatchSerializer(serializers.Serializer):
    permission_scope = serializers.ListField(
        child=serializers.CharField(max_length=120), required=False,
    )
    purpose = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    expires_at = serializers.DateTimeField(required=False)

    def validate_permission_scope(self, value):
        for code in value:
            parts = str(code).split(".")
            if len(parts) not in (2, 3) or not all(parts):
                raise serializers.ValidationError(
                    f"Invalid permission code: {code} (expected module.resource.action)."
                )
        return value


class ConsentRenewSerializer(serializers.Serializer):
    expires_at = serializers.DateTimeField()

# ---------------------------------------------------------------------------
# Clinical records (FR-MEDREC-001/002/006; role-perm §3.4)
# ---------------------------------------------------------------------------


class RecordCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = models.RecordCategory
        fields = ["code", "name", "description", "is_active", "sort_order"]
        read_only_fields = fields


class ClinicalEncounterSerializer(serializers.ModelSerializer):
    facility_uid = serializers.UUIDField(source="facility.uid", read_only=True)
    facility_name = serializers.CharField(source="facility.name", read_only=True, default="")
    doctor_uid = serializers.UUIDField(source="doctor.uid", read_only=True)
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    created_by_uid = serializers.UUIDField(source="created_by.uid", read_only=True)

    class Meta:
        model = models.ClinicalEncounter
        fields = [
            "uid", "patient_uid", "encounter_type", "occurred_at", "summary",
            "facility_uid", "facility_name", "doctor_uid", "created_by_uid", "created_at",
        ]
        read_only_fields = fields


class MedicalRecordFileSerializer(serializers.ModelSerializer):
    """Attachment metadata. Deliberately never carries a resolvable URL.

    §9 says these bytes live in encrypted-at-rest storage and are never a public
    URL, so the download is an authorized API call rather than a link that could
    be pasted into a chat and read by whoever holds it.
    """

    uid = serializers.UUIDField(read_only=True)
    file_name = serializers.CharField(read_only=True)
    content_type = serializers.CharField(read_only=True)
    size_bytes = serializers.IntegerField(read_only=True)
    checksum = serializers.CharField(read_only=True)
    uploaded_by_uid = serializers.UUIDField(source="uploaded_by.uid", read_only=True)
    uploaded_at = serializers.DateTimeField(read_only=True)
    download_path = serializers.SerializerMethodField()

    class Meta:
        model = models.MedicalRecordFile
        fields = [
            "uid", "file_name", "content_type", "size_bytes", "checksum",
            "uploaded_by_uid", "uploaded_at", "download_path",
        ]
        read_only_fields = fields

    def get_download_path(self, obj) -> str:
        return f"/api/medical-records/files/{obj.uid}/download/"


class MedicalRecordListSerializer(serializers.ModelSerializer):
    """Chart-list row — clinical text is excluded until the row is opened."""

    uid = serializers.UUIDField(read_only=True)
    category_code = serializers.CharField(source="category.code", read_only=True)
    category_name = serializers.CharField(source="category.name", read_only=True)
    facility_name = serializers.CharField(source="facility.name", read_only=True, default="")
    recorded_by_name = serializers.SerializerMethodField()
    file_count = serializers.SerializerMethodField()

    class Meta:
        model = models.MedicalRecord
        fields = [
            "uid", "title", "category_code", "category_name", "status",
            "is_consent_visible", "recorded_at", "facility_name",
            "recorded_by_name", "file_count", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_recorded_by_name(self, obj) -> str:
        user = obj.recorded_by
        name = f"{user.first_name} {user.last_name}".strip()
        return name or user.email

    def get_file_count(self, obj) -> int:
        return obj.files.count()


class MedicalRecordDetailSerializer(serializers.ModelSerializer):
    uid = serializers.UUIDField(read_only=True)
    category_code = serializers.CharField(source="category.code", read_only=True)
    category_name = serializers.CharField(source="category.name", read_only=True)
    encounter_uid = serializers.UUIDField(source="encounter.uid", read_only=True)
    facility_uid = serializers.UUIDField(source="facility.uid", read_only=True)
    facility_name = serializers.CharField(source="facility.name", read_only=True, default="")
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    recorded_by_uid = serializers.UUIDField(source="recorded_by.uid", read_only=True)
    recorded_by_name = serializers.SerializerMethodField()
    files = MedicalRecordFileSerializer(many=True, read_only=True)
    can_edit = serializers.SerializerMethodField()
    can_upload = serializers.SerializerMethodField()

    class Meta:
        model = models.MedicalRecord
        fields = [
            "uid", "patient_uid", "title", "description", "category_code",
            "category_name", "encounter_uid", "facility_uid", "facility_name",
            "recorded_by_uid", "recorded_by_name", "recorded_at", "status",
            "is_consent_visible", "files", "can_edit", "can_upload",
            "created_at", "updated_at",
        ]
        read_only_fields = fields

    def _scope(self) -> "MedicalRecordScope | None":
        view = self.context.get("view")
        return view if isinstance(view, MedicalRecordScope) else None

    def get_recorded_by_name(self, obj) -> str:
        user = obj.recorded_by
        name = f"{user.first_name} {user.last_name}".strip()
        return name or user.email

    def get_can_edit(self, obj) -> bool:
        scope = self._scope()
        if scope is None:
            return False
        try:
            scope.assert_can_edit(obj)
        except Exception:
            return False
        return True

    def get_can_upload(self, obj) -> bool:
        scope = self._scope()
        if scope is None:
            return False
        user = scope.request.user
        return user.has_perm_code("medical_records.upload") and scope.get_can_attach(obj)


class MedicalRecordWriteSerializer(serializers.ModelSerializer):
    """Create/update body. Every reference is resolved server-side."""

    category_code = serializers.CharField(max_length=40)
    encounter_uid = serializers.UUIDField(required=False, allow_null=True)
    facility_uid = serializers.UUIDField(required=False, allow_null=True)
    # Defaults to "now" server-side: a client must never be able to backdate or
    # future-date the moment a finding was observed.
    recorded_at = serializers.DateTimeField(required=False)

    class Meta:
        model = models.MedicalRecord
        fields = [
            "title", "description", "category_code", "encounter_uid",
            "facility_uid", "recorded_at",
        ]

    def validate_category_code(self, value):
        category = models.RecordCategory.objects.filter(
            code=value, is_active=True,
        ).first()
        if category is None:
            raise serializers.ValidationError("Unknown record category.")
        return value

    def validate_title(self, value):
        cleaned = (value or "").strip()
        if not cleaned:
            raise serializers.ValidationError("A record needs a title.")
        return cleaned

    def validate_recorded_at(self, value):
        from django.utils import timezone

        if value > timezone.now():
            raise serializers.ValidationError("recorded_at cannot be in the future.")
        return value

    def resolve(self, *, patient, actor):
        """Map validated references to model instances (never client-pk trust)."""
        data = self.validated_data
        category = models.RecordCategory.objects.get(
            code=data["category_code"], is_active=True,
        )
        encounter = None
        encounter_uid = data.get("encounter_uid")
        if encounter_uid:
            encounter = models.ClinicalEncounter.objects.filter(
                uid=encounter_uid, patient=patient,
            ).first()
            if encounter is None:
                raise serializers.ValidationError(
                    {"encounter_uid": "That encounter does not belong to this patient."}
                )
        facility = None
        facility_uid = data.get("facility_uid")
        if facility_uid:
            from facilities.models import Facility

            facility = Facility.objects.filter(uid=facility_uid).first()
            if facility is None:
                raise serializers.ValidationError({"facility_uid": "Unknown facility."})
        return {"category": category, "encounter": encounter, "facility": facility}


class MedicalRecordStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=[c for c, _ in models.MedicalRecord.STATUS])
    reason = serializers.CharField(required=False, allow_blank=True, max_length=500)


class MedicalRecordVisibilitySerializer(serializers.Serializer):
    """The per-record opt-out from any consent-derived read set."""

    is_consent_visible = serializers.BooleanField()


class MedicalRecordShareSerializer(serializers.Serializer):
    """Hand one record to one named user (narrowest grant available)."""

    granted_to_uid = serializers.UUIDField()
    scope = serializers.ChoiceField(
        choices=["view", "download"], default="view",
        help_text="Least privilege requested for this specific record.",
    )
    expires_at = serializers.DateTimeField(required=False, allow_null=True)
    purpose = serializers.CharField(required=False, allow_blank=True, max_length=500)

    def validate_expires_at(self, value):
        from django.utils import timezone

        if value is not None and value <= timezone.now():
            raise serializers.ValidationError("expires_at must be in the future.")
        return value


class MedicalRecordEventSerializer(serializers.ModelSerializer):
    """One append-only history row (FR-MEDREC-006).

    `details` is non-PHI by construction — field names, counts, statuses and file
    names only — so this projection can be shown to the patient without leaking
    the clinical text through the audit trail.
    """

    actor_uid = serializers.UUIDField(source="actor.uid", read_only=True)
    actor_name = serializers.SerializerMethodField()
    record_uid = serializers.UUIDField(source="record.uid", read_only=True)

    class Meta:
        model = models.MedicalRecordEvent
        fields = [
            "uid", "record_uid", "actor_uid", "actor_name", "event_type",
            "from_status", "to_status", "details", "occurred_at",
        ]
        read_only_fields = fields

    def get_actor_name(self, obj) -> str:
        user = obj.actor
        if user is None:
            return "System"
        name = f"{user.first_name} {user.last_name}".strip()
        return name or user.email
