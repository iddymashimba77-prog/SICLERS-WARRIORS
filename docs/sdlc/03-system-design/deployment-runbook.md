# 3.9 Stage — Deployment Runbook

> Part of Stage 3.9 Deployment Design (§45). This defines the **future**
> production deployment sequence. **Do NOT execute any of these steps now.**
> This runbook lives and evolves in Stage 4; a release is executed only after
> explicit owner approval.

---

## 1. Release Types

| Type | Trigger | Approval | Target |
|---|---|---|---|
| Hotfix | Critical prod defect | Owner + release manager | Production |
| Standard | Approved feature/QA pass | Owner | Staging → Production |
| Emergency window | Security incident | Owner (documented) | Production |

## 2. Roles & Responsibilities

| Role | Responsibility |
|---|---|
| Release Manager | Coordinates the steps below; is the single approver in-flight |
| Developer | Fixes defects found in verification |
| QA/Test Engineer | Runs smoke tests; confirms acceptance |
| Owner (project owner) | Final go/no-go approval (3.9 §43) |

## 3. Pre-Requisites (before any release)

- [ ] Git baseline exists with protected `main` (3.9 §19/§22) — zero-commit repo today
- [ ] CI green on release tag (lint, unit tests, security checks)
- [ ] Staging was verified with the same SHA being released
- [ ] Backup of production DB successfully restored within RPO/RTO targets in a drill (≤ 30 days old)
- [ ] Secrets for the release rotated/available in secret manager
- [ ] Rollback image/tag identified (previous release retained)

---

## 4. Deployment Sequence (the future run)

### Step 0 — Verify Release
1. Confirm the release tag name/hash (`vX.Y.Z-<git-sha>`).
2. Confirm the diff for this release is approved and recorded.
3. Confirm staging acceptance was signed off for this exact SHA.

### Step 1 — Backup Database
1. Take an encrypted logical backup (pg_dump) of production.
2. Verify checksum + take a filesystem-level snapshot if applicable.
3. Record backup name/location; confirm a restore path exists.
   * Migrations that alter schema must have a dedicated pre-migration backup
     (3.9 §13/§27).

### Step 2 — Verify Staging
1. Deploy same tag to staging (parity config).
2. Run the full smoke suite (3.9 §40) against staging.
3. Resolve and re-test any failure **before** production.

### Step 3 — Approve Release
1. Release Manager presents: tag, CI evidence, staging evidence, rollback plan.
2. Project owner gives explicit go/no-go.
3. Record approval (name + timestamp) in the release log (BR-012 audit).

### Step 4 — Prepare Infrastructure
1. Confirm firewall, DNS, TLS unchanged/intact.
2. Pull new images to prod host; verify checksums/digests.
3. Rotate any credentials required by this release (if any).

### Step 5 — Deploy Backend
1. Roll out new backend image with graceful stop (SIGTERM drain).
2. Keep previous image tag available (rollback).

### Step 6 — Run Migrations (if approved & not backfilled)
1. Execute ONLY approved migration steps.
2. `migrate --plan` review logged.
3. No combined code+schema release that cannot be rolled back (expanded/contract
   pattern as needed, 3.9 §13/§29 — see DB migration strategy).

### Step 7 — Deploy Static / Admin Assets
1. `collectstatic` (new assets) → nginx/CDN; cache-busted hashed filenames.
2. Build + deploy Admin Web bundle.

### Step 8 — Restart / Reload Services
1. Reload nginx (no downtime), restart workers in a rolling fashion.

### Step 9 — Run Health Checks
1. `/livez` and `/healthz` from the proxy.
2. DB connectivity, worker heartbeat, external dependency probes.

### Step 10 — Run Smoke Tests (3.9 §40)
1. API health & version endpoint.
2. Database connectivity check.
3. Authentication: login with safe test account (MFA if applicable).
4. Registration flow with throwaway test account.
5. Doctor verification workflow (staged docs).
6. Blood request flow.
7. Emergency request flow.
8. Donation workflow.
9. Notification (email/SMS/FCM) — delivery to test device.
10. Admin access + permission checks (role-limited).

### Step 11 — Verify Database
1. Row counts / audit trail intact; new migrations applied as expected.
2. `security_events`/`audit_logs` recording for the release actions.

### Step 12 — Verify Authentication
1. Refresh rotation still works; old refresh tokens behave per 3.8 §31.
2. MFA step-up paths (admin role ops, refunds, emergency) functional.

### Step 13 — Verify Critical APIs
1. Key patient/billing/webhook endpoints return expected status.
2. Rate limit headers present.

### Step 14 — Verify Payment Callbacks
1. Send a **test** callback (sandbox/self-test) and confirm signature+nonce
   +idempotency handling (3.8 §22).
2. Re-send the same callback → no duplicate charge processing.

### Step 15 — Verify Notifications
1. Send a test push + email + SMS.
2. Confirm logging and no PHI in payloads.

### Step 16 — Monitor
1. Watch dashboards for 30–60 min: error rate, latency p95, queue backlog.
2. Confirm no error spike in Sentry/logs.

### Step 17 — Declare Release Successful
1. Record release in release log (SHA, DB version, backups, approval, evidence).
2. Update runbook with lessons learned.

---

## 5. Rollback Triggers & Immediate Actions

Trigger any rollback when (3.9 §29):

* Health checks fail post-deploy.
* Smoke tests fail on core flows.
* Error rate/latency exceeds alert threshold for >10 min.
* Data integrity anomaly detected.

Actions:
1. Halt feature flag / re-point to previous backend image tag (static,
   backward-compatible schema releases only — else follow migration rollback
   step in `deployment-design.md` §13).
2. Restore DB only from the Step-1 pre-release backup if schema rollback
   required (accepting data-loss window per documented plan).
3. Redeploy Admin Web previous build.
4. Full re-verification (Steps 9–15) before declaring recovery.

## 6. Post-Release Checklist

- [ ] Logs/dashboards reviewed; alerts silenced only when resolved
- [ ] Backup verified post-release (new backup of new state)
- [ ] Release documented; tag immutable
- [ ] Owner notified of the final status
- [ ] Any created developer/ops access revoked (least privilege, §43)

---

## 7. Out-of-Scope (explicitly not part of this stage)

* Executing this runbook for production (Stage 5/launch activity).
* Automating every step (CI/CD covers Steps 0-4 partially; approvals remain human).
* Emergency incident handling details → `deployment-design.md` §38 (3.8 §38).

---

_End of deployment-runbook.md (3.9 companion). Reference only; not executed now._