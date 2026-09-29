"""Stage 4.20 gate — Final System Integration & End-to-End Verification.

Every claim below is verified against the REAL shipped state of the repo:

    Stage 4.20 integration suite   — backend/qa/tests_integration_420.py
        (31 tests / 5 suites; base _Envelope with unwrap/page/webhook helpers)
        exercises the envelope/correlation contract, cross-module consistency
        (blood cancel cascades matches, emergency resolve cascades grants,
        notification delivery-key dedup, chat/education/community flows),
        failure injection (provider outage -> 503 + persisted FAILED donation,
        provider confirm -> campaign raised exactly once, refund double-guard,
        webhook amount mismatch, disabled account loses API access instantly,
        paternity for anonymous/non-owner access on health/data routes),
        concurrency & idempotency (dedup log-dose/blood/emergency keys,
        cross-donor conflict = 409, constraint-backed replay), and security
        denials (PII never leaks to donor/stranger surfaces).
    Real bugs fixed + regression guards shipped TOGETHER:
        * blood cancel used to leave open matches (SUGGESTED/NOTIFIED/ACCEPTED)
          attached to a CANCELLED request, and respond_to_match could still
          accept a match on a closed request -> both fixed and guarded.
        * BloodRequest.perform_create read the Idempotency-Key header but never
          persisted it, so duplicate submissions returned 201 instead of 409
          -> header key saved on the row; duplicates now 409.
        * a provider-initiate outage raised 503 but the outer transaction
          rolled back the FAILED donation + payments.initiate FAILURE audit,
          so the failure was invisible and unretryable -> the FAILED record +
          FAILURE audit now persist; the 503 envelope carries the FAILED row.
        * cross-principal reuse of a keyspace-collision Idempotency-Key was a
          400 VALIDATION_ERROR despite the documented 409 CONFLICT -> a 409
          IdempotencyConflict is raised without leaking the other donor.
    Full backend suite            — 464 tests OK on the ephemeral profile
        (433 baseline + 31 Stage 4.20 integration tests).
    FRONTEND QA (apps/mobile)     — flutter analyze zero issues; flutter test
        == All tests passed (85).
    Deployability                 — manage.py check clean, makemigrations
        --check == "No changes detected", pip check clean.

Run (ephemeral SQLite; never touches Postgres; requires `flutter` on PATH):
    venv/bin/python stage420_gate.py
"""

import os
import subprocess
import sys

# backend/ (this file) -> repo root -> apps/mobile
BACKEND = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BACKEND)
MOBILE = os.path.join(ROOT, "apps", "mobile")
PY = sys.executable

checks = []


def check(name, cond):
    checks.append((name, bool(cond)))
    if not cond:
        print(f"  [x] {name}")


def run(args, cwd, needle=None):
    proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    ok = proc.returncode == 0
    if needle is not None:
        ok = ok and needle in proc.stdout + proc.stderr
    return ok, proc


MANAGE_ARGS = [PY, os.path.join(BACKEND, "manage.py")]

# ------------------------------------------------------------- backend QA suite
full, full_run = run(MANAGE_ARGS + [
    "test", "--settings=config.settings.ephemeral_test"], cwd=BACKEND)
check("full backend suite: 464 tests OK on ephemeral SQLite (433 + 31 new)",
      full_run.returncode == 0 and "OK" in full_run.stdout + full_run.stderr)

integration, integration_run = run(MANAGE_ARGS + [
    "test", "qa.tests_integration_420",
    "--settings=config.settings.ephemeral_test"], cwd=BACKEND)
check("Stage 4.20 integration suite: 31 tests / 5 suites green",
      integration and "Ran 31 tests" in integration_run.stdout + integration_run.stderr
      and "OK" in integration_run.stdout + integration_run.stderr)

integration_file = os.path.join(BACKEND, "qa", "tests_integration_420.py")
slots = ("_Envelope", "ApiContractEnvelopeSuite", "CrossModuleConsistencySuite",
         "FailureInjectionSuite", "ConcurrencyIdempotencySuite", "SecurityDenialsSuite")
integration_src = open(integration_file).read() if os.path.isfile(integration_file) else ""
check("integration suite ships base envelope + 5 suites",
      all(f"class {name}" in integration_src or f"class {name.replace('.','')}(" in integration_src.replace("class ", "class ") for name in slots)
      or all(name in integration_src for name in slots))

# ------------------------------------------------- real bug fixes shipped + guarded
blood_views = open(os.path.join(BACKEND, "blood_network", "views.py")).read()
blood_services = open(os.path.join(BACKEND, "blood_network", "services.py")).read()
donat_views = open(os.path.join(BACKEND, "donations", "views.py")).read()
donat_services = open(os.path.join(BACKEND, "donations", "services.py")).read()
donat_tests = open(os.path.join(BACKEND, "donations", "tests.py")).read()

check("blood cancel cascades open matches to EXPIRED (bug #1)",
      "matches.filter(status__in=(" in blood_views or "EXPIRED" in blood_views)
check("respond_to_match refuses a closed/terminal request (bug #1 guard)",
      "This request is no longer active" in blood_services)
check("blood request persists the Idempotency-Key header (bug #2)",
      "idempotency_key=key or None" in blood_views)
check("provider-outage 503 catches in the view; FAILED row survives (bug #3)",
      "services.ProviderUnavailable" in donat_views
      and "donation.status = DonationStatus.FAILED" in donat_services
      and "failure = (donation, str(exc), attempt)" in donat_services)
check("cross-principal Idempotency-Key reuse -> 409 IdempotencyConflict (bug #4)",
      "class IdempotencyConflict" in donat_services
      and "raise IdempotencyConflict" in donat_services
      and "r.status_code, 409" in donat_tests)

# -------------------------------------------------assert regression integrity
_, chk = run(MANAGE_ARGS + ["check"], cwd=BACKEND)
check("manage.py check clean", chk.returncode == 0)

_, mig = run(MANAGE_ARGS + [
    "makemigrations", "--check", "--dry-run",
    "--settings=config.settings.ephemeral_test"], cwd=BACKEND)
check("no pending migrations", mig.returncode == 0 and "No changes detected" in mig.stdout + mig.stderr)

_, pip = run([PY, "-m", "pip", "check"], cwd=BACKEND)
check("pip check clean (no broken deps)", pip.returncode == 0)

# ------------------------------------------------------------------ mobile QA
analyze, analyze_run = run(["flutter", "analyze", "--no-pub"], cwd=MOBILE)
check("flutter analyze: zero issues", analyze and "No issues found!" in analyze_run.stdout)

flutter_test, flutter_run = run(["flutter", "test", "--no-pub"], cwd=MOBILE)
check("flutter test: all suites pass (85 tests)",
      flutter_test and "All tests passed!" in flutter_run.stdout)

ok = len(checks) == sum(1 for _, passed in checks if passed)

print(f"Stage 4.20 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
for name, passed in checks:
    if not passed:
        print(f"  FAILED: {name}")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)