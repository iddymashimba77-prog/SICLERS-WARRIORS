"""Authorized context selection for the assistant (§ stage 5: Minimum Necessary Data).

The assistant NEVER receives the full patient record. ``build_context`` assembles
only the approved patient-generated categories (medication, symptoms, health
timeline — special-systems §3.9.5) for the **owner**, bounded by settings caps,
and only for use cases that actually need them.

Privacy rules enforced here:
* Context is self-only. There is no approved consent surface in this build
  (consent design is separate/unbuilt), so cross-patient or caregiver/doctor
  personalization is impossible — the pipeline returns an empty context and the
  provider falls back to general education with an explicit limitation notice.
* Genotype, primary diagnosis, blood group and medical-record content are NOT
  part of the AI context (medical records are not authorized to the assistant;
  the medical_records app is still a scaffold).
* Numbers are what matter — timestamps become dates, and free-text notes are
  never copied into context.
"""

from django.conf import settings

from medications.services import adherence_stats

PERSONALIZED_USE_CASES = frozenset({
    "medication_education",
    "appointment_preparation",
    "health_summary",
    "insight_explanation",
})


def build_context(user, use_case, *, personalized: bool) -> dict:
    """Return ``{"categories": [...], "data": {...}, "limitation": "..."}``.

    ``personalized`` is decided by the caller AFTER the consent/privacy check;
    if it requests data the user is not entitled to, an empty context with a
    limitation notice is returned (education continues on general terms).
    """
    if not (user and user.is_authenticated):
        return {"categories": [], "data": {}, "limitation": ""}
    if not personalized or use_case not in PERSONALIZED_USE_CASES or not user.is_verified_patient:
        return {
            "categories": [],
            "data": {},
            "limitation": (
                "No authorised personal health data was used for this answer; "
                "it is general educational information."
            ),
        }

    data = {}
    categories = []

    if use_case in ("medication_education", "insight_explanation", "health_summary"):
        stats = adherence_stats(user, window_days=settings.AI_CONTEXT_DAYS)
        meds = [
            {
                "uid": m["uid"],
                "name": m["name"],
                "strength": m["strength"],
                "is_active": m["is_active"],
                "adherence_pct": m["adherence_pct"],
                "expected": m["expected"],
                "taken": m["taken"],
            }
            for m in stats["per_medication"][: settings.AI_MEDICATION_EDUCATION_LIMIT]
        ]
        data["medications"] = {
            "overall_adherence_pct": stats["overall"]["adherence_pct"],
            "expected": stats["overall"]["expected"],
            "taken": stats["overall"]["taken"],
            "list": meds,
        }
        categories.append("medications")
        if use_case == "insight_explanation":
            data["symptoms"] = _recent_symptoms(user)
            categories.append("symptoms")

    if use_case in ("health_summary", "appointment_preparation"):
        data["symptoms"] = _recent_symptoms(user)
        data["timeline"] = _recent_timeline(user)
        categories += ["symptoms", "timeline"]

    return {"categories": sorted(set(categories)), "data": data, "limitation": ""}


def _recent_symptoms(user):
    from medications.models import Symptom

    return [
        {
            "symptom_type_name": s.symptom_type.name if s.symptom_type else None,
            "pain_level": s.pain_level,
            "duration_minutes": s.duration_minutes,
            "recorded_on": s.recorded_at.date().isoformat(),
        }
        for s in Symptom.objects.filter(patient=user).select_related("symptom_type")[: settings.AI_SYMPTONS_HISTORY_LIMIT]
    ]


def _recent_timeline(user):
    from medications.models import HealthTimelineEntry

    return [
        {
            "event_type": t.event_type,
            "occurred_on": t.occurred_at.date().isoformat(),
            "summary": t.summary,
        }
        for t in HealthTimelineEntry.objects.filter(patient=user)[: settings.AI_TIMELINE_HISTORY_LIMIT]
    ]