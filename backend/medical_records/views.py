"""Consent API views (AUTH-1; api-design §consent, endpoint-matrix §9).

Surface:
    GET         /api/consents/             consents.view (owner / named grantee)
    POST        /api/consents/             consents.grant (PAT, owner)
    GET         /api/consents/active/      consents.view (grantee C2 eval)
    GET/PATCH   /api/consents/{uid}/       consents.view / consents.grant (owner)
    POST        /api/consents/{uid}/revoke/  consents.revoke (PAT, owner) — immediate
    POST        /api/consents/{uid}/renew/   consents.grant (PAT, owner) — extend

Object rules (role-perm §15):
* Owner = the patient on the consent row; a named grantee may read the detail
  the consent names them in (C3). SUP/ADM (C4) see the consent graph.
* Revocation is immediate (FR-MEDREC-005) and revoking a caregiver relationship
  also marks its consents REVOKED (caregiver view layer).
* Every grant/revoke/renew is audited both in `audit_logs` and
  `security_events` (role-perm §15, §22) — no PHI in log payloads.
"""

from django.db.models import Q
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, OpenApiTypes, extend_schema
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import Role, SecurityEvent, User
from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from patients.models import Patient
from . import models, serializers, services


def _resolve_user(uid) -> User:
    user = User.objects.filter(uid=uid, deleted_at__isnull=True).first()
    if user is None:
        raise NotFound("Grantee not found.")
    return user


class ConsentViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.ConsentSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("consents.view")]
    parser_classes = [JSONParser]

    def _is_owner(self, consent) -> bool:
        return consent.patient_profile.user_id == self.request.user.id

    def _owner_patient(self) -> Patient:
        if not self.request.user.is_patient:
            raise PermissionDenied("A PATIENT identity is required for this action.")
        patient, _ = Patient.objects.get_or_create(user=self.request.user)
        return patient

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.Consent.objects.none()
        qs = models.Consent.objects.select_related("patient_profile__user", "granted_to")
        if user.is_admin:
            return qs
        patient = Patient.objects.filter(user=user).first()
        mine = Q(patient_profile=patient) if patient else Q(pk__in=[])
        named = Q(granted_to=user)
        return qs.filter(mine | named)

    def get_object(self):
        consent = self.get_queryset().filter(uid=self.kwargs[self.lookup_url_kwarg]).first()
        if consent is None:
            raise NotFound("Consent not found.")
        return consent

    def create(self, request, *args, **kwargs):
        if not request.user.has_perm_code("consents.grant"):
            raise PermissionDenied("Only the patient can grant consent.")
        serializer = serializers.ConsentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = self._owner_patient()
        granted_to = _resolve_user(data["granted_to_uid"])
        if granted_to.id == request.user.id:
            raise ValidationError({"granted_to_uid": "You cannot grant consent to yourself."})
        role = None
        if data.get("authorized_role_code"):
            role = Role.objects.filter(code=data["authorized_role_code"].upper()).first()
            if role is None:
                raise ValidationError({"authorized_role_code": "Unknown role."})
        try:
            consent = services.grant(
                patient=patient,
                granted_to=granted_to,
                permission_scope=data["permission_scope"],
                resource_type=data["resource_type"],
                resource_ids=data.get("resource_ids"),
                purpose=data.get("purpose", ""),
                start_date=data.get("start_date"),
                expires_at=data["expires_at"],
                authorized_role=role,
            )
        except ValueError as exc:
            raise ValidationError({"expires_at": str(exc)})
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=consent.pk, request=request,
            details={
                "grantee": str(granted_to.uid), "resource_type": consent.resource_type,
                "permission_scope": consent.permission_scope,
            },
        )
        _event(request.user, "CONSENT_GRANTED", {"grantee": str(granted_to.uid)})
        return Response(
            serializers.ConsentSerializer(consent).data, status=http_status.HTTP_201_CREATED,
        )

    def partial_update(self, request, *args, **kwargs):
        if not request.user.has_perm_code("consents.grant"):
            raise PermissionDenied("Only the patient can amend consent.")
        consent = self.get_object()
        if not self._is_owner(consent):
            raise PermissionDenied("Only the granting patient can amend this consent.")
        serializer = serializers.ConsentPatchSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if data.get("permission_scope") is not None:
            consent.permission_scope = [str(c) for c in data["permission_scope"]]
        if data.get("purpose") is not None:
            consent.purpose = data["purpose"]
        if data.get("expires_at") is not None:
            if data["expires_at"] <= timezone.now():
                raise ValidationError({"expires_at": "expires_at must be in the future."})
            consent.expires_at = data["expires_at"]
        consent.save()
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=consent.pk, request=request,
            details={"action": "amend", "permission_scope": consent.permission_scope},
        )
        return Response(serializers.ConsentSerializer(consent).data)

    @action(detail=False, methods=["get"], url_path="active")
    def active(self, request):
        """C2 evaluation for the caller: union of ACTIVE permission scopes."""
        services.expire_due()
        user = request.user
        nown = timezone.now()
        rows = models.Consent.objects.filter(
            status="ACTIVE", start_date__lte=nown, expires_at__gt=nown,
        ).select_related("patient_profile", "granted_to")
        if not user.is_admin:
            patient = Patient.objects.filter(user=user).first()
            mine = Q(patient_profile=patient) if patient else Q(pk__in=[])
            named = Q(granted_to=user)
            rows = rows.filter(mine | named)
        codes: set[str] = set()
        for row in rows:
            for c in row.permission_scope or []:
                codes.add(str(c))
        return Response({
            "permission_scope": sorted(codes),
            "count": rows.count(),
        })

    @action(detail=True, methods=["post"], url_path="revoke")
    def revoke(self, request, uid=None):
        if not request.user.has_perm_code("consents.revoke"):
            raise PermissionDenied("Only the patient can revoke consent.")
        consent = self.get_object()
        if not self._is_owner(consent):
            raise PermissionDenied("Only the granting patient can revoke this consent.")
        reason = (request.data or {}).get("reason", "")
        row = services.revoke(consent, actor=request.user)
        record_audit(
            actor=request.user, action_code="consents.revoke",
            resource_type="consent", resource_id=row.pk, request=request,
            details={"reason": str(reason)[:500]},
        )
        _event(request.user, "CONSENT_REVOKED", {"consent": str(row.uid)})
        return Response(serializers.ConsentSerializer(row).data)

    @action(detail=True, methods=["post"], url_path="renew")
    def renew(self, request, uid=None):
        if not request.user.has_perm_code("consents.grant"):
            raise PermissionDenied("Only the patient can renew consent.")
        consent = self.get_object()
        if not self._is_owner(consent):
            raise PermissionDenied("Only the granting patient can renew this consent.")
        serializer = serializers.ConsentRenewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            row = services.renew(
                consent, expires_at=serializer.validated_data["expires_at"], actor=request.user,
            )
        except ValueError as exc:
            raise ValidationError({"expires_at": str(exc)})
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=row.pk, request=request,
            details={"action": "renew", "expires_at": row.expires_at.isoformat()},
        )
        _event(request.user, "CONSENT_RENEWED", {"consent": str(row.uid)})
        return Response(serializers.ConsentSerializer(row).data)


def _event(user, event_type, detail=None):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type, detail=dict(detail or {}))
    except Exception:
        pass

# ---------------------------------------------------------------------------
# Clinical records (FR-MEDREC-001/002/006; role-perm §3.4, database-design §9)
# ---------------------------------------------------------------------------
#
# Surface (mounted under /api/ and /api/v1/):
#   GET/POST        /api/medical-records/
#   GET/PATCH/DELETE /api/medical-records/{uid}/
#   POST            /api/medical-records/{uid}/status/     archive/suppress
#   POST            /api/medical-records/{uid}/visibility/ opt out of sharing
#   GET/POST        /api/medical-records/{uid}/files/      list / attach
#   GET/DELETE      /api/medical-records/{uid}/files/{file_uid}/
#   GET/POST        /api/medical-records/{uid}/share/      per-record grant
#   POST            /api/medical-records/{uid}/share/revoke/
#   GET             /api/medical-records/{uid}/history/    append-only history
#   GET             /api/medical-records/history/          chart-wide history
#   GET             /api/medical-records/files/{file_uid}/download/
#   GET             /api/record-categories/                catalog
#   GET/POST        /api/clinical-encounters/              visits
#
# Two invariants hold across every action here:
#   1. **The read set is the only gate.** Querysets are filtered by
#      `MedicalRecordScope.readable_patient_ids()`, so an unauthorized patient
#      id yields an empty page / a 404 — never a 403 that would confirm the
#      record exists.
#   2. **Every read and every write lands in the append-only history.**
#      FR-MEDREC-006 is satisfied by `medical_record_events`, which refuses to
#      update or delete a row, not merely by convention.

from django.db.models import Q
from django.http import FileResponse
from django.utils import timezone
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus
from audit.services import record_audit
from core.pagination import CorePageNumberPagination

from . import models, serializers, services
from .permissions import (
    MedicalRecordAccess,
    MedicalRecordScope,
    DOWNLOAD,
    assert_oversight_reason,
    oversight_reason,
    patient_profile_for,
)
from .throttles import (
    MedicalRecordFileThrottle,
    MedicalRecordShareThrottle,
    MedicalRecordWriteThrottle,
)


class RecordCategoryListView(viewsets.ReadOnlyModelViewSet):
    """The approved record-category catalog (DB design §9). Reference data."""

    queryset = models.RecordCategory.objects.filter(is_active=True)
    serializer_class = serializers.RecordCategorySerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    lookup_field = "code"
    pagination_class = CorePageNumberPagination


class ClinicalEncounterViewSet(
    mixins.ListModelMixin,
    mixins.CreateModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
    MedicalRecordScope,
):
    """Visits that produced records. Scoped to the caller's read set."""

    serializer_class = serializers.ClinicalEncounterSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination
    queryset = models.ClinicalEncounter.objects.none()

    def get_queryset(self):
        user = self.request.user
        return models.ClinicalEncounter.objects.filter(
            patient_id__in=services.readable_patient_ids(user)
        ).select_related("facility", "doctor", "patient__user")

    def create(self, request, *args, **kwargs):
        # Creating an encounter is authoring clinical data, so it needs the
        # clinical-writer gate (C15), not merely "is authenticated".
        allowed = services.clinical_writer_patient_ids(request.user)
        if not allowed:
            raise PermissionDenied(
                "Only a clinician with a patient consent can record an encounter."
            )
        from patients.models import Patient

        patient_uid = (request.data or {}).get("patient_uid")
        if patient_uid:
            patient = Patient.objects.filter(user__uid=patient_uid).first()
        else:
            patient = patient_profile_for(request.user)
        if patient is None:
            raise ValidationError({"patient_uid": "That patient account does not exist."})
        if patient.pk not in allowed:
            raise PermissionDenied("You do not have consent for this patient.")

        facility = None
        facility_uid = (request.data or {}).get("facility_uid")
        if facility_uid:
            from facilities.models import Facility

            facility = Facility.objects.filter(uid=facility_uid).first()
            if facility is None:
                raise ValidationError({"facility_uid": "Unknown facility."})
        try:
            services.assert_writer_facility_is_verified(facility)
        except ValueError as exc:
            raise ValidationError({"facility_uid": str(exc)})

        encounter_type = (request.data or {}).get("encounter_type")
        if encounter_type not in dict(models.ClinicalEncounter.ENCOUNTER_TYPE):
            raise ValidationError({"encounter_type": "Unknown encounter type."})
        occurred_at = (request.data or {}).get("occurred_at")
        if not occurred_at:
            raise ValidationError({"occurred_at": "occurred_at is required."})

        encounter = models.ClinicalEncounter.objects.create(
            patient=patient,
            facility=facility,
            doctor=_doctor_for(request.user),
            staff=request.user if request.user.has_perm_code("medical_records.create") else None,
            encounter_type=encounter_type,
            occurred_at=occurred_at,
            summary=(request.data or {}).get("summary", "")[:4000],
            created_by=request.user,
        )
        services.record_event(
            patient=patient, actor=request.user, event_type="CREATED",
            details={"entity": "encounter", "encounter_uid": str(encounter.uid),
                     "encounter_type": encounter_type},
        )
        record_audit(
            actor=request.user, action_code="medical_records.create",
            resource_type="clinical_encounter", resource_id=encounter.pk, request=request,
            details={"encounter_uid": str(encounter.uid), "type": encounter_type},
        )
        return Response(
            serializers.ClinicalEncounterSerializer(encounter).data,
            status=http_status.HTTP_201_CREATED,
        )


def _doctor_for(user):
    """The `doctors.Doctor` row for a user, or None (staff may have none)."""
    try:
        return user.doctor_profile
    except Exception:
        return None


class MedicalRecordViewSet(
    mixins.ListModelMixin,
    mixins.CreateModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    mixins.DestroyModelMixin,
    viewsets.GenericViewSet,
    MedicalRecordScope,
):
    """The clinical chart. Ownership = patient, authorship = `recorded_by`."""

    lookup_field = "uid"
    serializer_class = serializers.MedicalRecordDetailSerializer
    permission_classes = [IsAuthenticatedRespectStatus, MedicalRecordAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination
    throttle_classes = [MedicalRecordWriteThrottle]
    queryset = models.MedicalRecord.objects.none()

    def get_serializer_class(self):
        if self.action == "list":
            return serializers.MedicalRecordListSerializer
        return serializers.MedicalRecordDetailSerializer

    def get_queryset(self):
        return self.record_queryset(
            models.MedicalRecord.objects.filter(deleted_at__isnull=True)
        ).select_related("category", "facility", "recorded_by", "patient__user")

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["view"] = self
        return context

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        status_param = (request.query_params.get("status") or "").strip().upper()
        if status_param:
            if status_param not in models.MedicalRecord.STATUSES:
                raise ValidationError({"status": "Unknown status filter."})
            queryset = queryset.filter(status=status_param)
        category_code = (request.query_params.get("category") or "").strip()
        if category_code:
            queryset = queryset.filter(category__code=category_code)
        return self._paginated(queryset, request)

    def _paginated(self, queryset, request):
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        return Response(self.get_serializer(queryset, many=True).data)

    def retrieve(self, request, *args, **kwargs):
        record = self.get_record_or_404(kwargs[self.lookup_field])
        self.assert_can_read(record)
        # FR-MEDREC-006: a read of a chart entry is itself an audited event.
        self._log_read(record, "VIEWED")
        return Response(self.get_serializer(record).data)

    def _log_read(self, record, event_type):
        services.record_event(
            record=record, actor=self.request.user, event_type=event_type,
            details={"via": self.request.path},
        )
        record_audit(
            actor=self.request.user,
            action_code=f"medical_records.{event_type.lower()}",
            resource_type="medical_record", resource_id=record.pk,
            request=self.request, details={"record_uid": str(record.uid)},
        )

    def create(self, request, *args, **kwargs):
        payload = request.data or {}
        patient = self._resolve_write_patient(payload.get("patient_uid"))
        serializer = serializers.MedicalRecordWriteSerializer(data=payload)
        serializer.is_valid(raise_exception=True)
        resolved = serializer.resolve(patient=patient, actor=request.user)
        if resolved["facility"] is not None and self._is_clinical_writer():
            try:
                services.assert_writer_facility_is_verified(resolved["facility"])
            except ValueError as exc:
                raise ValidationError({"facility_uid": str(exc)})

        record = models.MedicalRecord.objects.create(
            patient=patient,
            title=serializer.validated_data["title"],
            description=serializer.validated_data.get("description", ""),
            recorded_by=request.user,
            recorded_at=serializer.validated_data.get("recorded_at", timezone.now()),
            **resolved,
        )
        services.record_event(
            record=record, actor=request.user, event_type="CREATED",
            details={"entity": "medical_record", "category": record.category.code},
        )
        record_audit(
            actor=request.user, action_code="medical_records.create",
            resource_type="medical_record", resource_id=record.pk, request=request,
            details={"record_uid": str(record.uid), "category": record.category.code},
        )
        return Response(
            serializers.MedicalRecordDetailSerializer(
                record, context=self.get_serializer_context(),
            ).data,
            status=http_status.HTTP_201_CREATED,
        )

    def _resolve_write_patient(self, patient_uid):
        """Who a new record is for: self, or a consented clinical patient (C15)."""
        user = self.request.user
        own = patient_profile_for(user)
        if patient_uid in (None, "", "me"):
            if own is None:
                raise PermissionDenied("A patient profile is required to add a record.")
            return own
        from patients.models import Patient

        target = Patient.objects.filter(user__uid=patient_uid).first()
        if target is None:
            raise ValidationError({"patient_uid": "That patient account does not exist."})
        if own is not None and target.pk == own.pk:
            return target
        if target.pk in services.clinical_writer_patient_ids(user):
            return target
        raise PermissionDenied("You do not have consent to write to this record.")

    def update(self, request, *args, **kwargs):
        record = self.get_record_or_404(kwargs[self.lookup_field])
        self.assert_can_edit(record)
        partial = kwargs.pop("partial", False)
        serializer = serializers.MedicalRecordWriteSerializer(
            record, data=request.data, partial=partial,
        )
        serializer.is_valid(raise_exception=True)
        changed_fields = []
        if "title" in serializer.validated_data:
            record.title = serializer.validated_data["title"]
            changed_fields.append("title")
        if "description" in serializer.validated_data:
            record.description = serializer.validated_data["description"]
            changed_fields.append("description")
        if "category_code" in serializer.validated_data:
            record.category = models.RecordCategory.objects.get(
                code=serializer.validated_data["category_code"], is_active=True,
            )
            changed_fields.append("category")
        if "facility_uid" in serializer.validated_data:
            facility_uid = serializer.validated_data["facility_uid"]
            if facility_uid is None:
                record.facility = None
            else:
                from facilities.models import Facility

                facility = Facility.objects.filter(uid=facility_uid).first()
                if facility is None:
                    raise ValidationError({"facility_uid": "Unknown facility."})
                if self._is_clinical_writer():
                    try:
                        services.assert_writer_facility_is_verified(facility)
                    except ValueError as exc:
                        raise ValidationError({"facility_uid": str(exc)})
                record.facility = facility
            changed_fields.append("facility")
        if "recorded_at" in serializer.validated_data:
            record.recorded_at = serializer.validated_data["recorded_at"]
            changed_fields.append("recorded_at")
        record.save()
        services.record_event(
            record=record, actor=request.user, event_type="UPDATED",
            details={"fields": changed_fields},
        )
        record_audit(
            actor=request.user, action_code="medical_records.update",
            resource_type="medical_record", resource_id=record.pk, request=request,
            details={"record_uid": str(record.uid), "fields": changed_fields},
        )
        return Response(
            serializers.MedicalRecordDetailSerializer(
                record, context=self.get_serializer_context(),
            ).data,
        )

    def partial_update(self, request, *args, **kwargs):
        kwargs["partial"] = True
        return self.update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        record = self.get_record_or_404(kwargs[self.lookup_field])
        self.assert_can_delete(record)
        # C16/C4: soft delete only — a clinical chart is never hard-deleted, so
        # the history and the consent trail stay coherent.
        record.deleted_at = timezone.now()
        record.save(update_fields=["deleted_at", "updated_at"])
        services.record_event(
            record=record, actor=request.user, event_type="DELETED",
            details={"soft": True},
        )
        record_audit(
            actor=request.user, action_code="medical_records.delete",
            resource_type="medical_record", resource_id=record.pk, request=request,
            details={"record_uid": str(record.uid), "soft": True},
        )
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    # -- status / visibility -------------------------------------------------

    @action(detail=True, methods=["post"], url_path="status")
    def set_status(self, request, uid=None, **kwargs):
        record = self.get_record_or_404(uid)
        self.assert_can_set_status(record)
        serializer = serializers.MedicalRecordStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        target = serializer.validated_data["status"]
        previous = record.status
        if previous == target:
            return Response(
                serializers.MedicalRecordDetailSerializer(
                    record, context=self.get_serializer_context(),
                ).data,
            )
        record.status = target
        record.save(update_fields=["status", "updated_at"])
        services.record_event(
            record=record, actor=request.user, event_type="STATUS_CHANGED",
            from_status=previous, to_status=target,
            details={"reason": serializer.validated_data.get("reason", "")[:500]},
        )
        record_audit(
            actor=request.user, action_code="medical_records.update",
            resource_type="medical_record", resource_id=record.pk, request=request,
            details={"record_uid": str(record.uid), "from": previous, "to": target},
        )
        return Response(
            serializers.MedicalRecordDetailSerializer(
                record, context=self.get_serializer_context(),
            ).data,
        )

    @action(detail=True, methods=["post"], url_path="visibility")
    def set_visibility(self, request, uid=None, **kwargs):
        """Per-record opt-out from every consent-derived read set."""
        record = self.get_record_or_404(uid)
        if not self._is_owner(record):
            raise PermissionDenied("Only the patient can change who may see this record.")
        serializer = serializers.MedicalRecordVisibilitySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        record.is_consent_visible = serializer.validated_data["is_consent_visible"]
        record.save(update_fields=["is_consent_visible", "updated_at"])
        services.record_event(
            record=record, actor=request.user, event_type="UPDATED",
            details={"fields": ["is_consent_visible"],
                     "value": record.is_consent_visible},
        )
        return Response(
            serializers.MedicalRecordDetailSerializer(
                record, context=self.get_serializer_context(),
            ).data,
        )

    # -- files ---------------------------------------------------------------

    @action(
        detail=True, methods=["get", "post"],
        url_path="files", parser_classes=[JSONParser, MultiPartParser, FormParser],
        throttle_classes=[MedicalRecordFileThrottle],
    )
    def files(self, request, uid=None, **kwargs):
        record = self.get_record_or_404(uid)
        self.assert_can_read(record)
        if request.method == "GET":
            rows = record.files.all()
            return Response(serializers.MedicalRecordFileSerializer(rows, many=True).data)
        self.assert_can_attach(record)
        try:
            row = services.attach_record_file(
                record=record, uploaded=request.FILES.get("file"), actor=request.user,
            )
        except services.RecordFileRejected as exc:
            raise ValidationError({exc.field: exc.reason})
        record_audit(
            actor=request.user, action_code="medical_records.upload",
            resource_type="medical_record_file", resource_id=row.pk, request=request,
            details={"record_uid": str(record.uid), "file_name": row.file_name,
                     "size_bytes": row.size_bytes},
        )
        return Response(
            serializers.MedicalRecordFileSerializer(row).data,
            status=http_status.HTTP_201_CREATED,
        )

    @extend_schema(
        parameters=[
            OpenApiParameter(name="file_uid", type=OpenApiTypes.STR, location=OpenApiParameter.PATH),
        ],
    )
    @action(
        detail=True, methods=["get", "delete"], url_path=r"files/(?P<file_uid>[^/.]+)",
    )
    def file_detail(self, request, uid=None, file_uid=None, **kwargs):
        record = self.get_record_or_404(uid)
        self.assert_can_read(record)
        row = record.files.filter(uid=file_uid).first()
        if row is None:
            raise NotFound("Attachment not found.")
        if request.method == "DELETE":
            self.assert_can_attach(record)
            services.remove_record_file(row=row, actor=request.user)
            record_audit(
                actor=request.user, action_code="medical_records.upload",
                resource_type="medical_record_file", resource_id=row.pk, request=request,
                details={"record_uid": str(record.uid), "removed": True},
            )
            return Response(status=http_status.HTTP_204_NO_CONTENT)
        if not self.request.user.has_perm_code(DOWNLOAD):
            raise PermissionDenied("You cannot download this record.")
        self._log_read(record, "DOWNLOADED")
        return Response(serializers.MedicalRecordFileSerializer(row).data)

    @extend_schema(
        parameters=[
            OpenApiParameter(name="file_uid", type=OpenApiTypes.STR, location=OpenApiParameter.PATH),
        ],
    )
    @action(
        detail=False, methods=["get"], url_path=r"files/(?P<file_uid>[^/.]+)/download",
        permission_classes=[IsAuthenticatedRespectStatus],
    )
    def download_file(self, request, file_uid=None, **kwargs):
        row = models.MedicalRecordFile.objects.filter(uid=file_uid).select_related(
            "record__patient",
        ).first()
        if row is None:
            raise NotFound("Attachment not found.")
        record = row.record
        # Reuse the chart's own read gate so a file can never be a way around it.
        self.assert_can_read(record)
        if not request.user.has_perm_code(DOWNLOAD):
            raise PermissionDenied("You cannot download this record.")
        try:
            handle = row.file.open("rb")
        except (FileNotFoundError, OSError):
            raise NotFound("The stored attachment is no longer available.")
        response = FileResponse(handle, content_type=row.content_type)
        response["Content-Disposition"] = f'attachment; filename="{row.file_name}"'
        self._log_read(record, "DOWNLOADED")
        return response

    # -- per-record sharing --------------------------------------------------

    @action(
        detail=True, methods=["get", "post"], url_path="share",
        throttle_classes=[MedicalRecordShareThrottle],
        parser_classes=[JSONParser],
    )
    def share(self, request, uid=None, **kwargs):
        record = self.get_record_or_404(uid)
        self.assert_can_read(record)
        if request.method == "GET":
            if not self._is_owner(record):
                raise PermissionDenied("Only the patient can see who a record is shared with.")
            rows = record.links.select_related("granted_to")
            return Response([
                {
                    "uid": str(row.uid),
                    "granted_to_uid": str(row.granted_to.uid),
                    "granted_to_name": (
                        f"{row.granted_to.first_name} {row.granted_to.last_name}".strip()
                        or row.granted_to.email
                    ),
                    "scope": row.scope,
                    "expires_at": row.expires_at,
                    "granted_at": row.granted_at,
                    "revoked_at": row.revoked_at,
                    "active": row.is_active_now(),
                }
                for row in rows
            ])
        if not self._is_owner(record):
            raise PermissionDenied("Only the patient can share this record.")
        if not record.is_consent_visible or record.status == "SUPPRESSED":
            raise ValidationError(
                "This record is private. Make it consent-visible before sharing it."
            )
        serializer = serializers.MedicalRecordShareSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        from accounts.models import User

        grantee = User.objects.filter(
            uid=serializer.validated_data["granted_to_uid"], deleted_at__isnull=True,
        ).first()
        if grantee is None:
            raise ValidationError({"granted_to_uid": "That member does not exist."})
        if grantee.pk == request.user.pk:
            raise ValidationError({"granted_to_uid": "You already own this record."})

        link, created = models.MedicalRecordLink.objects.update_or_create(
            record=record,
            granted_to=grantee,
            defaults={
                "scope": serializer.validated_data["scope"],
                "expires_at": serializer.validated_data.get("expires_at"),
                "granted_by_patient": record.patient,
                "revoked_at": None,
                "revoked_by": None,
            },
        )
        services.record_event(
            record=record, actor=request.user, event_type="SHARED",
            details={"grantee_uid": str(grantee.uid),
                     "scope": link.scope,
                     "expires_at": link.expires_at.isoformat() if link.expires_at else None},
        )
        record_audit(
            actor=request.user, action_code="medical_records.share",
            resource_type="medical_record", resource_id=record.pk, request=request,
            details={"grantee_uid": str(grantee.uid), "scope": link.scope},
        )
        return Response(
            {"uid": str(link.uid), "granted_to_uid": str(grantee.uid),
             "scope": link.scope, "expires_at": link.expires_at},
            status=http_status.HTTP_201_CREATED if created else http_status.HTTP_200_OK,
        )

    @action(detail=True, methods=["post"], url_path="share/revoke",
            throttle_classes=[MedicalRecordShareThrottle], parser_classes=[JSONParser])
    def revoke_share(self, request, uid=None, **kwargs):
        record = self.get_record_or_404(uid)
        if not self._is_owner(record):
            raise PermissionDenied("Only the patient can revoke access to this record.")
        link_uid = (request.data or {}).get("link_uid")
        link = record.links.filter(uid=link_uid).first() if link_uid else None
        if link is None:
            link = record.links.filter(revoked_at__isnull=True).first()
        if link is None:
            raise NotFound("No active share to revoke.")
        link.revoked_at = timezone.now()
        link.revoked_by = request.user
        link.save(update_fields=["revoked_at", "revoked_by"])
        services.record_event(
            record=record, actor=request.user, event_type="SHARE_REVOKED",
            details={"grantee_uid": str(link.granted_to.uid)},
        )
        return Response({"uid": str(link.uid), "revoked_at": link.revoked_at})

    # -- history -------------------------------------------------------------

    @action(detail=True, methods=["get"], url_path="history",
            permission_classes=[IsAuthenticatedRespectStatus, MedicalRecordAccess],
            parser_classes=[JSONParser], throttle_classes=[])
    def history(self, request, uid=None, **kwargs):
        record = self.get_record_or_404(uid)
        self.assert_can_read(record)
        return Response(_history_payload(record.history.select_related("actor").all()))

    @action(detail=False, methods=["get"], url_path="history",
            permission_classes=[IsAuthenticatedRespectStatus, MedicalRecordAccess],
            parser_classes=[JSONParser], throttle_classes=[])
    def chart_history(self, request, **kwargs):
        """Chart-wide append-only history for the caller's readable patients."""
        patient_ids = self.readable_patient_ids()
        rows = models.MedicalRecordEvent.objects.filter(
            patient_id__in=patient_ids,
        ).select_related("actor", "record").order_by("-occurred_at")[:200]
        return Response(_history_payload(rows))


def _history_payload(rows):
    return serializers.MedicalRecordEventSerializer(rows, many=True).data


@extend_schema(
    parameters=[
        OpenApiParameter(name="patient_uid", type=OpenApiTypes.STR, location=OpenApiParameter.PATH),
    ],
)
class PatientScopedMedicalRecordViewSet(MedicalRecordViewSet):
    """Nested alias of the chart: `/patients/{patient_uid}/medical-records/...`

    The approved endpoint matrix (§9) nests the chart under the patient, while the
    flatter `/medical-records/` resource is what the mobile client uses. Both are
    served by the same viewset so there is exactly one implementation of the
    read gate; this subclass only narrows the read set to the patient named in
    the URL.

    Narrowing happens inside `readable_patient_ids()`, which both
    `get_queryset()` and `get_record_or_404()` already consult, so a nested URL
    cannot become a way around the C2/C3 consent check.
    """

    def _nested_patient(self):
        uid = self.kwargs.get("patient_uid")
        from patients.models import Patient

        if str(uid).lower() in ("me", "self", "mine"):
            target = Patient.objects.filter(user=self.request.user).first()
            if target is None:
                raise NotFound("Patient not found.")
            return target

        target = Patient.objects.filter(user__uid=uid).first()
        # 404 (not 403) for an unknown or unreadable patient: the API must not
        # confirm that somebody else's chart exists.
        if target is None:
            raise NotFound("Patient not found.")
        return target

    def readable_patient_ids(self) -> set:
        allowed = super().readable_patient_ids()
        if "patient_uid" not in self.kwargs:
            return allowed
        return allowed & {self._nested_patient().pk}

    def create(self, request, *args, **kwargs):
        if "patient_uid" in self.kwargs:
            payload = dict(request.data or {})
            nested = self._nested_patient()
            payload["patient_uid"] = str(nested.user.uid)
            request._full_data = payload
        return super().create(request, *args, **kwargs)
