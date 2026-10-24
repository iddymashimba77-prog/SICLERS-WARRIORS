"""Deterministic AI safety layer (special-systems §3.9.5; FR-AI-003/006).

Pipe: input safety filter → AI processing → medical safety validation → output.

This layer is deliberately **rule-based, not LLM-dependent**. Emergency intent
is detected with keyword/pattern rules BEFORE any provider runs, and the output
validators are the last gate before the client sees text. Nothing here claims
certainty about anyone's medical state (BR-010/011, FR-AI-006).

Refusal categories mirror the safety boundary:

* diagnosis (do not diagnose)
* prescription / dosage numbers (do not prescribe, change, or stop medication)
* fabricated records/outcomes (never invent medical records)
* privacy (no cross-patient data; no leaking identifiers)
* consent bypass / instruction override (jailbreak resistance)
* unsupported certainty ("guaranteed", "100% cure", ...) in output
"""

import re

# ---------------------------------------------------------------------------
# Emergency indicators (approved categories: severe symptoms, loss of
# consciousness, difficulty breathing, severe chest symptoms, uncontrolled
# bleeding, serious neurological symptoms, self-harm).
# ---------------------------------------------------------------------------

EMERGENCY_PATTERNS = [
    ("loss_of_consciousness", re.compile(
        r"(\b(passed? out|fainted|unconscious|lost consciousness|loss of consciousness|blacked? out)\b)",
        re.I,
    )),
    ("breathing_difficulty", re.compile(
        r"(\b(can'?t breathe|struggling? to breathe|difficult(y|ies)? breathing|short(ness)? of breath|can'?t (get|catch) (my )?breath)\b)",
        re.I,
    )),
    ("chest", re.compile(
        r"(\b(severe chest (pain|pressure)|crushing chest|chest pain (that )?(is )?(severe|worsening))\b)",
        re.I,
    )),
    ("bleeding", re.compile(
        r"(\b(uncontrolled bleeding|can'?t stop bleeding|bleeding (heavily|profusely)|severe (bleeding|blood loss))\b)",
        re.I,
    )),
    ("neuro", re.compile(
        r"(\b(slurred speech|face droop|one-?side (weakness|numbness)|sudden (weakness|numbness)|stroke|seizure(s)?|convulsion(s)?)\b)",
        re.I,
    )),
    ("self_harm", re.compile(
        r"(\b(kill myself|suicid(al|e)|self[ -]?harm|want to die|end my life)\b)",
        re.I,
    )),
]


def scan_emergency(text) -> list[str]:
    """Return matched emergency categories (deterministic). Empty = not flagged."""
    matched = []
    for category, pattern in EMERGENCY_PATTERNS:
        if pattern.search(text):
            matched.append(category)
    return matched


EMERGENCY_RESPONSE = (
    "This may need urgent medical attention, and I can't assess or confirm what's "
    "happening. If this is an emergency, use the app's Emergency/SOS feature and "
    "call your local emergency number (for example, the national ambulance hotline) "
    "or go to the nearest emergency department now. Do not wait for an app reply. "
    "If it is not urgent, please contact your healthcare professional. This is "
    "educational support only and is not a medical assessment."
)


# ---------------------------------------------------------------------------
# Input guards — refuse unsafe requests up front (cheaper + deterministic).
# ---------------------------------------------------------------------------

REFUSAL_TEMPLATES = {
    "diagnosis": (
        "I'm an education and decision-support assistant, not a doctor, so I can't "
        "diagnose or tell you what condition you may have. Please discuss symptoms "
        "with a qualified healthcare professional. I can help you prepare questions "
        "or understand general education if that would help."
    ),
    "prescription": (
        "I can't prescribe, recommend starting a medicine, or give dosage advice — "
        "those decisions belong to a qualified prescriber. Please talk to your "
        "doctor or pharmacist, and keep taking any prescribed medicine exactly as "
        "directed until you discuss it with them."
    ),
    "dose_change": (
        "I can't advise changing, increasing, decreasing, or stopping any medication "
        "or its dosage. Please speak with the prescriber or pharmacist who knows "
        "your care before making any change."
    ),
    "stop_medication": (
        "Stopping or skipping a prescribed medication needs a professional "
        "conversation, so I can't recommend it. Please contact your prescriber or "
        "pharmacist to review your treatment safely."
    ),
    "fabricate": (
        "I can't generate or alter medical records, lab results, or treatment "
        "history. Records are only ever created through the approved clinical "
        "workflows, never by the assistant."
    ),
    "privacy": (
        "I only ever use your own authorised, minimum-necessary data. I can't "
        "reveal, compare, or use another person's records, and I won't bypass the "
        "consent rules that protect health data."
    ),
    "override": (
        "I can't change or ignore the safety rules I run under. This assistant "
        "always stays educational and non-diagnostic."
    ),
}

_INPUT_GUARDS = [
    ("diagnosis", re.compile(
        r"(\bdiagnos(e|is|ing)|what (disease|condition|illness) (do i|did i)|do i have \w+|am i (having|getting|at risk of)|could i have )",
        re.I,
    )),
    ("prescription", re.compile(
        r"(\bprescrib(e|ing|tion)|what should i take (for|to)|which medicine (for|should)|should i take \w+ (for|to))",
        re.I,
    )),
    ("dose_change", re.compile(
        r"(\b(change|adjust|increase|decrease|reduce|wean|taper|double|halve) (my )?(dose|dosage)|how much (of|should i take) \w+|dosage (should|advice))",
        re.I,
    )),
    ("stop_medication", re.compile(
        r"(\b(stop|quit|discontinue|skip) (taking |taking my )?(medication|medicine|meds|drugs|tablets?))",
        re.I,
    )),
    ("fabricate", re.compile(
        r"(\b(invent|make up|fabricate|fake|forge) (a )?(medical record|lab result|test result|treatment history|diagnosis))",
        re.I,
    )),
    ("privacy", re.compile(
        r"(\b(another|other|someone else's) (patient|person)|(leak|reveal|show me) (someone else|another record|user's)|whose records|about (user|patient) \d)",
        re.I,
    )),
    ("override", re.compile(
        r"(\bignore (previous|your|the) (instructions|rules|safety|prompt|guidelines)|you are now |act as (an? )?(unrestricted|unlimited) doctor|jailbreak|developer message|system prompt>|\[system)",
        re.I,
    )),
]


def input_guard(text) -> tuple[bool, str]:
    """Return (is_safe, refusal_key_or_empty). False → refuse with template."""
    for key, pattern in _INPUT_GUARDS:
        if pattern.search(text):
            return False, key
    return True, ""


# ---------------------------------------------------------------------------
# Output validation — last gate before the client sees generated text.
# ---------------------------------------------------------------------------

_OUTPUT_FORBIDDEN = [
    ("diagnosis", re.compile(
        r"(\b(you (have|are diagnosed with|suffer from) \w+ (disease|condition)|your diagnosis is|i diagnose (you|that)|certainly have sickle cell|you (have|are) (sickle cell|a)\b.*\b(disease))\b)",
        re.I,
    )),
    ("prescription", re.compile(
        r"(\byou should (start|begin) (taking|using) \w+|take \d+ ?(mg|ml|units?|tablets?)\b per|(i (prescribe|recommend) (you take|a dose)))",
        re.I,
    )),
    ("dose_change", re.compile(
        r"(\b(change|increase|decrease|double|halve|stop|skip) your (dose|dosage|medication)\b)",
        re.I,
    )),
    ("certainty", re.compile(
        r"(\b(guaranteed?|100% (will|works|cures)|definitely (works|cured|safe)|no doubt|i can (confirm|cure))\b)",
        re.I,
    )),
    ("fabricate", re.compile(
        r"(\b(i (invented|made up|fabricated)|fake (lab|test|medical record)|your (lab|test) (results|report) (show|say|are))\b)",
        re.I,
    )),
    ("privacy_leak", re.compile(
        r"(\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b)",
        re.I,
    )),
]

def validate_output(text) -> tuple[bool, str]:
    """Return (is_safe, reason). False → the caller must fall back."""
    for key, pattern in _OUTPUT_FORBIDDEN:
        if pattern.search(text):
            return False, key
    return True, ""


SAFE_FALLBACK = (
    "I can't answer that at that level of detail — it would cross into medical "
    "advice I'm not allowed to give. I'm here for education and to help you "
    "prepare for conversations with your healthcare professional. For anything "
    "clinical, please ask a qualified doctor, pharmacist, or nurse."
)

#: Polite scope-limitation reply for anything outside sickle cell disease and
#: the Sickler's Warriors platform (FR-AI-001 scope). Bilingual so a Swahili
#: speaker is never left without a clear answer.
OFF_TOPIC_REFUSAL = (
    "Samahani, niko hapa kukujibu kuhusu seli mundu (sickle cell disease) na "
    "mambo yanayohusiana na app yetu ya Sickler's Warriors pekee. Naweza "
    "kukusaidia na elimu, ushauri wa jumla kuhusu seli mundu, dawa "
    "zinazohusiana na seli mundu, au maswala ya afya yanayohusiana na seli "
    "mundu. Tafadhali uliza swali linalohusiana na seli mundu. "
    "(Sorry — I can only help with sickle cell disease and the Sickler's "
    "Warriors app. Please ask a sickle-cell related question.)"
)

#: Explicit sickle-cell vocabulary (the core in-scope domain).
_SICKLE_CELL_TERMS = re.compile(
    r"\b(sickle[ -]?cell|sickle|sickling|vaso[ -]?occlusive|vasoocclusive|"
    r"cris(e|es|is)|hbs|hb ?s|hemoglobin ?s|hbf|drepanocyt\w*|"
    r"hydroxyurea|hydroxycarbamide|hydroxyurea|folic acid|folate|"
    r"exchange transfusion|blood transfusion|transfusion|"
    r"thalass?emia|sickle trait|sickle cell trait|splenic|painful crisis|"
    r"pain cris\w+|acute chest syndrome|acute chest|"
    r"osteomyelitis|leg ulcer|retinopath\w*|avascular necrosis|"
    r"priapism|dactylitis|sequestration|aplastic crisis|"
    r"hydrea|endari|voxelotor|oxbryta|adkveo|crizanlizumab|"
    r"sickle disease|red (blood )?cell|blood disorder|haemoglobinopathy|"
    r"hemoglobinopathy|genetic blood)\b",
    re.I,
)

#: App / general health vocabulary that stays in scope because it describes the
#: platform or sickle-cell-adjacent care (education, meds, symptoms, records).
_GENERAL_HEALTH_TERMS = re.compile(
    r"\b(health|medical|medicine|medication|meds|drug|pill|tablet|dose|dosage|"
    r"prescription|pharmac\w*|symptom|pain|fever|ana?emia|jaundice|"
    r"infection|dehydration|hydration|appointment|doctor|nurse|clinic|"
    r"hospital|treatment|therapy|care|diagnos\w*|test|screening|blood|"
    r"vaccin\w*|fluids?|oxygen|headache|swelling|fatigue|tiredness|"
    r"app|account|profile|sign ?up|login|record|reminder|emergency|sos|"
    r"donor|donation|campaign|education|academy|patient|caregiver|"
    r"genetic|genetics|gene|inherit|hered|nutrition|diet|food|eat|meal|"
    r"mental|psycholog\w*|counsel\w*|stress|anxiety|depress\w*|support|family|"
    r"hello|hi|hey|habari|mambo|salaam|salam|thank\w*|asante|help)\b",
    re.I,
)


def is_topic_allowed(text: str) -> tuple[bool, str]:
    """Return ``(is_allowed, reason)`` for the assistant's scope.

    The Sickler's Warriors assistant is deliberately scoped to sickle cell
    disease and the platform. Anything else is answered with the polite
    :data:`OFF_TOPIC_REFUSAL` instead of an unrelated (and unapproved) answer.

    Empty/greeting messages are allowed through so the provider can greet the
    user; the provider's own system instruction still refuses off-topic detail.
    """
    if not text or not text.strip():
        return True, ""
    if _SICKLE_CELL_TERMS.search(text) or _GENERAL_HEALTH_TERMS.search(text):
        return True, ""
    return False, "off_topic"