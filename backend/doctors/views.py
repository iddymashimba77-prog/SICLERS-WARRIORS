"""Chat + professional-registry API views (Stage 4.10 + AUTH-1).

Chat (approved endpoint-matrix §17):

    GET         /api/chat/conversations/                    member list
    POST        /api/chat/conversations/                    chat.start (+C13b)
    GET         /api/chat/conversations/{uid}/              member retrieve
    GET/POST    /api/chat/conversations/{uid}/messages/     member / chat.send
    DELETE      /api/chat/conversations/{uid}/messages/{mid}/  sender tombstone
    POST        /api/chat/conversations/{uid}/read/         member
    POST        /api/chat/conversations/{uid}/leave/        member
    POST        /api/chat/conversations/{uid}/add-participant/  creator (PEER/GROUP)
    GET         /api/chat/recipients/                role-aware recipient picker

Doctor professional registry (AUTH-1, endpoint-matrix §5):

    GET/PATCH   /api/doctors/me/                    doctors.self_manage (C5)
    POST        /api/doctors/me/verification/       doctors.self_manage (FR-DOC-002)
    GET         /api/doctors/                       doctors.view (verified only)
    GET         /api/doctors/{uid}/                 doctors.view (verified only)
    GET         /api/admin/doctors/verification-queue/   doctors.verify
    POST        /api/admin/doctors/{uid}/verify/    doctors.verify (approve/reject, reason on reject)
    POST        /api/admin/doctors/{uid}/suspend/   doctors.verify (reason required)

Every conversation surface is membership-scoped (C13): a non-participant gets
404, never a 403 that would confirm the conversation exists. Verification
gates clinical functions via ``User.is_verified_doctor`` (BR-001) — a DOCTOR
account starts PENDING and is unusable in clinical flows until APPROVED.
"""

from django.db import IntegrityError, transaction
from django.db.models import Count, Q
from django.utils import timezone
from drf_spectacular.utils import (
    OpenApiParameter,
    OpenApiTypes,
    extend_schema,
)
from rest_framework import status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.generics import GenericAPIView, ListAPIView, RetrieveUpdateAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import (
    PROFESSIONAL_ROLE_CODES,
    SecurityEvent,
    User,
    VerificationDocument,
)
from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from facilities.models import Facility
from . import models, serializers, services
from .permissions import ChatAccess
from .throttles import ChatCreateThrottle, ChatMessageThrottle


@extend_schema(
    parameters=[
        OpenApiParameter(name="uid", type=OpenApiTypes.STR, location=OpenApiParameter.PATH),
    ],
)
class ConversationViewSet(viewsets.GenericViewSet):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.ConversationSerializer
    permission_classes = [ChatAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action == "create":
            return [ChatCreateThrottle()]
        if action == "messages" and self.request.method == "POST":
            return [ChatMessageThrottle()]
        return []

    def get_queryset(self):
        user = self.request.user
        qs = (
            models.Conversation.objects.select_related("created_by")
            .prefetch_related("participants__user")
            .filter(participants__user=user, participants__status="ACTIVE")
            .distinct()
        )
        return qs.annotate(
            unread_count=Count(
                "messages",
                filter=Q(messages__deleted_at__isnull=True)
                & ~Q(messages__sender=user)
                & ~Q(messages__status="READ"),
            )
        )

    def get_object(self):
        obj = self.get_queryset().filter(**{self.lookup_field: self.kwargs[self.lookup_url_kwarg]}).first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        qs = self.get_queryset().order_by("-last_message_at", "-created_at")
        page = self.paginate_queryset(qs)
        serializer = serializers.ConversationSerializer(page, many=True, context={"request": request})
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        instance = self.get_object()
        return Response(serializers.ConversationSerializer(instance, context={"request": request}).data)

    def _partner_error(self, creator, partner):
        if creator.is_patient:
            # C13b: a patient may open a care conversation with any *verified*
            # professional — doctor, psychologist or social support worker. A
            # pending, rejected or suspended applicant is not a professional yet,
            # which is why this checks the registry and not the role.
            if not partner.is_verified_professional:
                return "You may only start a chat with a verified professional."
        elif creator._has_active_role(*PROFESSIONAL_ROLE_CODES, "HEALTHCARE_STAFF"):
            if not partner.is_patient:
                return "A professional-patient conversation must include a patient."
            if not creator.is_verified_professional and creator._has_active_role(
                *PROFESSIONAL_ROLE_CODES
            ):
                return "Your professional verification must be approved first."
        else:
            return "You may not start a conversation."
        return None

    @transaction.atomic
    def create(self, request):
        user = request.user
        serializer = serializers.ConversationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        partner_uid = serializer.validated_data["participant_uid"]
        partner = User.objects.filter(uid=partner_uid, deleted_at__isnull=True).first()
        if partner is None:
            raise ValidationError({"participant_uid": "Participant not found."})
        if partner.pk == user.pk:
            raise ValidationError({"participant_uid": "You cannot start a conversation with yourself."})
        error = self._partner_error(user, partner)
        if error:
            raise PermissionDenied(error)
        conversation = services.create_conversation(
            creator=user, partner=partner, type_=serializer.validated_data["type"],
        )
        record_audit(
            actor=user, action_code="conversations.create",
            resource_type="conversation", resource_id=conversation.pk, request=request,
            details={"type": conversation.type},
        )
        conversation = self.get_queryset().get(pk=conversation.pk)
        return Response(
            serializers.ConversationSerializer(conversation, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["get", "post"], url_path="messages")
    def messages(self, request, uid=None):
        conversation = self.get_object()
        if request.method == "GET":
            qs = conversation.messages.select_related("sender").order_by("created_at")
            page = self.paginate_queryset(qs)
            serializer = serializers.MessageSerializer(page, many=True, context={"request": request})
            return self.get_paginated_response(serializer.data)
        if not request.user.has_perm_code("chat.send"):
            raise PermissionDenied("You do not have permission to send messages.")
        serializer = serializers.MessageCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        message = services.send_message(
            conversation=conversation, sender=request.user,
            content=serializer.validated_data["content"],
            message_type=serializer.validated_data["message_type"],
        )
        record_audit(
            actor=request.user, action_code="messages.send",
            resource_type="message", resource_id=message.pk, request=request,
            details={"conversation": conversation.pk},
        )
        return Response(
            serializers.MessageSerializer(message, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"], url_path="read")
    def read(self, request, uid=None):
        conversation = self.get_object()
        updated = services.mark_read(conversation=conversation, reader=request.user)
        return Response({"updated": updated})

    @action(detail=True, methods=["post"], url_path="leave")
    def leave(self, request, uid=None):
        conversation = self.get_object()
        services.leave_conversation(conversation=conversation, user=request.user)
        record_audit(
            actor=request.user, action_code="conversations.leave",
            resource_type="conversation", resource_id=conversation.pk, request=request,
        )
        return Response({"status": "LEFT"})

    @action(detail=True, methods=["post"], url_path="add-participant")
    def add_participant(self, request, uid=None):
        conversation = self.get_object()
        if conversation.created_by_id != request.user.id:
            raise PermissionDenied("Only the conversation creator can add participants.")
        if conversation.type == "DOCTOR_PATIENT":
            raise ValidationError({"type": "Participants cannot be added to a private doctor conversation."})
        serializer = serializers.AddParticipantSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        target = User.objects.filter(
            uid=serializer.validated_data["user_uid"], deleted_at__isnull=True,
        ).first()
        if target is None:
            raise ValidationError({"user_uid": "User not found."})
        services.add_participant(
            conversation=conversation, user=target, invited_by=request.user,
            role_in_chat=serializer.validated_data.get("role_in_chat", "MEMBER"),
        )
        record_audit(
            actor=request.user, action_code="conversations.add_participant",
            resource_type="conversation", resource_id=conversation.pk, request=request,
            details={"invited": str(target.uid)},
        )
        conversation = self.get_queryset().get(pk=conversation.pk)
        return Response(serializers.ConversationSerializer(conversation, context={"request": request}).data)


@extend_schema(responses={204: None})
class MessageDeleteView(GenericAPIView):
    """DELETE /chat/conversations/{uid}/messages/{mid}/ — sender-only tombstone."""

    permission_classes = [IsAuthenticatedRespectStatus, require("chat.send")]
    parser_classes = [JSONParser]

    def get_object(self):
        message = models.Message.objects.select_related("conversation").filter(
            uid=self.kwargs["uid"], conversation__uid=self.kwargs["conv_uid"],
        ).first()
        if message is None:
            raise NotFound("Not found.")
        is_member = message.conversation.participants.filter(
            user=self.request.user, status="ACTIVE",
        ).exists()
        if not is_member:
            raise NotFound("Not found.")
        return message

    @transaction.atomic
    def delete(self, request, conv_uid=None, uid=None):
        message = self.get_object()
        if message.sender_id != request.user.id:
            raise PermissionDenied("You can only delete your own messages.")
        services.delete_message(message)
        record_audit(
            actor=request.user, action_code="messages.delete",
            resource_type="message", resource_id=message.pk, request=request,
            details={"conversation": message.conversation_id},
        )
        return Response(status=http_status.HTTP_204_NO_CONTENT)


class ChatRecipientListView(APIView):
    """GET ``/api/chat/recipients/`` — role-aware recipient picker (FR-CHAT).

    Replaces the manual "type a verified professional UID" flow: the client
    offers this searchable identity list instead of asking people to paste
    identifiers. The rows mirror ``ConversationViewSet._partner_error`` exactly,
    so a picker entry can never be someone ``POST /chat/conversations/`` would
    refuse:

    * patient creator  → approved, active professionals (registry public subset)
    * professional / healthcare-staff creator → registered patients
      (identity rows only — no medical payload)
    * anyone else (caregiver, donor, …) → 403, the same denial ``create`` gives

    Verification for clinical features is NOT removed anywhere — a patient's
    list only ever contains APPROVED professionals (the server-side C13b rule
    stays in force), and the picker just makes that rule invisible to honest
    users. ``?q=`` narrows by name (and specialty for professionals).
    """

    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]

    _LIMIT = 50

    def get(self, request):
        user = request.user
        if not user.has_perm_code("chat.start"):
            raise PermissionDenied(
                "You do not have permission to start conversations."
            )
        query = (request.query_params.get("q") or "").strip()
        if user.is_patient:
            return Response({"results": self._professionals(query)})
        if user._has_active_role(*PROFESSIONAL_ROLE_CODES, "HEALTHCARE_STAFF"):
            # Same creator gate ``create`` applies to professionals (mirrors
            # _partner_error): an unapproved professional cannot start a chat,
            # so the picker refuses them with the very same message.
            if user._has_active_role(*PROFESSIONAL_ROLE_CODES) and not user.is_verified_professional:
                raise PermissionDenied(
                    "Your professional verification must be approved first."
                )
            return Response({"results": self._patients(query)})
        raise PermissionDenied("You may not start a conversation.")

    def _professionals(self, query):
        # Mirrors `is_verified_professional` + the registry's own directory
        # filters: APPROVED row, active registry entry, ACTIVE account, live
        # professional role, not soft-deleted — so every listed row is one
        # `POST /chat/conversations/` would accept as a partner.
        qs = (
            models.Doctor.objects.filter(
                verification_status="APPROVED",
                is_active=True,
                user__account_status="ACTIVE",
                user__deleted_at__isnull=True,
                user__user_roles__role__code__in=PROFESSIONAL_ROLE_CODES,
                user__user_roles__is_active=True,
            )
            .distinct()
            .select_related("user", "facility")
        )
        if query:
            qs = qs.filter(
                Q(user__first_name__icontains=query)
                | Q(user__last_name__icontains=query)
                | Q(specialty__icontains=query)
            )
        rows = []
        for doctor in qs.order_by("user__first_name", "user__last_name")[: self._LIMIT]:
            detail = doctor.specialty or ""
            if doctor.facility_id:
                facility = f"{doctor.facility.name}"
                detail = f"{detail} · {facility}" if detail else facility
            rows.append({
                "uid": str(doctor.user.uid),
                "display_name": serializers.display_name(doctor.user),
                "role": doctor.professional_type,
                "detail": detail,
            })
        return rows

    def _patients(self, query):
        qs = User.objects.filter(
            user_roles__role__code="PATIENT",
            user_roles__is_active=True,
            account_status="ACTIVE",
            deleted_at__isnull=True,
        ).distinct()
        if query:
            qs = qs.filter(
                Q(first_name__icontains=query)
                | Q(last_name__icontains=query)
                | Q(email__icontains=query)
            )
        rows = []
        for patient in qs.order_by("first_name", "last_name")[: self._LIMIT]:
            rows.append({
                "uid": str(patient.uid),
                "display_name": serializers.display_name(patient),
                "role": "PATIENT",
                "detail": "",
            })
        return rows


# ---------------------------------------------------------------------------
# Doctor professional registry (AUTH-1, database-design §3.4)
# ---------------------------------------------------------------------------


def _audit_event(user, event_type):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type)
    except Exception:
        pass


def _doctor_for_user(user) -> models.Doctor | None:
    try:
        return user.doctor_profile
    except models.Doctor.DoesNotExist:
        return None


def _resolve_doctor_or_404(uid):
    doctor = models.Doctor.objects.select_related("user", "facility").filter(user__uid=uid).first()
    if doctor is None:
        raise NotFound("Doctor not found.")
    return doctor


class DoctorMeView(RetrieveUpdateAPIView):
    """GET/PATCH /doctors/me — DOCTOR's own professional profile (C5).

    The row is 1:1 with the identity; creating the profile does NOT approve it —
    it starts PENDING (BR-001) until a VO/ADM/SUP decides.
    """

    serializer_class = serializers.DoctorSelfSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.self_manage")]
    parser_classes = [JSONParser]

    def get_object(self):
        user = self.request.user
        if not user._has_active_role("DOCTOR"):
            raise PermissionDenied("A DOCTOR identity is required for a professional profile.")
        doctor, _ = models.Doctor.objects.get_or_create(user=user)
        return doctor

    def perform_update(self, serializer):
        doctor = serializer.save()
        record_audit(
            actor=self.request.user, action_code="doctors.self_manage",
            resource_type="doctor", resource_id=doctor.pk, request=self.request,
            details={"verification_status": doctor.verification_status},
        )
        _audit_event(self.request.user, "PROFILE_UPDATED")


@extend_schema(
    request=serializers.DoctorVerificationSubmitSerializer,
    responses=serializers.DoctorSelfSerializer,
)
class DoctorVerificationSubmitView(GenericAPIView):
    """POST /doctors/me/verification — submit/update documents (FR-DOC-002).

    Resets a REJECTED application back into the PENDING review queue (a resubmit
    is a new decision). Approved or suspended doctors cannot self-resubmit.
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.self_manage")]
    parser_classes = [JSONParser]

    def post(self, request):
        user = request.user
        if not user._has_active_role(*PROFESSIONAL_ROLE_CODES):
            raise PermissionDenied("A professional identity is required.")
        doctor, _ = models.Doctor.objects.get_or_create(user=user)
        if doctor.verification_status in ("APPROVED", "SUSPENDED"):
            raise ValidationError(
                {"status": "Your verification cannot be resubmitted in its current state."}
            )
        serializer = serializers.DoctorVerificationSubmitSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        # Mandatory-document enforcement (C5): a professional applicant must
        # attach at least a government-verified education/professional
        # certificate and a National ID scan before the queue will review them.
        submitted_doc_types = {
            str(d.get("doc_type", "")).upper() for d in data.get("documents", [])
        }
        if not submitted_doc_types:
            raise ValidationError(
                {"documents": "Please attach your verification documents before submitting."}
            )
        if "NATIONAL_ID" not in submitted_doc_types:
            raise ValidationError(
                {"documents": "A National ID (NIDA) scan is required for verification."}
            )
        if not submitted_doc_types.intersection({"LICENSE", "CERTIFICATE"}):
            raise ValidationError(
                {"documents": "A government-verified education certificate or professional license is required."}
            )
        # The claimed type must match the account role that actually holds this
        # profile, otherwise a DOCTOR could submit as a psychologist and inherit
        # nothing, or (worse) the queue would file them under the wrong
        # profession. The account role stays the source of privileges.
        claimed_type = data.get("professional_type") or "DOCTOR"
        expected_type = next(
            (code for code in ("PSYCHOLOGIST", "SOCIAL_SUPPORT") if user._has_active_role(code)),
            "DOCTOR",
        )
        if claimed_type != expected_type:
            raise ValidationError({
                "professional_type": (
                    f"Your account is registered as {expected_type}; it cannot submit "
                    f"a {claimed_type} verification."
                )
            })
        doctor.professional_type = expected_type
        if data.get("license_number"):
            doctor.license_number = data["license_number"]
        if data.get("specialty"):
            doctor.specialty = data["specialty"]
        if data.get("registration_body"):
            doctor.registration_body = data["registration_body"]
        if data.get("facility_uid") is not None:
            facility = Facility.objects.filter(uid=data["facility_uid"]).first()
            if facility is None:
                raise ValidationError({"facility_uid": "Facility not found."})
            doctor.facility = facility
        previous_status = doctor.verification_status
        doctor.verification_status = "PENDING"
        doctor.rejection_reason = ""
        doctor.verified_by = None
        doctor.verified_at = None
        doctor.verification_expires_at = None
        doctor.save()

        # A resubmit is a new decision, not an edit of the old one: the earlier
        # rejection stays in the history with its reason.
        services.record_decision(
            doctor,
            decision="RESUBMITTED" if previous_status == "REJECTED" else "SUBMITTED",
            actor=user,
            from_status=previous_status, to_status="PENDING",
        )

        created_docs = []
        allowed_doc_types = {code for code, _ in VerificationDocument.DOC_TYPE}
        for doc in data.get("documents", []):
            doc_type = str(doc.get("doc_type", "")).upper()
            if doc_type not in allowed_doc_types:
                raise ValidationError(
                    {"documents": f"Unsupported document type: {doc_type or 'missing'}."}
                )
            if not doc.get("file_url"):
                raise ValidationError({"documents": "Each document needs a storage key."})
            created_docs.append(
                VerificationDocument.objects.create(
                    user=user, doc_type=doc_type, file_url=doc["file_url"], status="PENDING",
                )
            )
        record_audit(
            actor=user, action_code="doctors.verification_submit",
            resource_type="doctor", resource_id=doctor.pk, request=request,
            details={
                "verification_status": "PENDING",
                "documents": [d.doc_type for d in created_docs],
            },
        )
        _audit_event(user, "DOCTOR_VERIFICATION_SUBMITTED")
        return Response(
            serializers.DoctorSelfSerializer(doctor).data, status=http_status.HTTP_200_OK,
        )


class DoctorDirectoryListView(ListAPIView):
    """GET /doctors — public-subset registry (verified, active only).

    `?professional_type=PSYCHOLOGIST` narrows to one profession. Without it the
    list is every verified professional, which is the honest default now that the
    registry holds more than one kind: a patient looking for psychological
    support and a patient looking for a haematologist are both served by the same
    route, and each filters.
    """

    serializer_class = serializers.DoctorPublicSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.view")]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        queryset = models.Doctor.objects.filter(
            verification_status="APPROVED", is_active=True,
        ).select_related("user", "facility")
        professional_type = (self.request.query_params.get("professional_type") or "").strip().upper()
        if professional_type:
            if professional_type not in models.Doctor.PROFESSIONAL_TYPE_CODES:
                raise ValidationError({"professional_type": "Unknown professional type."})
            queryset = queryset.filter(professional_type=professional_type)
        return queryset


@extend_schema(responses=serializers.DoctorPublicSerializer)
class DoctorDirectoryDetailView(GenericAPIView):
    """GET /doctors/{uid} — public-subset detail (doctor's user uid)."""

    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.view")]

    def get(self, request, uid=None):
        doctor = models.Doctor.objects.filter(
            user__uid=uid, verification_status="APPROVED", is_active=True,
        ).select_related("user", "facility").first()
        if doctor is None:
            raise NotFound("Doctor not found.")
        return Response(serializers.DoctorPublicSerializer(doctor).data)


class AdminDoctorVerificationQueueView(ListAPIView):
    """GET /admin/doctors/verification-queue — PENDING applications (FR-DOC-003)."""

    serializer_class = serializers.DoctorAdminSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.verify")]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        queryset = models.Doctor.objects.filter(
            verification_status="PENDING",
        ).select_related("user", "facility")
        professional_type = (
            self.request.query_params.get("professional_type") or ""
        ).strip().upper()
        if professional_type:
            if professional_type not in models.Doctor.PROFESSIONAL_TYPE_CODES:
                raise ValidationError({"professional_type": "Unknown professional type."})
            queryset = queryset.filter(professional_type=professional_type)
        return queryset


@extend_schema(
    request=serializers.DoctorVerifySerializer,
    responses=serializers.DoctorAdminSerializer,
)
class AdminDoctorVerifyView(GenericAPIView):
    """POST /admin/doctors/{uid}/verify — approve or reject (VO/ADM/SUP, C6).

    One endpoint handles both outcomes (unified design): rejection requires a
    reason. Every decision is audited (FR-DOC-004).
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.verify")]
    parser_classes = [JSONParser]

    def post(self, request, uid=None):
        doctor = _resolve_doctor_or_404(uid)
        serializer = serializers.DoctorVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        approve = serializer.validated_data["approve"]
        reason = serializer.validated_data.get("reason", "").strip()
        if not approve and not reason:
            raise ValidationError({"reason": "A rejection reason is required."})
        if doctor.verification_status not in ("PENDING", "REJECTED"):
            raise ValidationError(
                {"status": "Only pending (or rejected) applications can be decided."}
            )
        previous_status = doctor.verification_status
        doctor.verification_status = "APPROVED" if approve else "REJECTED"
        doctor.verified_by = request.user
        doctor.verified_at = timezone.now()
        doctor.rejection_reason = "" if approve else reason
        doctor.save(update_fields=[
            "verification_status", "verified_by", "verified_at",
            "rejection_reason", "updated_at",
        ])
        services.record_decision(
            doctor,
            decision="APPROVED" if approve else "REJECTED",
            actor=request.user,
            from_status=previous_status,
            to_status=doctor.verification_status,
            reason=reason[:2000],
        )
        record_audit(
            actor=request.user, action_code="doctors.verify",
            resource_type="doctor", resource_id=doctor.pk, request=request,
            details={"approve": approve, "reason": reason[:500]},
        )
        _audit_event(request.user, "DOCTOR_VERIFIED" if approve else "DOCTOR_REJECTED")
        return Response(
            serializers.DoctorAdminSerializer(doctor).data, status=http_status.HTTP_200_OK,
        )


@extend_schema(
    request=serializers.DoctorSuspendSerializer,
    responses=serializers.DoctorAdminSerializer,
)
class AdminDoctorSuspendView(GenericAPIView):
    """POST /admin/doctors/{uid}/suspend — reason required, audited (FR-DOC-004)."""

    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.verify")]
    parser_classes = [JSONParser]

    def post(self, request, uid=None):
        doctor = _resolve_doctor_or_404(uid)
        serializer = serializers.DoctorSuspendSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data["reason"].strip()
        if not reason:
            raise ValidationError({"reason": "A suspension reason is required."})
        if doctor.verification_status == "SUSPENDED":
            raise ValidationError({"status": "This doctor is already suspended."})
        previous_status = doctor.verification_status
        doctor.verification_status = "SUSPENDED"
        doctor.rejection_reason = reason
        doctor.verified_by = request.user
        doctor.save(update_fields=[
            "verification_status", "rejection_reason", "verified_by", "updated_at",
        ])
        services.record_decision(
            doctor, decision="SUSPENDED", actor=request.user,
            from_status=previous_status, to_status="SUSPENDED", reason=reason[:2000],
        )
        record_audit(
            actor=request.user, action_code="doctors.verify",
            resource_type="doctor", resource_id=doctor.pk, request=request,
            details={"action": "suspend", "reason": reason[:500]},
        )
        _audit_event(request.user, "DOCTOR_SUSPENDED")
        return Response(
            serializers.DoctorAdminSerializer(doctor).data, status=http_status.HTTP_200_OK,
        )


@extend_schema(
    request=serializers.DoctorSuspendSerializer,
    responses=serializers.DoctorAdminSerializer,
)
class AdminDoctorReinstateView(GenericAPIView):
    """POST /admin/doctors/{uid}/reinstate — reason required, audited.

    Suspension is not a terminal state: without this, a licence that was
    suspended in error could only be cleared by editing the row by hand, which
    would leave the history claiming the doctor was still suspended. The
    reinstatement is appended as its own decision rather than rewriting the
    suspension, so the trail shows the suspension *and* its reversal.
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.verify")]
    parser_classes = [JSONParser]

    def post(self, request, uid=None):
        doctor = _resolve_doctor_or_404(uid)
        serializer = serializers.DoctorSuspendSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data["reason"].strip()
        if not reason:
            raise ValidationError({"reason": "A reinstatement reason is required."})
        if doctor.verification_status != "SUSPENDED":
            raise ValidationError({"status": "Only a suspended doctor can be reinstated."})
        previous_status = doctor.verification_status
        doctor.verification_status = "APPROVED"
        doctor.rejection_reason = ""
        doctor.verified_by = request.user
        doctor.verified_at = timezone.now()
        doctor.save(update_fields=[
            "verification_status", "rejection_reason", "verified_by",
            "verified_at", "updated_at",
        ])
        services.record_decision(
            doctor, decision="REINSTATED", actor=request.user,
            from_status=previous_status, to_status="APPROVED", reason=reason[:2000],
        )
        record_audit(
            actor=request.user, action_code="doctors.verify",
            resource_type="doctor", resource_id=doctor.pk, request=request,
            details={"action": "reinstate", "reason": reason[:500]},
        )
        _audit_event(request.user, "DOCTOR_REINSTATED")
        return Response(
            serializers.DoctorAdminSerializer(doctor).data, status=http_status.HTTP_200_OK,
        )


@extend_schema(responses=OpenApiTypes.OBJECT)
class DoctorVerificationHistoryView(GenericAPIView):
    """GET /doctors/{uid}/verification-history — the append-only trail (FR-DOC-007).

    Two audiences, one route:

    * the doctor themselves may read their own trail at any time — "why was I
      rejected?" has to be answerable to the person who was rejected;
    * a VO/ADM/SUP with ``doctors.verify`` may read any doctor's trail as part of
      the C6 workflow.

    Everyone else gets a 404 rather than a 403, so the endpoint never confirms
    that a particular licence application exists.
    """

    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]

    def get(self, request, uid=None):
        doctor = _resolve_doctor_or_404(uid)
        user = request.user
        is_self = doctor.user_id == user.id
        is_reviewer = user.has_perm_code("doctors.verify")
        if not (is_self or is_reviewer):
            raise NotFound("Verification history not found.")
        rows = doctor.verification_decisions.select_related("actor").order_by(
            "-decided_at", "-pk",
        )
        data = serializers.DoctorVerificationDecisionSerializer(rows, many=True).data
        return Response({
            "doctor_uid": str(doctor.user.uid),
            "verification_status": doctor.verification_status,
            "count": len(data),
            "decisions": data,
        })


@extend_schema(responses=serializers.DoctorVerificationDecisionSerializer(many=True))
class AdminDoctorVerificationHistoryView(GenericAPIView):
    """GET /admin/doctors/verification-history — the review queue's trail.

    The queue view that pairs with `AdminDoctorVerifyView`: an officer can see
    every decision already made across the registry before deciding the next
    one, which is what C6's "reason + audit" requirement is for in practice.
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("doctors.verify")]
    parser_classes = [JSONParser]

    def get(self, request):
        decision = (request.query_params.get("decision") or "").strip().upper()
        queryset = models.DoctorVerificationDecision.objects.select_related(
            "actor", "doctor",
        )
        if decision:
            if decision not in models.DoctorVerificationDecision.DECISIONS:
                raise ValidationError({"decision": "Unknown decision filter."})
            queryset = queryset.filter(decision=decision)
        rows = queryset.order_by("-decided_at", "-pk")[:200]
        return Response(
            serializers.DoctorVerificationDecisionSerializer(rows, many=True).data,
        )
