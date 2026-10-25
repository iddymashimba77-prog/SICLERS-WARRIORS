"""AI application service — the approved pipeline (special-systems §3.9.5).

    authenticate  →  authorize (ai.use, §3.21)  →  consent/privacy (own data
    only, minimum necessary)  →  safety validation (input)  →  provider
    (rule-based sandbox; interface for a governed future LLM)  →  medical
    safety validation (output)  →  response + disclaimer (FR-AI-006)

External contract (API design placeholder AD-2):

    POST /api/ai/chat/            — FR-AI-001/002 conjunction
    GET  /api/ai/trends/{uid}/    — FR-AI-004

Honesty invariants implemented here:
* The assistant NEVER stores the message or the generated text — no transcript,
  no content retention (any row that might tempt it is avoided). Only audit
  metadata is persisted (audit_logs), per traceability TC-AI-003.
* No new database tables: the approved database-design has no ``ai_*`` entity,
  so AI activity goes through the existing audit system only.
* Emergency intent short-circuits to professional-care referral and is NEVER
  acted on (no auto-creating SOS requests, no diagnosis) — BR-010/011.
* ``symptom_assistance`` returns a structured draft but never writes Symptom
  records (§26: the assistant does not modify medical records).
* ``insight_explanation`` explains the deterministic metric only; the number
  always comes from medications.services.adherence_stats.
"""

import logging
import uuid

from django.conf import settings
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied

from audit.services import record_audit
from medications.services import adherence_stats

from . import knowledge, providers, safety

logger = logging.getLogger(__name__)

EMERGENCY_CATEGORY = "emergency"
REFUSED_CATEGORY = "refused"


class AiAssistantService:
    """Stateless orchestration (one use per request; no instance data)."""

    # ------------------------------------------------------------------
    # Public surface
    # ------------------------------------------------------------------

    def handle_chat(self, user, data, request):
        """Run the full pipeline for one chat turn.

        Returns a response dict; raises ``ProviderUnavailable`` (→ 503, audited)
        only when no configured provider can answer.
        """
        request_id = uuid.uuid4().hex
        message = (data.get("message") or "").strip()
        use_case = data.get("use_case") or "education"
        personalized_requested = bool(data.get("personalized", True))
        metric = data.get("metric")

        record_audit(
            actor=user, action_code="ai.request",
            resource_type="ai.assistant", resource_id=None,
            result="SUCCESS", request=request,
            details={
                "request_id": request_id,
                "use_case": use_case,
                "message_chars": len(message),
                "personalized_requested": personalized_requested,
            },
        )

        # -- privacy / minimum necessary -------------------------------
        # Personalization requires (a) a use case that needs data and (b) the
        # caller being the data owner. We never bind context to any non-owner.
        can_personalize = (
            personalized_requested
            and use_case in providers.PERSONALIZED_USE_CASES
            and user.is_verified_patient
        )
        ctx = context_build(user, use_case, personalized=can_personalize)
        if ctx["categories"]:
            record_audit(
                actor=user, action_code="ai.context_access",
                resource_type="ai.assistant", resource_id=None,
                result="SUCCESS", request=request,
                details={"request_id": request_id, "categories": ctx["categories"]},
            )

        # -- safety validation (input) -----------------------------------
        emergency = safety.scan_emergency(message)
        if emergency:
            return self._finish(
                user, request, request_id,
                message=safety.EMERGENCY_RESPONSE,
                sources=[], metrics=None, personalized=can_personalize,
                context_categories=ctx["categories"],
                emergency_action=True, emergency_categories=emergency,
                safety_blocked=True, safety_reason="emergency",
                model_id=providers.RuleBasedProvider.model_id,
                use_case=use_case,
                limitation=ctx["limitation"],
            )

        safe, refusal_key = safety.input_guard(message)
        if not safe:
            text = safety.REFUSAL_TEMPLATES[refusal_key]
            return self._finish(
                user, request, request_id,
                message=text, sources=[], metrics=None, personalized=can_personalize,
                context_categories=ctx["categories"],
                emergency_action=False, emergency_categories=[],
                safety_blocked=True, safety_reason=refusal_key,
                model_id=providers.RuleBasedProvider.model_id,
                use_case=use_case, limitation=ctx["limitation"],
            )
        
        # -- topic restriction (sickle cell + app only) -------------------
        # Free-form Q&A is scoped to sickle cell / health. Personal-data use
        # cases (health_summary, symptom_assistance, insight_explanation,
        # appointment_preparation) are app features and stay in scope by design.
        if use_case in ("education", "health_questions", "medication_education"):
            topic_ok, topic_reason = safety.is_topic_allowed(message)
            if not topic_ok:
                return self._finish(
                    user, request, request_id,
                    message=safety.OFF_TOPIC_REFUSAL,
                    sources=[], metrics=None, personalized=can_personalize,
                    context_categories=ctx["categories"],
                    emergency_action=False, emergency_categories=[],
                    safety_blocked=True, safety_reason="off_topic",
                    model_id=getattr(settings, "AI_PROVIDER", "rule_based"),
                    use_case=use_case, limitation=ctx["limitation"],
                )

        # -- approved-knowledge grounding (FR-AI-001) ---------------------
        sources = []
        if use_case in ("education", "health_questions", "medication_education"):
            sources = knowledge.search_approved_knowledge(message)

        # -- deterministic metric for insight_explanation -----------------
        metrics = None
        if use_case == "insight_explanation":
            metrics = self._adherence_metrics(user, metric, ctx)

        # -- provider ------------------------------------------------------
        history = None
        if request is not None:
            try:
                # Try to get history from request data or session
                history = request.data.get('history') or request.data.get('messages') or getattr(request, 'ai_history', None)
            except Exception:
                history = None
        payload = providers.ChatPayload(
            request_id=request_id,
            use_case=use_case,
            message=message,
            context=ctx,
            sources=sources,
            metrics=metrics,
            personalized=can_personalize,
            history=history,
        )
        try:
            result = providers.get_ai_provider().generate(payload)
        except providers.ProviderUnavailable as exc:
            record_audit(
                actor=user, action_code="ai.provider_failure",
                resource_type="ai.assistant", resource_id=None,
                result="FAILURE", request=request,
                details={
                    "request_id": request_id, "use_case": use_case,
                    # Operator-facing code (missing_api_key, upstream_http_403…);
                    # never sent to the client.
                    "reason": getattr(exc, "reason", "") or "unknown",
                },
            )
            raise

        # -- medical safety validation (output) ----------------------------
        safe_out, out_reason = safety.validate_output(result.text)
        safety_blocked = not safe_out
        safety_reason = out_reason if not safe_out else None
        if safety_blocked:
            record_audit(
                actor=user, action_code="ai.safety_block",
                resource_type="ai.assistant", resource_id=None,
                result="FAILURE", request=request,
                details={
                    "request_id": request_id, "stage": "output",
                    "reason": out_reason,
                },
            )
            result = providers.AIResult(
                text=safety.SAFE_FALLBACK, sources=[], model_id=result.model_id,
            )

        return self._finish(
            user, request, request_id,
            message=result.text,
            sources=result.sources,
            metrics=metrics,
            personalized=can_personalize,
            context_categories=ctx["categories"],
            emergency_action=False, emergency_categories=[],
            safety_blocked=safety_blocked, safety_reason=safety_reason,
            model_id=result.model_id,
            use_case=use_case,
            limitation=ctx["limitation"],
        )

    # ------------------------------------------------------------------
    # Trends (FR-AI-004, AD-2)
    # ------------------------------------------------------------------

    def handle_trends(self, actor, target_user, window_days, request):
        """Owner-only health-trend summary from eligible patient-generated data.

        Denials are audited and mapped to 403 by DRF:
        * caller lacks ``analytics.health_trends`` (matrix §3.19) → 403;
        * caller is not the data owner → 403 ``consent_unavailable`` (the
          approved consent surface is a separate, unbuilt stage — DOC/CAR
          C2/3 grants are not reachable here).
        """
        request_id = uuid.uuid4().hex
        if not actor.has_perm_code("analytics.health_trends"):
            record_audit(
                actor=actor, action_code="ai.trends_denied",
                resource_type="ai.trends", resource_id=None,
                result="DENIED", request=request,
                details={
                    "patient_uid": str(target_user.uid),
                    "reason": "missing_permission",
                },
            )
            raise PermissionDenied(
                {"detail": "You do not have permission to view health trends.",
                 "code": "missing_permission"}
            )
        is_owner = actor.pk == target_user.pk and actor.is_verified_patient
        if not is_owner:
            record_audit(
                actor=actor, action_code="ai.trends_denied",
                resource_type="ai.trends", resource_id=None,
                result="DENIED", request=request,
                details={
                    "patient_uid": str(target_user.uid),
                    "reason": "consent_unavailable",
                    "note": "Cross-patient trend analysis requires the approved "
                            "consent surface, which is not part of this stage.",
                },
            )
            raise PermissionDenied(
                {"detail": "Cross-patient trend analysis requires the approved "
                           "consent mechanism, which is not available yet.",
                 "code": "consent_unavailable"}
            )

        metrics = self._trend_metrics(target_user, window_days)
        record_audit(
            actor=actor, action_code="ai.trends",
            resource_type="ai.trends", resource_id=None,
            result="SUCCESS", request=request,
            details={
                "patient_uid": str(target_user.uid),
                "window_days": window_days,
                "window_start": _window_start(window_days).isoformat(),
                "window_end": timezone.localtime().isoformat(),
                "metrics_keys": sorted(metrics.keys()),
            },
        )
        return {
            "patient_uid": str(target_user.uid),
            "window_days": window_days,
            "measured_at": timezone.localtime().isoformat(),
            "metrics": metrics,
            "explanation": self._trend_explanation(metrics, window_days),
            "disclaimer": settings.AI_DISCLAIMER,
        }

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _finish(self, user, request, request_id, *, message, sources, metrics,
                personalized, context_categories, emergency_action,
                emergency_categories, safety_blocked, safety_reason,
                model_id, use_case, limitation):
        if emergency_action and emergency_categories:
            record_audit(
                actor=user, action_code="ai.safety_block",
                resource_type="ai.assistant", resource_id=None,
                result="FAILURE", request=request,
                details={
                    "request_id": request_id, "stage": "input",
                    "reason": "emergency",
                    "emergency_categories": emergency_categories,
                },
            )
        elif safety_blocked and (
            safety_reason in safety.REFUSAL_TEMPLATES or safety_reason == "off_topic"
        ):
            record_audit(
                actor=user, action_code="ai.safety_block",
                resource_type="ai.assistant", resource_id=None,
                result="FAILURE", request=request,
                details={
                    "request_id": request_id, "stage": "input",
                    "reason": safety_reason,
                },
            )

        if emergency_action:
            outcome = "emergency"
        elif safety_blocked and (
            safety_reason in safety.REFUSAL_TEMPLATES or safety_reason == "off_topic"
        ):
            outcome = "refused"
        else:
            outcome = "completed"

        record_audit(
            actor=user, action_code="ai.completed",
            resource_type="ai.assistant", resource_id=None,
            result="SUCCESS", request=request,
            details={
                "request_id": request_id,
                "outcome": outcome,
                "use_case": use_case,
                "personalized": bool(personalized),
                "context_categories": list(context_categories),
                "sources_used": len(sources),
                "model_id": model_id,
            },
        )

        return {
            "assistant_id": request_id,
            "use_case": use_case,
            "personalized": bool(personalized),
            "emergency_action": bool(emergency_action),
            "emergency_categories": list(emergency_categories),
            "safety": {
                "blocked": bool(safety_blocked),
                "reason": safety_reason,
            },
            "metrics": metrics,
            "sources": [dict(s) for s in sources],
            "context_used": bool(context_categories),
            "limitation": limitation or None,
            "message": message,
            "disclaimer": settings.AI_DISCLAIMER,
        }

    def _adherence_metrics(self, user, metric, ctx):
        if metric != "medication_adherence":
            return None
        overall = ctx.get("data", {}).get("medications", {}).get("overall")
        if overall is None:
            stats = adherence_stats(user, window_days=settings.AI_CONTEXT_DAYS)
            overall = stats["overall"]
        return {
            "medication_adherence": {
                "adherence_pct": overall.get("adherence_pct"),
                "expected": overall.get("expected", 0),
                "taken": overall.get("taken", 0),
                "window_days": settings.AI_CONTEXT_DAYS,
            }
        }

    def _trend_metrics(self, user, window_days):
        from medications.models import HealthTimelineEntry, Symptom

        stats = adherence_stats(user, window_days=window_days)
        start_dt = _window_start(window_days)
        symptoms = Symptom.objects.filter(
            patient=user, recorded_at__gte=start_dt, recorded_at__lte=timezone.localtime()
        )
        pains = list(
            symptoms.exclude(pain_level=None).values_list("pain_level", flat=True)
        )
        timeline_count = HealthTimelineEntry.objects.filter(
            patient=user, occurred_at__gte=start_dt,
            occurred_at__lte=timezone.localtime(),
        ).count()
        return {
            "medication_adherence": {
                "adherence_pct": stats["overall"]["adherence_pct"],
                "expected": stats["overall"]["expected"],
                "taken": stats["overall"]["taken"],
            },
            "symptoms_recorded": symptoms.count(),
            "symptom_pain_peak": max(pains) if pains else None,
            "symptom_pain_avg_10": (round(sum(pains) / len(pains), 1) if pains else None),
            "health_timeline_events": timeline_count,
        }

    def _trend_explanation(self, metrics, window_days):
        adherence = metrics["medication_adherence"]
        parts = []
        if adherence["adherence_pct"] is None:
            parts.append("no dose-event data was recorded yet, so adherence "
                         "can't be computed for the window")
        else:
            parts.append(
                f"recorded medication adherence was {adherence['adherence_pct']}% "
                f"({adherence['taken']} of {adherence['expected']} scheduled doses recorded as taken)"
            )
        parts.append(
            f"{metrics['symptoms_recorded']} symptom entr{'y' if metrics['symptoms_recorded'] == 1 else 'ies'} "
            "were recorded"
            + (
                f" (peak pain {metrics['symptom_pain_peak']}/10)"
                if metrics["symptom_pain_peak"] is not None
                else ""
            )
        )
        parts.append(
            f"{metrics['health_timeline_events']} health-timeline event"
            f"{'' if metrics['health_timeline_events'] == 1 else 's'} were recorded"
        )
        return (
            f"Across the last {window_days} days, the available authorised records "
            f"show that: {'; '.join(parts)}. This overview is generated from your "
            "own patient-generated data and is informational — it is not a "
            "diagnosis, risk indicator, or prediction. Figures that appear are "
            "computed deterministically from your records; anything blank means "
            "no matching data was recorded in the window."
        )


def context_build(user, use_case, *, personalized):
    from .context import build_context

    return build_context(user, use_case, personalized=personalized)


def _window_start(window_days):
    from datetime import timedelta

    return timezone.localtime() - timedelta(days=window_days)