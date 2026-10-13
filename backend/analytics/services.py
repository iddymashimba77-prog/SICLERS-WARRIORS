"""Aggregate analytics service (approved Stage 4.14).

The ONE place analytics snapshots are computed, written and read. Contract:

* AGGREGATES ONLY (AD-7): every row in ``analytics_snapshots`` is a count /
  sum / average over a population. No identifiers, notes, contact details or
  medical payloads ever reach the table — `dimensions` carry categorical
  slices only (status, urgency, severity, category, symptom-type code,
  document type).
* IDEMPOTENT: ``build_snapshot`` uses ``update_or_create`` on the approved
  unique key (metric_key, dimensions, granularity, measured_at). Re-running
  the aggregation job never double-counts.
* TWO KINDS OF METRIC:
    - ``delta``  — events recorded *within* the aggregation window
                  (donations confirmed, dose events, symptom records, …).
    - ``state``  — point-in-time population snapshots (active blood requests,
                  pending campaigns, …). Historical replay reflects the latest
                  known statuses — the DBD-2 rebuild-on-read decision is
                  documented in the 4.14 implementation note.
* ROLE SCOPE (C6): ``metrics_visible`` limits a VERIFICATION_OFFICER to the
  verification metric set only (blood/campaign/verification-document state).
  SUP/ADM see the full registry. Deny by default for every other role.

The registry below is the explicit whitelist — there is no generic ``**``
metric path (api-design §23).
"""

import datetime
import json
from dataclasses import dataclass, field
from decimal import Decimal

from django.db.models import Avg, Count, Sum
from django.utils import timezone

# NFR-PERF-002: unbounded series scans are rejected by clamping the window.
_MAX_SERIES_DAYS = 366

from accounts.models import SecurityEvent, User, VerificationDocument
from blood_network.models import (
    BloodDonationEvent, BloodMatch, BloodRequest,
)
from community.models import Comment, CommunityPost, Report
from donations.models import Campaign, Donation
from education.models import EducationalContent
from emergencies.models import EmergencyRequest
from medications.models import MedicationEvent, Symptom

from .models import AnalyticsSnapshot

DELTA = "delta"
STATE = "state"

GRANULARITIES = ("DAILY", "WEEKLY", "MONTHLY")

# ---------------------------------------------------------------------------
# Role scopes
# ---------------------------------------------------------------------------

ADMIN_SCOPE = "ADMIN"           # SUPER_ADMIN + ADMIN kernels (§ admin-web §5)
VERIFICATION_SCOPE = "VERIFICATION"  # VO C6 — verification metrics only


@dataclass(frozen=True)
class Metric:
    key: str
    kind: str
    model: type
    ts_field: str
    dimension: str | None = None
    value: str = "count"          # count | sum | avg | count_non_success
    value_field: str | None = None
    anchors: dict = field(default_factory=dict)
    distinct: bool = False
    scope: str = ADMIN_SCOPE


# ---------------------------------------------------------------------------
# Explicit metric registry (the whitelist — no generic path)
# ---------------------------------------------------------------------------

METRICS = {
    # --- People ---
    "users.total": Metric("users.total", STATE, User, "created_at"),
    "users.active": Metric(
        "users.active", STATE, User, "created_at",
        anchors={"account_status": "ACTIVE"},
    ),
    "users.active_patients": Metric(
        "users.active_patients", STATE, User, "created_at", distinct=True,
        anchors={
            "account_status": "ACTIVE",
            "user_roles__is_active": True,
            "user_roles__role__code": "PATIENT",
        },
    ),
    "users.new": Metric("users.new", DELTA, User, "created_at"),
    "verification_docs.by_status": Metric(
        "verification_docs.by_status", STATE, VerificationDocument, "created_at",
        dimension="status", scope=VERIFICATION_SCOPE,
    ),
    # --- Blood ---
    "blood_requests.by_status": Metric(
        "blood_requests.by_status", STATE, BloodRequest, "created_at",
        dimension="status", scope=VERIFICATION_SCOPE,
    ),
    "blood_requests.by_urgency": Metric(
        "blood_requests.by_urgency", STATE, BloodRequest, "created_at",
        dimension="urgency", scope=VERIFICATION_SCOPE,
    ),
    "blood_donations.by_outcome": Metric(
        "blood_donations.by_outcome", DELTA, BloodDonationEvent, "donated_at",
        dimension="outcome",
    ),
    "blood_matches.by_status": Metric(
        "blood_matches.by_status", STATE, BloodMatch, "created_at",
        dimension="status",
    ),
    # --- Emergency ---
    "emergency_requests.by_status": Metric(
        "emergency_requests.by_status", STATE, EmergencyRequest, "created_at",
        dimension="status",
    ),
    "emergency_requests.by_severity": Metric(
        "emergency_requests.by_severity", STATE, EmergencyRequest, "created_at",
        dimension="severity",
    ),
    # --- Donations / campaigns ---
    "campaigns.by_status": Metric(
        "campaigns.by_status", STATE, Campaign, "created_at",
        dimension="status", scope=VERIFICATION_SCOPE,
    ),
    "donations.by_status": Metric(
        "donations.by_status", DELTA, Donation, "created_at",
        dimension="status",
    ),
    "donations.confirmed_amount": Metric(
        "donations.confirmed_amount", DELTA, Donation, "created_at",
        value="sum", value_field="amount",
        anchors={"status": "COMPLETED"},
    ),
    # --- Community ---
    "community_posts.by_status": Metric(
        "community_posts.by_status", STATE, CommunityPost, "created_at",
        dimension="status",
    ),
    "community_posts.by_category": Metric(
        "community_posts.by_category", STATE, CommunityPost, "created_at",
        dimension="category", anchors={"status": "PUBLISHED"},
    ),
    "comments.by_status": Metric(
        "comments.by_status", STATE, Comment, "created_at",
        dimension="status",
    ),
    "reports.by_status": Metric(
        "reports.by_status", STATE, Report, "created_at", dimension="status",
    ),
    # --- Education ---
    "education.by_status": Metric(
        "education.by_status", STATE, EducationalContent, "created_at",
        dimension="status",
    ),
    "education.by_category": Metric(
        "education.by_category", STATE, EducationalContent, "created_at",
        dimension="category__code", anchors={"status": "PUBLISHED"},
    ),
    # --- Health/symptom aggregates (de-identified, §19) ---
    "symptoms.by_type": Metric(
        "symptoms.by_type", DELTA, Symptom, "recorded_at",
        dimension="symptom_type__code",
    ),
    "symptoms.avg_pain": Metric(
        "symptoms.avg_pain", DELTA, Symptom, "recorded_at",
        value="avg", value_field="pain_level",
        anchors={"pain_level__isnull": False},
    ),
    "medication_events.by_status": Metric(
        "medication_events.by_status", DELTA, MedicationEvent, "created_at",
        dimension="status",
    ),
    # --- Security telemetry ---
    "security_events.non_success": Metric(
        "security_events.non_success", STATE, SecurityEvent, "created_at",
        value="count_non_success",
    ),
}


def canonical_dimensions(dimensions=None):
    """Order-independent identity for the JSONB unique key (sort_keys)."""
    dims = dict(dimensions or {})
    return json.loads(json.dumps(dims, sort_keys=True))


def allowed_metrics(user) -> list[str]:
    """Metric keys visible to ``user`` (C6 scope, deny by default)."""
    codes = set(getattr(user, "role_codes", []) or [])
    if not codes:
        return []
    if {"SUPER_ADMIN", "ADMIN"} & codes:
        return [m.key for m in METRICS.values() if m.scope == ADMIN_SCOPE]
    if "VERIFICATION_OFFICER" in codes:
        return [m.key for m in METRICS.values() if m.scope == VERIFICATION_SCOPE]
    return []


# ---------------------------------------------------------------------------
# Snapshot writer + readers
# ---------------------------------------------------------------------------


def _exact_rows(metric_key, dims, granularity="DAILY", since=None):
    """Rows for a metric ordered oldest→newest, matched on the EXACT JSONB
    key.

    Django JSONField ``filter(dimensions=...)`` is CONTAINMENT, not equality
    (and an empty ``{}`` dummy is true for every object on jsonb), so exact
    matching is done in Python against the canonical dict — safe on SQLite and
    Postgres alike. Row volume per (metric, day) is tiny (≤ ~14 slices), so
    this is bounded; WEEKLY/MONTHLY rollups read the same DAILY rows.
    """
    qs = AnalyticsSnapshot.objects.filter(
        metric_key=metric_key, granularity=granularity,
    )
    if since is not None:
        qs = qs.filter(measured_at__gte=since)
    return [r for r in qs.order_by("measured_at") if r.dimensions == dims]


def _latest_row(metric_key, dims, granularity="DAILY"):
    rows = _exact_rows(metric_key, dims, granularity)
    return rows[-1] if rows else None


def build_snapshot(
    metric_key, value, *, dimensions=None, granularity="DAILY", measured_at=None,
):
    """Idempotently write one aggregate row (unique key approved §19).

    Exact-key matched (see ``_exact_rows``) so re-running a day upserts the
    same unique row rather than multiplying slices via JSON containment.
    """
    if granularity not in GRANULARITIES:
        raise ValueError(f"Unsupported granularity: {granularity}")
    metric = METRICS.get(metric_key)
    if metric is None:
        raise ValueError(f"Unknown metric: {metric_key}")
    dims = canonical_dimensions(dimensions)
    measured_at = measured_at or timezone.now()
    if timezone.is_naive(measured_at):
        measured_at = timezone.make_aware(measured_at)
    try:
        decimal_value = Decimal(str(value)).quantize(Decimal("0.000001"))
    except Exception:  # pragma: no cover — defensive; ints/floats/Decimals
        decimal_value = Decimal(str(value))
    candidates = AnalyticsSnapshot.objects.filter(
        metric_key=metric_key, granularity=granularity, measured_at=measured_at,
    )
    existing = next(
        (r for r in candidates if r.dimensions == dims), None,
    )
    if existing is not None:
        existing.value = decimal_value
        existing.save(update_fields=["value"])
        return existing
    return AnalyticsSnapshot.objects.create(
        metric_key=metric_key, dimensions=dims, granularity=granularity,
        measured_at=measured_at, value=decimal_value,
    )


def _window(day, kind):
    """(start, end) filtering bounds for a metric kind on ``day``.

    ``delta`` rows count events recorded inside the calendar day; ``state``
    rows count the population as of the end of the day (cumulative).
    """
    start = day.replace(hour=0, minute=0, second=0, microsecond=0)
    end = day.replace(hour=23, minute=59, second=59, microsecond=999999)
    if kind == STATE:
        return None, end
    return start, end


def _base_queryset(metric, start, end):
    model = metric.model
    kwargs = {f"{metric.ts_field}__lte": end}
    if start is not None:
        kwargs[f"{metric.ts_field}__gte"] = start
    qs = model.objects.filter(**kwargs)
    if metric.anchors:
        qs = qs.filter(**metric.anchors)
    return qs


def compute_daily(day=None) -> int:
    """Compute all approved DAILY snapshots for one calendar ``day``.

    Idempotent — re-running the same day upserts the same unique rows.
    Returns the number of snapshot rows upserted.
    """
    day = (day or timezone.now()).replace(
        hour=0, minute=0, second=0, microsecond=0,
    )
    written = 0
    for metric in METRICS.values():
        start, end = _window(day, metric.kind)
        qs = _base_queryset(metric, start, end)

        if metric.value == "count_non_success":
            value = qs.exclude(status="SUCCESS").count()
            build_snapshot(
                metric.key, value, measured_at=end,
            )
            written += 1
            continue

        if metric.dimension:
            rows = (
                qs.values(metric.dimension)
                .order_by()
                .annotate(
                    _v=Count("id", distinct=metric.distinct)
                    if metric.value == "count"
                    else Sum(metric.value_field) if metric.value == "sum"
                    else Avg(metric.value_field),
                )
            )
            for row in rows:
                key = row[metric.dimension]
                if key is None:
                    continue
                build_snapshot(
                    metric.key, row["_v"],
                    dimensions={metric.dimension.split("__")[-1]: key},
                    measured_at=end,
                )
                written += 1
            continue

        if metric.value == "count":
            value = qs.count() if not metric.distinct else qs.distinct().count()
        elif metric.value == "sum":
            value = qs.aggregate(_v=Sum(metric.value_field))["_v"] or 0
        elif metric.value == "avg":
            value = qs.aggregate(_v=Avg(metric.value_field))["_v"]
            if value is None:
                continue  # no data yet — no snapshot row for the day
        else:  # pragma: no cover — registry is closed; defensive
            continue
        build_snapshot(metric.key, value, measured_at=end)
        written += 1
    return written


def compute_range(days: int = 90) -> int:
    """Aggregate the trailing ``days`` (including today) DAILY windows."""
    today = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
    written = 0
    for i in range(days - 1, -1, -1):
        written += compute_daily(today - datetime.timedelta(days=i))
    return written


def latest(metric_key, dimensions=None):
    """Most recent DAILY snapshot value for a metric (+ exact dimensions)."""
    dims = canonical_dimensions(dimensions)
    row = _latest_row(metric_key, dims)
    return float(row.value) if row else None


def daily_series(metric_key, days=30, dimensions=None):
    """Daily snapshot series (oldest→newest) for dashboards/trends."""
    dims = canonical_dimensions(dimensions)
    since = timezone.now() - datetime.timedelta(days=days - 1)
    rows = _exact_rows(
        metric_key, dims,
        since=since.replace(hour=0, minute=0, second=0, microsecond=0),
    )
    return [
        {"measured_at": r.measured_at.date().isoformat(), "value": float(r.value)}
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Live (on-read) KPI counts
# ---------------------------------------------------------------------------
# AD-7 requires the dashboard to be aggregate-only, but the requirement also
# asks for *real* figures rather than whatever the last nightly aggregation
# happened to write. These helpers answer the question directly from the source
# tables with plain ``.count()`` / ``.values(...).annotate(Count(...))`` calls:
# no row is materialised, so no identifier, contact detail or clinical field can
# leak into a dashboard response. Snapshot rows remain the source for the
# derived/aggregate figures that have no cheap on-read equivalent (money,
# averages) and for every historical trend.

_ACTIVE_STATUSES = ("ACTIVE",)
_ROLE_COUNT_CODES = (
    "PATIENT", "DOCTOR", "BLOOD_DONOR", "FINANCIAL_DONOR", "CAREGIVER",
    "HOSPITAL", "ORGANIZATION", "HEALTHCARE_STAFF",
)


def _role_counts() -> dict[str, int]:
    """One grouped query for every role population on the dashboard.

    A single ``values().annotate(Count())`` over the ``user_roles`` join keeps
    this to two queries total instead of one per role, and a user holding two
    roles is intentionally counted in both populations.
    """
    from accounts.models import UserRole

    rows = (
        UserRole.objects.filter(is_active=True, role__code__in=_ROLE_COUNT_CODES)
        .values("role__code")
        .annotate(_n=Count("user_id"))
    )
    counts = {row["role__code"].lower(): int(row["_n"]) for row in rows}
    return {code.lower(): counts.get(code.lower(), 0) for code in _ROLE_COUNT_CODES}


def live_kpis() -> tuple[dict[str, int], dict[str, str]]:
    """Compute the state KPIs from source tables.

    Returns ``(values, sources)`` where ``sources`` records, per KPI, whether
    the figure is ``live`` (computed for this request) or ``snapshot`` (last
    aggregation run) so the UI can be honest about freshness.
    """
    now = timezone.now()
    values: dict[str, int] = {}
    sources: dict[str, str] = {}

    users = User.objects.all()
    values["users_total"] = users.count()
    values["users_active"] = users.filter(account_status="ACTIVE").count()
    values["users_pending_verification"] = users.filter(
        account_status="PENDING_VERIFICATION"
    ).count()
    values["users_suspended"] = users.filter(account_status="SUSPENDED").count()

    for code, count in _role_counts().items():
        values[f"users_{code}"] = count
    # `users_active_patients` is the historical key the admin web already reads.
    values["users_active_patients"] = (
        User.objects.filter(
            account_status__in=_ACTIVE_STATUSES, user_roles__is_active=True,
            user_roles__role__code="PATIENT",
        ).distinct().count()
    )

    values["verified_docs"] = VerificationDocument.objects.filter(
        status="VERIFIED"
    ).count()
    values["verification_docs_pending"] = VerificationDocument.objects.filter(
        status="PENDING"
    ).count()

    blood_open = BloodRequest.objects.filter(
        status__in=["PENDING_VERIFICATION", "ACTIVE", "MATCHING", "MATCHED"]
    ).count()
    values["blood_requests_pending_verification"] = BloodRequest.objects.filter(
        status="PENDING_VERIFICATION"
    ).count()
    values["blood_requests_active"] = BloodRequest.objects.filter(
        status__in=["ACTIVE", "MATCHING", "MATCHED"]
    ).count()
    values["active_blood_requests"] = blood_open

    campaign_pending = Campaign.objects.filter(status="PENDING_VERIFICATION").count()
    values["campaigns_pending_verification"] = campaign_pending
    values["campaigns_active"] = Campaign.objects.filter(status="ACTIVE").count()

    values["pending_verifications"] = (
        VerificationDocument.objects.filter(status="PENDING").count()
        + BloodRequest.objects.filter(status="PENDING_VERIFICATION").count()
        + campaign_pending
    )
    values["active_emergencies"] = EmergencyRequest.objects.filter(
        status__in=_OPEN_EMERGENCY_STATUSES
    ).count()
    values["emergency_requests_critical"] = EmergencyRequest.objects.filter(
        severity="CRITICAL", status__in=_OPEN_EMERGENCY_STATUSES
    ).count()
    values["pending_moderation"] = Report.objects.filter(
        status__in=_OPEN_REPORT_STATUSES
    ).count()
    values["open_reports"] = Report.objects.filter(status="OPEN").count()
    values["published_content"] = EducationalContent.objects.filter(
        status="PUBLISHED"
    ).count()

    for key in values:
        sources[key] = "live"
    return values, sources


# ---------------------------------------------------------------------------
# Reporting surface helpers
# ---------------------------------------------------------------------------

_VERIFICATION_KPI = [
    ("blood_requests_pending_verification", "blood_requests.by_status", {"status": "PENDING_VERIFICATION"}),
    ("blood_requests_active", "blood_requests.by_status", {"status": "ACTIVE"}),
    ("campaigns_pending_verification", "campaigns.by_status", {"status": "PENDING_VERIFICATION"}),
    ("campaigns_active", "campaigns.by_status", {"status": "ACTIVE"}),
    ("verification_docs_pending", "verification_docs.by_status", {"status": "PENDING"}),
]

_ADMIN_KPI = [
    ("users_total", "users.total", None),
    ("users_active", "users.active", None),
    ("users_active_patients", "users.active_patients", None),
    ("verified_docs", "verification_docs.by_status", {"status": "VERIFIED"}),
    ("active_blood_requests", "blood_requests.by_status", {"status": "ACTIVE"}),
    ("emergency_requests_critical", "emergency_requests.by_severity", {"severity": "CRITICAL"}),
    ("active_campaigns", "campaigns.by_status", {"status": "ACTIVE"}),
    ("confirmed_donations_amount", "donations.confirmed_amount", None),
    ("open_reports", "reports.by_status", {"status": "OPEN"}),
    ("published_content", "education.by_status", {"status": "PUBLISHED"}),
]

_TREND_METRICS = [
    "users.total",
    "users.new",
    "donations.confirmed_amount",
    "symptoms.avg_pain",
    "blood_requests.by_status",
]

# Live queue badge queries — Count() only, no row materialisation (no PHI).
_OPEN_EMERGENCY_STATUSES = ("CREATED", "VALIDATING", "ACTIVE", "RESPONDING", "ESCALATED")
_OPEN_REPORT_STATUSES = ("OPEN", "IN_REVIEW")


class AnalyticsService:
    """AnalyticsService (api-design §40) — facade over the pure helpers above."""

    def metrics_visible(self, user) -> list[str]:
        return allowed_metrics(user)

    def build_snapshot(self, metric_key, value, *, dimensions=None, granularity="DAILY", measured_at=None):
        return build_snapshot(
            metric_key, value, dimensions=dimensions,
            granularity=granularity, measured_at=measured_at,
        )

    def compute_range(self, days: int = 90) -> int:
        return compute_range(days)

    def latest(self, metric_key, dimensions=None):
        return latest(metric_key, dimensions)

    def daily_series(self, metric_key, days=30, dimensions=None):
        return daily_series(metric_key, days=days, dimensions=dimensions)

    def series(self, user, metric, granularity="DAILY", date_from=None, date_to=None):
        """Snapshot series for ``metric`` with optional granularity rollup.

        DAILY returns stored rows; WEEKLY/MONTHLY are rolled up from the
        stored DAILY rows (count/sum metrics — averages are DAILY-only and
        rejected above daily resolution to avoid a wrong average-of-averages).
        """
        if metric not in allowed_metrics(user):
            return []
        if granularity not in GRANULARITIES:
            raise ValueError(f"Unsupported granularity: {granularity}")
        rows = AnalyticsSnapshot.objects.filter(
            metric_key=metric, granularity="DAILY",
        ).order_by("measured_at")
        if date_from is None:
            # NFR-PERF-002 (bounded reporting windows): never allow an unbounded
            # metric scan when the caller omits the start date — clamp to the
            # maximum approved reporting window.
            date_from = timezone.now() - datetime.timedelta(days=_MAX_SERIES_DAYS)
        if date_from:
            rows = rows.filter(
                measured_at__gte=date_from.replace(hour=0, minute=0, second=0, microsecond=0),
            )
        if date_to:
            rows = rows.filter(
                measured_at__lte=date_to.replace(hour=23, minute=59, second=59, microsecond=999999),
            )
        data = [
            {
                "measured_at": r.measured_at.replace(minute=0, second=0, microsecond=0),
                "value": float(r.value),
                "dimensions": r.dimensions,
            }
            for r in rows
        ]
        if granularity == "DAILY":
            return [
                {"measured_at": d["measured_at"].isoformat(), "value": d["value"], "dimensions": d["dimensions"]}
                for d in data
            ]
        metric_def = METRICS[metric]
        if metric_def.value == "avg":
            raise ValueError(f"{granularity} resolution is not supported for {metric}")
        buckets = {}
        for d in data:
            key = d["measured_at"].strftime("%Y-%W") if granularity == "WEEKLY" \
                else d["measured_at"].strftime("%Y-%m")
            buckets.setdefault(key, 0.0)
            buckets[key] += d["value"]
        return [
            {"period": key, "value": round(v, 4)}
            for key, v in sorted(buckets.items())
        ]

    # ------------------------------------------------------------------
    # Dashboard (AD-7: aggregates only — no raw rows ever serialised)
    # ------------------------------------------------------------------

    def dashboard(self, user) -> dict:
        codes = set(getattr(user, "role_codes", []) or [])
        if "VERIFICATION_OFFICER" in codes and not (codes & {"SUPER_ADMIN", "ADMIN"}):
            return self._verification_dashboard(user)
        return self._admin_dashboard(user)

    def _admin_dashboard(self, user) -> dict:
        codes = set(getattr(user, "role_codes", []) or [])
        live, sources = live_kpis()

        # Snapshot figures only fill the gaps that have no cheap on-read
        # equivalent (money, averages) — everything countable is live.
        kpis = dict(live)
        for key, metric, dims in _ADMIN_KPI:
            if key in kpis:
                continue
            value = self.latest(metric, dims)
            if value is not None:
                kpis[key] = value
                sources[key] = "snapshot"

        kpis["system_alerts_24h"] = SecurityEvent.objects.filter(
            created_at__gte=timezone.now() - datetime.timedelta(hours=24),
        ).exclude(status="SUCCESS").count()
        sources["system_alerts_24h"] = "live"

        trends = {
            metric: self.daily_series(metric, days=30)
            for metric in ("users.total", "users.new", "donations.confirmed_amount")
        }
        return {
            "generated_at": timezone.now().isoformat(),
            "role_kernel": "SUPER_ADMIN" if "SUPER_ADMIN" in codes else "ADMIN",
            "kpis": kpis,
            "kpi_sources": sources,
            "trends": trends,
        }

    def _verification_dashboard(self, user) -> dict:
        live, sources = live_kpis()
        kpis = {key: live[key] for key, _metric, _dims in _VERIFICATION_KPI if key in live}
        for key, metric, dims in _VERIFICATION_KPI:
            if key in kpis:
                continue
            value = self.latest(metric, dims)
            if value is not None:
                kpis[key] = value
                sources[key] = "snapshot"
        kpis["pending_verifications"] = live["pending_verifications"]
        sources["pending_verifications"] = "live"
        return {
            "generated_at": timezone.now().isoformat(),
            "role_kernel": "VERIFICATION_OFFICER",
            "kpis": kpis,
            "kpi_sources": sources,
            "trends": {},
        }

    def _sum_status(self, metric, statuses) -> int | None:
        total = 0
        seen = 0
        for st in statuses:
            value = self.latest(metric, {"status": st})
            if value is not None:
                total += value
                seen += 1
        return total if seen else None