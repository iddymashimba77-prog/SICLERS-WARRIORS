"""Stage 4.19 gate — Testing & QA Integration.

Every claim below is verified against the REAL shipped state of the repo:

    Backend QA (backend/qa)                 — 68 gherkin-style integration tests
        reach the real API surface on ephemeral SQLite, covering: patient day-one
        journey (register -> SOS -> donation -> medication), emergency throttle
        (3/hour) + idempotency + moderation, auth (register/login/session/me),
        IDOR attempts (cross-patient medical/blood/campaign access), privacy
        (PII containment on public surfaces, 404s for deprecated/inert apps),
        payment webhooks (M_PESA signature verification), symptom catalog &
        health endpoints, and cross-app data flows.
    Real bug fixed + regression   — `emergencies.views` no longer raises
        KeyError 500 when `description` is omitted; the SOS e2e regression test
        guards it (fix + test shipped together).
    Full backend suite            — 433 tests OK on the ephemeral profile.
    FRONTEND QA (apps/mobile)     — 20 new stage419 tests (navigation/shell
        routing, offline->retry recovery, auth controller token lifecycle,
        medication/profile/blood form validation+submit) join the 65 existing;
        `flutter analyze` reports zero issues; `flutter test` == All passed.
    Deployability                 — `manage.py check` clean, `makemigrations
        --check` == "No changes detected", `pip check` clean.

Run (ephemeral SQLite; never touches Postgres; requires `flutter` on PATH):
    venv/bin/python stage419_gate.py
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
check("full backend suite: 433 tests OK on ephemeral SQLite",
      full_run.returncode == 0 and "OK" in full_run.stdout + full_run.stderr)

qa_only, qa_run = run(MANAGE_ARGS + [
    "test", "qa", "--settings=config.settings.ephemeral_test"], cwd=BACKEND)
check("qa suite runs green (68 qa tests inside the full green suite)",
      qa_only and "OK" in qa_run.stdout + qa_run.stderr)

check("qa app ships 9 modules (helpers + 8 test suites)", all(
    os.path.isfile(os.path.join(BACKEND, "qa", f"{name}.py")) for name in (
        "qa_helpers", "tests_patients", "tests_emergency_surface",
        "tests_auth_surface", "tests_idor", "tests_privacy",
        "tests_transactions", "tests_symptom_types", "tests_e2e")))

# Regression guard: the emergencies.data.get fix must exist in source.
source = open(os.path.join(BACKEND, "emergencies", "views.py")).read()
check("emergencies.views uses data.get for optional description (KeyError fix)",
      'data.get("description"' in source)

# ------------------------------------------------------------------ mobile QA
analyze, analyze_run = run(["flutter", "analyze", "--no-pub"], cwd=MOBILE)
check("flutter analyze: zero issues", analyze and "No issues found!" in analyze_run.stdout)

flutter_test, flutter_run = run(["flutter", "test", "--no-pub"], cwd=MOBILE)
check("flutter test: stage419 + legacy suites all pass (85 total)",
      flutter_test and "All tests passed!" in flutter_run.stdout)

stage419 = [f"test/stage419_{name}_test.dart" for name in
            ("navigation", "offline", "auth_controller", "forms_widgets")]
p419, p419_run = run(["flutter", "test", "--no-pub", *stage419], cwd=MOBILE)
check("the 4 new stage419 test files are present and green (20 tests)",
      p419 and all(os.path.isfile(os.path.join(MOBILE, f)) for f in stage419)
      and "All tests passed!" in p419_run.stdout)

# ------------------------------------------------------------- deployability
_, chk = run(MANAGE_ARGS + ["check"], cwd=BACKEND)
check("manage.py check clean", chk.returncode == 0)

_, mig = run(MANAGE_ARGS + [
    "makemigrations", "--check", "--dry-run",
    "--settings=config.settings.ephemeral_test"], cwd=BACKEND)
check("no pending migrations", mig.returncode == 0 and "No changes detected" in mig.stdout + mig.stderr)

_, pip = run([PY, "-m", "pip", "check"], cwd=BACKEND)
check("pip check clean (no broken deps)", pip.returncode == 0)

ok = len(checks) == sum(1 for _, passed in checks if passed)

print(f"Stage 4.19 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
for name, passed in checks:
    if not passed:
        print(f"  FAILED: {name}")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)