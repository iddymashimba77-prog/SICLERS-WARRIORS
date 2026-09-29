"""Caregiver relationship API views (AUTH-1; endpoint-matrix §7, role-perm §10).

Surface (mounted at ``/api/caregivers/``):
    GET         /api/caregivers/            caregivers.view (patient own / C3 grantee)
    POST        /api/caregivers/            caregivers.invite (PAT) — invite → PENDING
    GET/PATCH   /api/caregivers/{id}/permissions   caregivers.modify (PAT) — consent scope
    POST        /api/caregivers/{id}/accept/   invitee only → ACTIVE
    POST        /api/caregivers/{id}/decline/  invitee only
    DELETE      /api/caregivers/{id}/      caregivers.remove (PAT) — revoke + consent REVOKED
    GET         /api/caregivers/me/patient/   caregivers.view (C3 grantee, consent-gated)

Rules (C14, role-perm §10/§15):
* CAREGIVER role alone grants nothing. Data access requires BOTH an ACTIVE
  relationship AND an ACTIVE consent whose scope covers the read.
* Every invite/accept/decline/remove and every permission change is audited.
"""

from django.db.models import Q
from django.utils import timezone
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import Role, SecurityEvent, User
from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from medical_records import services as consent_services
from medical_records.models import Consent
from medical_records.serializers import ConsentSerializer
from medical_records.views import _resolve_user as _resolve_user_by_uid
from . import serializers
from .models import CaregiverRelationship, Patient


def _event(user, event_type, detail=None):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type, detail=dict(detail or {}))
    except Exception:
        pass


class CaregiverViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.CreateModelMixin,
    mixins.DestroyModelMixin,
    viewsets.GenericViewSet,
):
    lookup_field = "pk"
    serializer_class = serializers.CaregiverRelationshipSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("caregivers.view")]
    parser_classes = [JSONParser]

    def _is_patient_owner(self, relation) -> bool:
        return relation.patient.user_id == self.request.user.id

    def _owner_patient(self) -> Patient:
        if not self.request.user.is_patient:
            raise PermissionDenied("A PATIENT identity is required for this action.")
        patient, _ = Patient.objects.get_or_create(user=self.request.user)
        return patient

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return CaregiverRelationship.objects.none()
        qs = CaregiverRelationship.objects.select_related("patient__user", "user", "invited_by")
        if user.is_admin:
            return qs
        patient = Patient.objects.filter(user=user).first()
        mine = Q(patient=patient) if patient else Q(pk__in=[])
        return qs.filter(mine | Q(user=user))

    def get_object(self):
        relation = self.get_queryset().filter(pk=self.kwargs["pk"]).first()
        if relation is None:
            raise NotFound("Caregiver relationship not found.")
        return relation

    # --- create (invite) ----------------------------------------------------
    def create(self, request, *args, **kwargs):
        if not request.user.has_perm_code("caregivers.invite"):
            raise PermissionDenied("Only the patient can invite a caregiver.")
        serializer = serializers.CaregiverInviteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = self._owner_patient()
        caregiver = _resolve_user_by_uid(data["user_uid"])
        if caregiver.id == request.user.id:
            raise ValidationError({"user_uid": "You cannot invite yourself."})
        if caregiver.account_status != "ACTIVE":
            raise ValidationError({"user_uid": "The caregiver account is not active."})
        if not caregiver.is_caregiver:
            raise ValidationError({"user_uid": "The invited user has no CAREGIVER role."})
        if CaregiverRelationship.objects.filter(
            patient=patient, user=caregiver, status__in=("PENDING", "ACTIVE"),
        ).exists():
            raise ValidationError({"user_uid": "A caregiver link already exists for this user."})
        relation = CaregiverRelationship.objects.create(
            patient=patient, user=caregiver,
            relationship_type=data["relationship_type"], status="PENDING",
            invited_by=request.user,
        )
        record_audit(
            actor=request.user, action_code="caregivers.invite",
            resource_type="caregiver_relationship", resource_id=relation.pk, request=request,
            details={"caregiver": str(caregiver.uid), "relationship_type": relation.relationship_type},
        )
        _event(request.user, "CAREGIVER_INVITED", {"caregiver": str(caregiver.uid)})
        return Response(
            serializers.CaregiverRelationshipSerializer(relation).data,
            status=http_status.HTTP_201_CREATED,
        )

    # --- accept / decline (invitee only) ------------------------------------
    def _invitee_action(self, request, *, accept: bool):
        relation = self.get_object()
        if relation.user_id != request.user.id:
            raise PermissionDenied("Only the invited caregiver can respond to this invite.")
        if relation.status != "PENDING":
            raise ValidationError({"status": "This invitation is no longer pending."})
        if accept:
            if not request.user.is_caregiver:
                raise ValidationError({"status": "A CAREGIVER role is required to accept."})
            relation.status = "ACTIVE"
            relation.accepted_at = timezone.now()
            relation.save(update_fields=["status", "accepted_at", "updated_at"])
            record_audit(
                actor=request.user, action_code="caregivers.accept",
                resource_type="caregiver_relationship", resource_id=relation.pk,
                request=request,
            )
            _event(request.user, "CAREGIVER_ACCEPTED", {"patient": str(relation.patient.user.uid)})
        else:
            relation.status = "REVOKED"
            relation.save(update_fields=["status", "updated_at"])
            record_audit(
                actor=request.user, action_code="caregivers.decline",
                resource_type="caregiver_relationship", resource_id=relation.pk,
                request=request,
            )
            _event(request.user, "CAREGIVER_DECLINED", {"patient": str(relation.patient.user.uid)})
        return Response(serializers.CaregiverRelationshipSerializer(relation).data)

    @action(detail=True, methods=["post"], url_path="accept")
    def accept(self, request, pk=None):
        return self._invitee_action(request, accept=True)

    @action(detail=True, methods=["post"], url_path="decline")
    def decline(self, request, pk=None):
        return self._invitee_action(request, accept=False)

    # --- permissions (patient manages consent scope for the link) -----------
    @action(detail=True, methods=["get", "patch"], url_path="permissions")
    def permissions(self, request, pk=None):
        if not request.user.has_perm_code("caregivers.modify"):
            raise PermissionDenied("Only the patient can manage caregiver permissions.")
        relation = self.get_object()
        if not self._is_patient_owner(relation):
            raise PermissionDenied("Only the granting patient can manage these permissions.")
        consent_rows = Consent.objects.filter(
            patient_profile=relation.patient, granted_to=relation.user,
        ).order_by("-created_at")
        if request.method == "GET":
            return Response({
                "consents": ConsentSerializer(consent_rows, many=True).data,
            })
        if relation.status != "ACTIVE":
            raise ValidationError({"status": "The caregiver link must be active to set permissions."})
        serializer = serializers.CaregiverPermissionsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            active = consent_rows.filter(
                resource_type=data["resource_type"], status__in=("ACTIVE",),
            ).first()
            if active is not None:
                active.permission_scope = [str(c) for c in data["permission_scope"]]
                active.expires_at = data["expires_at"]
                active.save(update_fields=["permission_scope", "expires_at", "updated_at"])
                row = active
            else:
                row = consent_services.grant(
                    patient=relation.patient,
                    granted_to=relation.user,
                    permission_scope=data["permission_scope"],
                    resource_type=data["resource_type"],
                    purpose="Caregiver profile-link scope",
                    expires_at=data["expires_at"],
                    authorized_role=Role.objects.filter(code="CAREGIVER").first(),
                )
        except ValueError as exc:
            raise ValidationError({"expires_at": str(exc)})
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=row.pk, request=request,
            details={"action": "caregiver_scope", "resource_type": row.resource_type},
        )
        _event(request.user, "CONSENT_GRANTED", {"caregiver": str(relation.user.uid)})
        return Response(ConsentSerializer(row).data)

    # --- remove (patient revokes) -------------------------------------------
    def destroy(self, request, *args, **kwargs):
        if not request.user.has_perm_code("caregivers.remove"):
            raise PermissionDenied("Only the patient can remove a caregiver.")
        relation = self.get_object()
        if not self._is_patient_owner(relation):
            raise PermissionDenied("Only the granting patient can remove this caregiver.")
        reason = (request.data or {}).get("reason", "")
        relation.status = "REVOKED"
        relation.save(update_fields=["status", "updated_at"])
        revoked = 0
        for consent in Consent.objects.filter(
            patient_profile=relation.patient, granted_to=relation.user, status__in=("ACTIVE", "DRAFT"),
        ):
            consent_services.revoke(consent, actor=request.user)
            revoked += 1
        record_audit(
            actor=request.user, action_code="caregivers.remove",
            resource_type="caregiver_relationship", resource_id=relation.pk, request=request,
            details={"reason": str(reason)[:500], "consents_revoked": revoked},
        )
        _event(request.user, "CAREGIVER_REVOKED", {"caregiver": str(relation.user.uid)})
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    # --- caregiver: consent-gated profile basics (C14, C3) -------------------
    @action(detail=False, methods=["get"], url_path="me/patient")
    def patient(self, request):
        user = request.user
        if not user.is_caregiver:
            raise PermissionDenied("A CAREGIVER identity is required.")
        relation = CaregiverRelationship.objects.filter(
            user=user, status="ACTIVE",
        ).select_related("patient__user").order_by("-accepted_at").first()
        if relation is None:
            raise NotFound("You have no active caregiver link to a patient.")
        patient = relation.patient
        if not consent_services.can_access(patient, user, "patients.view"):
            raise PermissionDenied(
                "No active consent grants you access to this patient's profile."
            )
        record_audit(
            actor=user, action_code="consents.view",
            resource_type="patient", resource_id=patient.pk, request=request,
            details={"grantee": str(user.uid), "scope": "patients.view"},
        )
        return Response(serializers.CaregiverPatientBasicsSerializer({
            "patient_uid": patient.user.uid,
            "first_name": patient.user.first_name,
            "last_name": patient.user.last_name,
            "relationship_type": relation.relationship_type,
        }).data)