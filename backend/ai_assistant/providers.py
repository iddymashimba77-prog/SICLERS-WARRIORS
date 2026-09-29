"""AI provider abstraction (special-systems §3.9.5).

Layering (approved architecture):

    AI Application Service  (ai_assistant.services)
            │
    AI Safety / Guardrails  (ai_assistant.safety)
            │
    AI Provider Interface   (this module)
            │
    Configured Provider     (settings.AI_PROVIDER)

Only one provider ships in this build:

* ``RuleBasedProvider`` — deterministic, template-driven, safe, offline. This is
  the sandbox default (no external calls, no API keys, no client↔provider path).

External LLM providers are the documented extension point behind the same
interface. They are NOT configured: no provider API key exists anywhere in this
repository's settings or environment variables, so this build never claims an
external LLM is operational (see 4.15 implementation note §7/§8).

``ChatPayload`` is the provider-independent request contract. It carries only
authorized, minimum-necessary context assembled server-side (ai_assistant.context)
plus optional approved-knowledge snippets (ai_assistant.knowledge). It NEVER
contains full medical records, other patients' data, or free-form user-supplied
"context" — the pipeline never trusts client text as context.
"""

import logging
from dataclasses import dataclass, field

from django.conf import settings
from rest_framework.exceptions import APIException

logger = logging.getLogger(__name__)

DISCLAIMER = settings.AI_DISCLAIMER

#: Use cases whose answers may be personalised with own patient-generated data.
PERSONALIZED_USE_CASES = frozenset({
    "medication_education",
    "appointment_preparation",
    "health_summary",
    "symptom_assistance",
    "insight_explanation",
})


class ProviderUnavailable(APIException):
    """No configured provider could process the request (transient/503)."""

    status_code = 503
    default_detail = "The AI assistant is temporarily unavailable. Please try again shortly."
    default_code = "ai_provider_unavailable"


@dataclass
class ChatPayload:
    request_id: str
    use_case: str
    message: str
    context: dict  # server-assembled authorized context (categories + data)
    sources: list  # approved-knowledge snippets with citations
    metrics: dict | None = None
    personalized: bool = False


@dataclass
class AIResult:
    text: str
    sources: list = field(default_factory=list)
    model_id: str = "rule_based"
    metrics: dict | None = None
    structured: dict | None = None


class BaseAIProvider:
    """Interface every provider implements."""

    model_id = "base"

    def generate(self, payload: ChatPayload) -> AIResult:
        raise NotImplementedError


class RuleBasedProvider(BaseAIProvider):
    """Deterministic sandbox provider — safe templates, zero external calls.

    The safety layer has ALREADY vetted the input before this provider runs;
    generation only ever returns the approved educational/support wording.
    """

    model_id = "rule_based"

    def generate(self, payload: ChatPayload) -> AIResult:
        use_case = payload.use_case
        text = self._render(use_case, payload)
        return AIResult(
            text=text,
            sources=[dict(s) for s in payload.sources],
            model_id=self.model_id,
            metrics=dict(payload.metrics) if payload.metrics else None,
        )

    # ------------------------------------------------------------------
    # Templates (approved non-diagnostic wording; never clinical claims)
    # ------------------------------------------------------------------

    def _render(self, use_case, payload):
        message = (payload.message or "").strip()
        if use_case == "education":
            return self._education(message, payload.sources)
        if use_case == "health_questions":
            return self._health_question(message, payload.sources)
        if use_case == "medication_education":
            return self._medication_education(payload)
        if use_case == "appointment_preparation":
            return self._appointment_prep(message, payload.context)
        if use_case == "health_summary":
            return self._health_summary(message, payload.context)
        if use_case == "symptom_assistance":
            return self._symptom_assistance(message)
        if use_case == "insight_explanation":
            return self._insight_explanation(payload.metrics)
        return self._education(message, payload.sources)

    def _education(self, message, sources):
        lead = (
            f"Here is a plain-language overview related to your question: \"{message[:160]}\". "
            "This is general health education, not personal medical advice."
        )
        if sources:
            lead += " I'm grounding this in the approved Warrior Academy material found below."
        return lead

    def _health_question(self, message, sources):
        base = (
            f"Regarding \"{message[:160]}\": this is educational information only. "
            "Key points are summarised from approved materials when available; for "
            "decisions about your own care, please talk to a qualified healthcare "
            "professional or pharmacist."
        )
        if sources:
            base += f" Approved source snippets were used: {', '.join(s['title'] for s in sources)}."
        return base

    def _medication_education(self, payload):
        ctx = payload.context or {}
        meds = (ctx.get("data", {}).get("medications") or {}).get("list", [])
        if payload.personalized and meds:
            names = ", ".join(m.get("name", "your medication") for m in meds[:6])
            return (
                f"Based on your approved medication records I can help you understand "
                f"instruction wording for: {names}. Medication information here is "
                "general education — it explains what a medicine is commonly used for "
                "and how to read existing instructions. It never changes, stops or "
                "re-doses any prescription, and it does not identify new drug "
                "interactions you weren't told about. For any change to your medication, "
                f"speak to your prescriber or pharmacist.\n\nQuestions you can ask them: "
                "What is this medicine for? How should I take it, and for how long? "
                "What side effects should I watch for? What should I do if I miss a dose?"
            )
        return (
            "I can explain medication instructions in simple, general language. In "
            "your case I do not have authorised medication context available, so I "
            "will keep this general: always take medicines exactly as prescribed; "
            "ask your prescriber or pharmacist before changing anything; and bring "
            "your medicine list to every appointment. For advice specific to your "
            "records, please check with a qualified healthcare professional or the "
            "pharmacist. I cannot prescribe, change dosages, or recommend stopping "
            "any medicine."
        )

    def _appointment_prep(self, message, ctx):
        topic_hint = ""
        data = (ctx or {}).get("data", {}) or {}
        symptoms = data.get("symptoms", []) or []
        timeline = data.get("timeline", []) or []
        if symptoms:
            topic_hint = (
                " From your authorised symptom journal, you could mention: "
                + ", ".join(
                    f"{s.get('symptom_type_name', 'a symptom')} (pain {s.get('pain_level')}/10)"
                    for s in symptoms[:5]
                )
                + "."
            )
        elif timeline:
            topic_hint = (
                " From your authorised health timeline, recent events you could "
                "mention include: " + ", ".join(t.get("event_type", "event") for t in timeline[:5]) + "."
            )
        return (
            "Preparing for a healthcare appointment is a great way to make the visit "
            "count. You can organise: (1) the symptoms or concerns you want to "
            "discuss and when they started; (2) questions to ask, such as \"What "
            "should I watch for and when should I come back?\" and \"What should I "
            "do between visits?\"; (3) the medicines you take and any missed doses; "
            "and (4) anything that worried you or changed since the last visit."
            + topic_hint
            + " I don't diagnose or predict — I help you organise information to "
            "discuss with your healthcare professional."
        )

    def _health_summary(self, message, ctx):
        data = (ctx or {}).get("data", {}) or {}
        symptoms = data.get("symptoms", []) or []
        timeline = data.get("timeline", []) or []
        meds = (data.get("medications", {}) or {}).get("list", []) or []
        if not (symptoms or timeline or meds):
            return (
                "The available records do not contain enough information to summarize "
                "this period. You can add symptoms and medication events in the app, "
                "and I will be able to organise a summary for you then. This summary "
                "is informational and never a diagnosis."
            )
        parts = []
        if meds:
            parts.append(
                f"medications: {len([m for m in meds if m.get('is_active')])} active "
                f"of {len(meds)} in the window"
            )
        if symptoms:
            pains = [s.get('pain_level') for s in symptoms if s.get('pain_level') is not None]
            if pains:
                parts.append(f"{len(symptoms)} symptom{'s' if len(symptoms) != 1 else ''} recorded, peak pain {max(pains)}/10")
            else:
                parts.append(f"{len(symptoms)} symptom{'s' if len(symptoms) != 1 else ''} recorded")
        if timeline:
            parts.append(f"{len(timeline)} health-timeline events in the window")
        body = "This summarizes only what is recorded in your authorised records: " + "; ".join(parts) + "."
        if not timeline:
            body += " No health-timeline events were found for this period."
        body += " If anything is missing from this period, it wasn't present in the available records — "
        body += "please tell your healthcare professional about anything not shown here."
        return body

    def _symptom_assistance(self, message):
        return (
            "I can help you structure what you just described into a symptom-journal "
            "entry so it's ready to share with your healthcare professional: "
            "date/time, symptom, severity (0-10), duration, possible trigger, what "
            "you tried, and how it went. I don't diagnose what you're feeling — I "
            "just help organise it. If any of what you described is urgent, please "
            "use the Emergency/SOS features in the app and contact local emergency "
            "services without delay."
        )

    def _insight_explanation(self, metrics):
        metric = (metrics or {}).get("medication_adherence")
        if metric is None or metric.get("adherence_pct") is None:
            return (
                "There isn't enough recorded medication-event data yet to compute an "
                "adherence figure for this period. Once you record a few scheduled "
                "doses, this insight will be available. The figure (when shown) is "
                "computed deterministically from your dose records — the assistant "
                "only explains it."
            )
        pct = metric["adherence_pct"]
        expected = metric.get("expected", 0)
        taken = metric.get("taken", 0)
        frame = (
            f"Your recorded medication adherence was {pct}% during the selected period. "
            f"This means {taken} of {expected} scheduled doses in the available records "
            "were recorded as taken."
        )
        if pct < 70:
            frame += " You may want to discuss missed doses and any barriers to taking your medicine with your healthcare provider."
        elif pct < 90:
            frame += " You may want to review any missed doses with your healthcare provider or pharmacist."
        else:
            frame += " Well done keeping up with your schedule. Keep discussing any concerns with your care team."
        frame += " This number is a computation from your dose records, not a medical judgement."
        return frame

_PROVIDERS = {
    "rule_based": lambda: RuleBasedProvider(),
}


def get_ai_provider() -> BaseAIProvider:
    """Provider factory (settings.AI_PROVIDER). Honest failure on misconfig.

    An unknown/unsupported name raises ``ProviderUnavailable`` (→ 503 + audited
    ``ai.provider_failure``): we must never silently fall back to a different
    model than the operator asked for.
    """
    name = (getattr(settings, "AI_PROVIDER", "rule_based") or "rule_based").lower()
    builder = _PROVIDERS.get(name)
    if builder is None:
        logger.error("ai.provider: unknown provider configured: %s", name)
        raise ProviderUnavailable()
    return builder()
