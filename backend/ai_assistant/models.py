"""AI assistant models (intentionally empty).

The approved database-design has NO ``ai_*`` entity (stage 4.15 audit), so the
assistant persists nothing:

* no transcripts / generated text (the assistant never stores the message or
  the answer — no content retention);
* all activity is audited through the existing ``audit_logs`` system
  (traceability TC-AI-003) via ``ai.request``, ``ai.completed``,
  ``ai.safety_block``, ``ai.trends``, ``ai.trends_denied``,
  ``ai.provider_failure``, ``ai.context_access``, ``ai.use_denied``.

The executable surface lives in ``providers.py``, ``safety.py``,
``knowledge.py``, ``context.py`` and ``services.py``.
"""