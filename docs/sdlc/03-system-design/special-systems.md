# 3.9 Special Systems

## 3.9.1 Blood Matching Architecture

```
Blood Request
      ↓
Verification (admin/verification officer)
      ↓
Matching Engine
      │
      ├── Blood group (compatible)
      ├── Location (region/city)
      ├── Availability (is_available=true)
      ├── Last donation date (minimum interval)
      └── Donation history
      ↓
Potential Donors (ranked)
      ↓
Notification (push to eligible donors)
      ↓
Donor Response (accept/decline)
      ↓
Fulfillment Tracking
```

**Kanuni:**
- Blood requests lazima ziverefreshwe (verified) kabla ya kuwa active.
- Matching engine sio medical eligibility determination — hiyo inafanywa na blood bank/qualified personnel.
- Donor contact information haishirikiwi publicly (BR-006).
- Matching inafanyika server-side (backend worker).
- Donor anaweza kukataa bila sababu (privacy).

**Matching algorithm (simple):**
1. Filter: blood_group compatible (O- universal, etc.)
2. Filter: is_available = true
3. Filter: last_donation_date ≥ 90 days ago (kwa maisha ya damu)
4. Rank: location proximity (region first)
5. Rank: fewer past matches (equitable distribution)

## 3.9.2 Emergency Architecture

```
Emergency Request
       ↓
Validate (rate limiting, verification)
       ↓
Classify Severity
       │
       ├── NORMAL (non-life-threatening)
       ├── URGENT (needs prompt response)
       └── CRITICAL (life-threatening)
       ↓
Priority Engine
       ↓
Notify Relevant Responders (admin, caregivers, nearby donors if blood)
       ↓
Response Tracking
       ↓
Resolved / Cancelled / Expired
```

**Abuse Prevention:**
- Rate limiting: max N requests per user per time window.
- Verification: optional (phone/email verification before creating).
- Admin monitoring: emergency requests visible to admin dashboard.
- Audit trail: all emergency actions logged.

**Emergency Override (medical access):**
- Limited access to patient medical records during critical emergency (policy-defined).
- Must be audited: who accessed, what, why, when.
- Patient consent check may be bypassed only for critical emergencies (configurable).
- Admin can review and revoke emergency access post-hoc.

## 3.9.3 Payment Architecture

```
Mobile App
    ↓
Donation API (/donations POST)
    ↓
Payment Service (backend)
    ↓
Payment Provider Interface
    │
    ├── M-Pesa
    ├── Airtel Money
    ├── Tigo Pesa
    ├── ClickPesa
    └── Selcom
    ↓
Provider Callback (webhook)
    ↓
Status Update (pending → success/failed/refunded)
    ↓
Receipt Generation
```

**Kanuni:**
- Payment confirmation lazima ishike server-side (BR-008).
- No direct client ↔ provider communication (except redirect/init flow).
- Transaction reference unique (UUID-based).
- Webhook validation: provider signature verification.
- Idempotency: duplicate webhooks handled safely.

## 3.9.4 Notification Architecture

```
Application Event (medication reminder, blood request, emergency, payment, community)
       ↓
Notification Service (backend worker)
       ↓
 ┌─────┼─────┐
 ▼     ▼     ▼
Push  In-App  Email*
(* Email = future; SMS = future)

Push = Firebase Cloud Messaging (FCM)
In-App = database-stored, fetched on app open
```

**Kanuni:**
- Notifications are async (background worker).
- User preferences: opt-in/out per category.
- Emergency notifications: high priority, cannot be disabled by user.
- Batch notifications: coalesce multiple events (e.g. multiple comments).
- Rate limiting: prevent notification spam.

## 3.9.5 AI Architecture

```
                  AI / Intelligence
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
    AI Assistant     Risk Engine    Analytics
    (chat)           (trends)       (aggregated)
          │              │              │
          ▼              ▼              ▼
      Safe Output    Risk Indicator   Insights
```

**Safety Layer:**
```
User Input
    ↓
Safety Filter (keyword detection, context)
    ↓
AI Processing (LLM or rule-based)
    ↓
Medical Safety Validation (no diagnosis, no prescription)
    ↓
Response
```

**Emergency Detection:**
- AI identifies emergency-related language in user input.
- Safety response: encourage appropriate urgent care.
- No AI diagnosis: always disclaim (FR-AI-006).

**Data Access:**
- AI has access only to patient-generated data (medication, symptoms, timeline).
- AI does NOT have access to full medical records unless explicitly authorized.
- AI output is informational, not clinical.

**Models:**
- Initial: rule-based + simple LLM (for education, FAQ).
- Future: validated ML models for trend analysis (with clinical governance).

## 3.9.6 Traceability

- FR-BLD → Blood Matching (3.9.1)
- FR-EMG → Emergency (3.9.2)
- FR-PAY/CAM → Payments (3.9.3)
- FR-NOT → Notifications (3.9.4)
- FR-AI → AI (3.9.5)