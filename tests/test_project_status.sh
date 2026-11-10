#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)" && [ -n "$TMP" ] && [ -d "$TMP" ] || { echo "cannot create a temp directory" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

PS="$REPO/scripts/project-status.sh"

if [ ! -f "$PS" ]; then
  fail "project-status entry exists"
  finish
  exit 1
fi

STAMP="$( . "$REPO/bootstrap/lib/stamp.sh"; compute_stamp "$REPO/bootstrap/directive.md" )"
onboard_stamp() { printf 'skill-commons-stamp: %s\n' "$STAMP" > "$1/AGENTS.md"; }

make_item() { # work-root slug work-status delivery-status implement-stage-status
  local root="$1" slug="$2" work_status="$3" delivery_status="$4" stage_status="$5"
  mkdir -p "$root/$slug"
  printf '# %s implementation\n' "$slug" > "$root/$slug/implement-report.md"
  cat > "$root/$slug/meta.yml" <<EOF
schema_version: work-item/v3
slug: $slug
title: $slug fixture
created_at: 2026-07-15T00:00:00Z
updated_at: 2026-07-15T00:01:00Z
execution_mode: bug-fix
work_status: $work_status
delivery_status: $delivery_status
stages:
  implement: { skill: implement, file: implement-report.md, status: $stage_status }
inputs:
  - fixture
EOF
}

make_canonical_item() { # work-root slug
  local root="$1" slug="$2"
  mkdir -p "$root/$slug/plan"
  printf '# %s implementation\n' "$slug" > "$root/$slug/implement-report.md"
  cat > "$root/$slug/meta.yml" <<EOF
schema_version: work-item/v3
slug: $slug
title: $slug canonical fixture
created_at: 2026-07-15T00:00:00Z
updated_at: 2026-07-15T00:01:00Z
execution_mode: bug-fix
work_status: active
delivery_status: not_requested
stages:
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
  implement: { skill: implement, file: implement-report.md, status: in_progress }
inputs:
  - fixture
EOF
  cat > "$root/$slug/plan/plan.md" <<EOF
# Plan: $slug

## Plan

- Format: canonical-v2
- Concurrency: 1
- Intent: Exercise canonical project status.
- Scope: One fixture task.
- Non-goals: No external delivery.

## Sources

- user: project-status-fixture

## Tasks

### T01 | fixture-task

- Status: in_progress
- Depends On: []

#### Intent

Exercise the plan status adapter.

#### Expected Result

The active task is reported deterministically.

#### Definition of Done

- The adapter reports T01.

#### Verification

- bash verify.sh

## Change Log

- 2026-07-15T00:00:00Z: Created fixture.
EOF
}

echo "project-status v3 contract"

# Bootstrap classification is exercised with a bounded subprocess mock. The
# real source probe builds all three generated roots and belongs to the final
# serialized verification, not this focused fixture suite.
MOCK_CHECK="$TMP/mock-check.sh"
MOCK_SOURCE="$TMP/mock-source"
MOCK_CONSUMER="$TMP/mock-consumer"
mkdir -p "$MOCK_SOURCE" "$MOCK_CONSUMER"
: > "$MOCK_CHECK"
BOOTSTRAP_PROBES="$(python3 - "$REPO/scripts/project_status.py" "$MOCK_CHECK" "$MOCK_SOURCE" "$MOCK_CONSUMER" <<'PY'
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

module_path = Path(sys.argv[1]).resolve()
check_path = Path(sys.argv[2]).resolve()
source_root = Path(sys.argv[3]).resolve()
consumer_root = Path(sys.argv[4]).resolve()
spec = importlib.util.spec_from_file_location("project_status_probe_fixture", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
module.CHECK_SH = check_path
module.REPO_ROOT = source_root

def run_case(project_root, returncode, stdout):
    calls = []

    def fake_run(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, returncode, stdout, "")

    original_run = module.subprocess.run
    module.subprocess.run = fake_run
    try:
        result = module.probe_bootstrap(project_root)
    finally:
        module.subprocess.run = original_run
    return {"result": result, "command": calls[0]}

payload = {
    "source_clean": run_case(source_root, 0, ""),
    "source_attention": run_case(
        source_root,
        0,
        "⚠️ maintainer generated root missing ownership ledger: .claude/skills/.skill-commons-ownership-v1; run: PROFILE=all bash bootstrap/generate.sh\n"
        "⚠️ maintainer generated content is stale in .codex/skills: stale/SKILL.md; run: PROFILE=all bash bootstrap/generate.sh\n"
        "⚠️ maintainer generated root contains retired owner output in .agents/skills: ponytail; run: PROFILE=all bash bootstrap/generate.sh\n",
    ),
    "source_operational_warning": run_case(
        source_root,
        0,
        "⚠️ maintainer source health check could not build an expected payload; run: PROFILE=all bash bootstrap/generate.sh\n",
    ),
    "source_nonzero": run_case(source_root, 7, ""),
    "consumer_drift": run_case(
        consumer_root,
        0,
        "⚠️ configuration is out of date (stamp 000000000000 ≠ abcdef123456); run: bash bootstrap/onboard.sh\n",
    ),
}
expected_states = {
    "source_clean": "PASS",
    "source_attention": "attention",
    "source_operational_warning": "unknown",
    "source_nonzero": "unknown",
    "consumer_drift": "attention",
}
for name, expected_state in expected_states.items():
    actual_state = payload[name]["result"]["state"]
    assert actual_state == expected_state, (name, expected_state, actual_state)
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
)"
bootstrap_probe_rc=$?
assert_eq "0" "$bootstrap_probe_rc" "bounded bootstrap probe fixture completes"
assert_contains "$BOOTSTRAP_PROBES" '"source_clean": {"command": ["bash"' "source probe invokes bootstrap/check.sh"
bootstrap_state() {
  printf '%s' "$BOOTSTRAP_PROBES" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["result"]["state"])' "$1"
}
assert_eq "PASS" "$(bootstrap_state source_clean)" "clean source health is PASS"
assert_eq "attention" "$(bootstrap_state source_attention)" "maintainer generated-root warnings are attention"
assert_eq "unknown" "$(bootstrap_state source_operational_warning)" "source operational warning is unknown"
assert_eq "unknown" "$(bootstrap_state source_nonzero)" "nonzero bootstrap subprocess is unknown"
assert_eq "attention" "$(bootstrap_state consumer_drift)" "consumer stamp drift remains attention"
assert_contains "$BOOTSTRAP_PROBES" '"detail": "maintainer source health requires attention"' "source health warning detail is actionable"
assert_contains "$BOOTSTRAP_PROBES" '"detail": "maintainer source health check failed operationally"' "source operational warning is unknown"
assert_contains "$BOOTSTRAP_PROBES" '"detail": "bootstrap check failed (exit status 7)"' "nonzero bootstrap subprocess is unknown"
assert_contains "$BOOTSTRAP_PROBES" '"detail": "bootstrap configuration is stale (stamp drift)"' "consumer stamp drift remains attention"

# Two active work items must remain ambiguous without guessing a primary item.
MROOT="$TMP/multi"
MWORK="$MROOT/docs/work"
mkdir -p "$MWORK"
make_item "$MWORK" alpha active not_requested in_progress
make_item "$MWORK" beta active not_requested in_progress

bash "$PS" --project-root "$MROOT" --work-root "$MWORK" --json > "$TMP/multi-1.json" 2> "$TMP/multi-1.err"
multi_rc=$?
bash "$PS" --project-root "$MROOT" --work-root "$MWORK" --json > "$TMP/multi-2.json" 2> "$TMP/multi-2.err"
assert_eq "0" "$multi_rc" "v3 multi-active fixture exits zero"
if diff -q "$TMP/multi-1.json" "$TMP/multi-2.json" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS + 1)); echo "  ok: v3 JSON is byte-identical"
else
  fail "v3 JSON is byte-identical"
fi
MULTI="$(cat "$TMP/multi-1.json")"
assert_contains "$MULTI" '"schema_version": 3' "project-status emits the schema with verification fields"
assert_contains "$MULTI" '"work_status": "active"' "work status is explicit"
assert_contains "$MULTI" '"delivery_status": "not_requested"' "delivery status is explicit"
assert_contains "$MULTI" '"multiple_active": true' "multiple active work is attention"
assert_contains "$MULTI" '"status": "attention"' "ambiguity contributes attention"
assert_not_contains "$MULTI" "primary" "project-status does not guess a primary item"
assert_not_contains "$MULTI" "$TMP" "JSON contains no host temp path"

SELECTED="$(bash "$PS" --project-root "$MROOT" --work-root "$MWORK" --slug alpha --json)"
assert_contains "$SELECTED" '"selected_slug": "alpha"' "active slug selection is explicit"
assert_contains "$SELECTED" '"multiple_active": false' "active slug resolves ambiguity"

# Canonical plan state comes from planctl, not the retired validator contract.
CROOT="$TMP/canonical"
CWORK="$CROOT/docs/work"
mkdir -p "$CWORK"
onboard_stamp "$CROOT"
make_canonical_item "$CWORK" canonical
CANONICAL="$(bash "$PS" --project-root "$CROOT" --work-root "$CWORK" --slug canonical --json)"
assert_contains "$CANONICAL" '"mode": "canonical"' "canonical plan mode is reported"
assert_contains "$CANONICAL" '"plan_state": "running"' "planctl running state is preserved"
assert_contains "$CANONICAL" '"active_task": "T01"' "planctl active task is preserved"
assert_contains "$CANONICAL" '"next_action": "continue canonical: T01: fixture-task"' "canonical executable task is the continuation hint"

# An active work item without a plan is uncertain, even when bootstrap is healthy.
NPROOT="$TMP/no-plan"
NPWORK="$NPROOT/docs/work"
mkdir -p "$NPWORK"
onboard_stamp "$NPROOT"
make_item "$NPWORK" no-plan active not_requested in_progress
NO_PLAN="$(bash "$PS" --project-root "$NPROOT" --work-root "$NPWORK" --slug no-plan --json)"
no_plan_state="$(printf '%s' "$NO_PLAN" | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')"
assert_eq "unknown" "$no_plan_state" "active item with no plan contributes unknown globally"
assert_contains "$NO_PLAN" '"state": "unknown"' "active item exposes its unknown plan state"

# A consuming root with an AGENTS.md but no managed stamp is not bootstrap PASS.
UROOT="$TMP/unstamped"
UWORK="$UROOT/docs/work"
mkdir -p "$UWORK"
printf '# unrelated project instructions\n' > "$UROOT/AGENTS.md"
make_canonical_item "$UWORK" unstamped
UNSTAMPED="$(bash "$PS" --project-root "$UROOT" --work-root "$UWORK" --slug unstamped --json)"
unstamped_bootstrap="$(printf '%s' "$UNSTAMPED" | python3 -c 'import json,sys;print(json.load(sys.stdin)["probes"]["bootstrap"]["state"])')"
assert_eq "unknown" "$unstamped_bootstrap" "unstamped consuming shim is not bootstrap PASS"

# A consuming root with a stale managed stamp remains bootstrap attention.
DROOT="$TMP/drift"
mkdir -p "$DROOT"
printf 'skill-commons-stamp: 000000000000\n' > "$DROOT/AGENTS.md"
DRIFT="$(bash "$PS" --project-root "$DROOT" --json)"
drift_bootstrap="$(printf '%s' "$DRIFT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["probes"]["bootstrap"]["state"])')"
assert_eq "attention" "$drift_bootstrap" "stamped consuming shim drift remains attention"
assert_contains "$DRIFT" '\u2260' "stamp drift warning remains visible"

# Invalid v3 metadata drives the global invalid state.
BROOT="$TMP/bad"
BWORK="$BROOT/docs/work"
mkdir -p "$BWORK/broken"
cat > "$BWORK/broken/meta.yml" <<EOF
slug: broken
title: missing v3 stamp
created_at: 2026-07-15T00:00:00Z
updated_at: 2026-07-15T00:01:00Z
status: active
stages:
  implement: { skill: implement, file: missing.md, status: done }
inputs:
  - fixture
EOF
BAD="$(bash "$PS" --project-root "$BROOT" --work-root "$BWORK" --json)"
assert_contains "$BAD" '"status": "invalid"' "invalid v3 metadata drives invalid"
assert_contains "$BAD" '"broken"' "invalid item remains identifiable"

# Completed historical work is listed but its deliberately invalid plan is not assessed.
HROOT="$TMP/history"
HWORK="$HROOT/docs/work"
mkdir -p "$HWORK"
onboard_stamp "$HROOT"
make_item "$HWORK" current active not_requested in_progress
make_item "$HWORK" past completed not_requested done
mkdir -p "$HWORK/past/plan"
printf '# invalid historical plan\n' > "$HWORK/past/plan/plan.md"
HISTORY="$(bash "$PS" --project-root "$HROOT" --work-root "$HWORK" --json)"
assert_contains "$HISTORY" '"slug": "past"' "completed history remains visible"
assert_contains "$HISTORY" '"work_status": "completed"' "completed work status is retained"
assert_not_contains "$HISTORY" '"status": "invalid"' "historical invalid plan does not drive current state"

# Unknown or completed slugs cannot silently change active orientation.
bash "$PS" --project-root "$HROOT" --work-root "$HWORK" --slug ghost --json > "$TMP/ghost.json" 2>/dev/null
ghost_rc=$?
assert_eq "2" "$ghost_rc" "unknown slug exits 2"
assert_contains "$(cat "$TMP/ghost.json")" '"status": "invalid"' "unknown slug emits invalid"
bash "$PS" --project-root "$HROOT" --work-root "$HWORK" --slug past --json > "$TMP/past.json" 2>/dev/null
past_rc=$?
assert_eq "2" "$past_rc" "completed slug is rejected as an active orientation target"

# A default missing docs/work is a valid empty project/public-payload state.
EROOT="$TMP/empty"
mkdir -p "$EROOT"
bash "$PS" --project-root "$EROOT" --json > "$TMP/empty.json" 2> "$TMP/empty.err"
empty_rc=$?
assert_eq "0" "$empty_rc" "default missing work root is treated as empty"
assert_contains "$(cat "$TMP/empty.json")" '"total": 0' "empty work root reports zero items"

# An explicitly requested bad work root and a path outside the project still fail closed.
bash "$PS" --project-root "$EROOT" --work-root "$EROOT/missing" --json >/dev/null 2> "$TMP/missing.err"
explicit_missing_rc=$?
assert_eq "2" "$explicit_missing_rc" "explicit missing work root exits 2"
assert_not_contains "$(cat "$TMP/missing.err")" "$TMP" "missing-root stderr contains no host absolute path"
mkdir -p "$TMP/outside/docs/work"
bash "$PS" --project-root "$EROOT" --work-root "$TMP/outside/docs/work" --json >/dev/null 2> "$TMP/outside.err"
outside_rc=$?
assert_eq "2" "$outside_rc" "outside work root exits 2"
assert_contains "$(cat "$TMP/outside.err")" "inside project root" "outside-root error is actionable"
assert_not_contains "$(cat "$TMP/outside.err")" "$TMP" "outside-root stderr contains no host absolute path"

# Wrapper/direct output parity and read-only bytecode behavior.
PYC="$REPO/scripts/__pycache__"
pyc_before="$(ls "$PYC" 2>/dev/null | sort)"
python3 "$REPO/scripts/project_status.py" --project-root "$MROOT" --work-root "$MWORK" --json > "$TMP/direct.json"
pyc_after="$(ls "$PYC" 2>/dev/null | sort)"
assert_eq "$pyc_before" "$pyc_after" "read-only command adds no bytecode residue"
if diff -q "$TMP/direct.json" "$TMP/multi-1.json" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS + 1)); echo "  ok: wrapper and direct output are identical"
else
  fail "wrapper and direct output are identical"
fi

# A plan that declares a participant repo reports it; one that declares none is
# unchanged. Participants come from the plan's Sources only, so status never grows
# a second place to record where the other repo is.
PROOT="$TMP/participants"
PWORK="$PROOT/docs/work"
mkdir -p "$PWORK" "$PROOT/.git"
git init -q "$TMP/participant-repo" >/dev/null 2>&1
onboard_stamp "$PROOT"
make_canonical_item "$PWORK" shared
perl -0pi -e 's#- user: project-status-fixture#- user: project-status-fixture\n- repo: sibling\@../participant-repo#' \
  "$PWORK/shared/plan/plan.md"
PARTICIPANTS="$(bash "$PS" --project-root "$PROOT" --work-root "$PWORK" --slug shared --json)"
assert_contains "$PARTICIPANTS" '"participants": [' "declared participants reach the status payload"
assert_contains "$PARTICIPANTS" '"sibling"' "the declared participant identifier is reported"
PARTICIPANTS_TEXT="$(bash "$PS" --project-root "$PROOT" --work-root "$PWORK" --slug shared)"
assert_contains "$PARTICIPANTS_TEXT" "participants=sibling" "text output names the participant"
NO_PARTICIPANTS_TEXT="$(bash "$PS" --project-root "$CROOT" --work-root "$CWORK" --slug canonical)"
assert_not_contains "$NO_PARTICIPANTS_TEXT" "participants=" "a plan with no participant is unchanged"

# Finished cross-repo work stays visible in one place: a completed item still
# reports the participants its canonical plan declares. Its plan state remains
# unassessed, so history still cannot drive current orientation.
FROOT="$TMP/finished-participants"
FWORK="$FROOT/docs/work"
mkdir -p "$FWORK" "$FROOT/.git"
git init -q "$TMP/finished-participant-repo" >/dev/null 2>&1
onboard_stamp "$FROOT"
make_canonical_item "$FWORK" finished
perl -0pi -e 's#- user: project-status-fixture#- user: project-status-fixture\n- repo: retired-sibling\@../finished-participant-repo#' \
  "$FWORK/finished/plan/plan.md"
perl -0pi -e 's#^work_status: active$#work_status: completed#m; s#status: in_progress \}#status: done }#' \
  "$FWORK/finished/meta.yml"
FINISHED="$(bash "$PS" --project-root "$FROOT" --work-root "$FWORK" --json)"
assert_contains "$FINISHED" '"work_status": "completed"' "the finished fixture is completed work"
assert_contains "$FINISHED" '"retired-sibling"' "a completed item still reports its declared participant"
assert_contains "$FINISHED" '"assessed": false' "a completed item's plan state stays unassessed"
FINISHED_TEXT="$(bash "$PS" --project-root "$FROOT" --work-root "$FWORK")"
assert_contains "$FINISHED_TEXT" "participants=retired-sibling" "text output names a completed item's participant"

# A declared participant that cannot be resolved must be reported, not dropped:
# the identity comes from the declaration, so a missing checkout is visible in
# both surfaces instead of collapsing to `participants: []` with no error.
UPROOT="$TMP/unreadable-participant"
UPWORK="$UPROOT/docs/work"
mkdir -p "$UPWORK" "$UPROOT/.git"
onboard_stamp "$UPROOT"
make_canonical_item "$UPWORK" orphaned
perl -0pi -e 's#- user: project-status-fixture#- user: project-status-fixture\n- repo: gone\@../absent-repo#' \
  "$UPWORK/orphaned/plan/plan.md"
perl -0pi -e 's#^work_status: active$#work_status: completed#m; s#status: in_progress \}#status: done }#' \
  "$UPWORK/orphaned/meta.yml"
UNREADABLE="$(bash "$PS" --project-root "$UPROOT" --work-root "$UPWORK" --json)"
assert_contains "$UNREADABLE" '"gone"' "an unreadable participant keeps its declared identity in JSON"
assert_contains "$UNREADABLE" "does not exist" "an unreadable participant is reported in JSON"
UNREADABLE_TEXT="$(bash "$PS" --project-root "$UPROOT" --work-root "$UPWORK")"
assert_contains "$UNREADABLE_TEXT" "participants=gone" "text output keeps the unreadable participant's identity"
assert_contains "$UNREADABLE_TEXT" "does not exist" "text output reports the unreadable participant"
assert_not_contains "$UNREADABLE" "$TMP" "unreadable-participant report leaks no host path"


# ── T04: verification evidence bound to content ─────────────────────────────
# verify.sh records the test result with a content fingerprint; project-status
# marks a completed, undelivered item stale when the fingerprinted files change.
VE="$TMP/verify-evidence"
mkdir -p "$VE/src" "$VE/tests" "$VE/.agent" "$VE/docs/work"
git -C "$VE" init -q
printf 'def add(a, b):\n    return a + b\n' > "$VE/src/app.py"
cat > "$VE/tests/test_app.py" <<'EOF'
import sys, unittest
sys.path.insert(0, "src")
from app import add
class T(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(1, 2), 3)
EOF
cat > "$VE/.agent/project-manifest.md" <<'EOF'
## Paths
- work_root: docs/work
- source_roots: src
- tests_root: tests

## Stack
- test_cmd: `python3 -B -m unittest discover -s tests`
- has_ui: false
- has_api: false
- typed_contracts: false
- has_e2e: false
EOF
make_done_item() { # slug updated_at
  mkdir -p "$VE/docs/work/$1"
  printf '# %s\n' "$1" > "$VE/docs/work/$1/implement-report.md"
  cat > "$VE/docs/work/$1/meta.yml" <<EOF
schema_version: work-item/v3
slug: $1
title: $1 fixture
created_at: $2
updated_at: $2
execution_mode: bug-fix
work_status: completed
delivery_status: awaiting_approval
documentation_impact: n/a:fixture
stages:
  implement: { skill: implement, file: implement-report.md, status: done }
inputs:
  - fixture
EOF
}
make_done_item done-item 2026-10-30T10:00:00Z
make_done_item no-evidence 2026-10-30T10:00:00Z
make_done_item legacy-item 2026-07-15T00:00:00Z
git -C "$VE" add -A && git -C "$VE" -c user.name=t -c user.email=t@example.invalid commit -q -m fixture

VERIFY="$REPO/verification-before-completion/scripts/verify.sh"
verify_out="$(cd "$VE" && bash "$VERIFY" --work-item done-item 2>&1)"; verify_rc=$?
assert_eq "0" "$verify_rc" "verify.sh passes on the fixture"
assert_file "$VE/docs/work/done-item/verification.json" "verify.sh writes verification evidence into the work item"
evidence="$(cat "$VE/docs/work/done-item/verification.json" 2>/dev/null)"
assert_contains "$evidence" '"result": "pass"' "evidence records a passing result"
assert_contains "$evidence" '"digest"' "evidence records a content fingerprint"

ve_state() { # slug [extra args]
  (cd "$VE" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c '
import json, sys
slug = sys.argv[1]
for item in json.load(sys.stdin)["work_items"]:
    if item["slug"] == slug:
        print(item["verification"]["state"])' "$1"
}
assert_eq "current" "$(ve_state done-item)" "unchanged content keeps the evidence current"
assert_eq "unknown" "$(ve_state no-evidence)" "a completed item without evidence is unknown, not PASS"
assert_eq "unbound" "$(ve_state legacy-item)" "items completed before the cutoff are unbound"

before_status="$(git -C "$VE" status --porcelain)"
printf 'def add(a, b):\n    return a - b\n' > "$VE/src/app.py"
assert_eq "stale" "$(ve_state done-item)" "a source change after verification makes it stale"
ve_json="$(cd "$VE" && python3 "$REPO/scripts/project_status.py" --json)"
assert_contains "$ve_json" '"status": "attention"' "stale verification puts the project in attention"
ve_line="$(cd "$VE" && python3 "$REPO/scripts/project_status.py" | grep -- '- done-item ')"
assert_contains "$ve_line" "state=attention" "the stale item's own line is not PASS (competitor test round 2)"
assert_not_contains "$ve_line" "state=PASS" "the stale item's line does not say PASS next to verify=stale"
assert_contains "$(printf '%s' "$ve_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["next_action"])')" "done-item" "next action names the stale item"
(cd "$VE" && python3 "$REPO/scripts/project_status.py" >/dev/null); assert_eq "0" "$?" "default exit code is unchanged"
(cd "$VE" && python3 "$REPO/scripts/project_status.py" --strict >/dev/null); strict_rc=$?
assert_eq "3" "$strict_rc" "--strict exits 3 on stale verification"
git -C "$VE" checkout -q -- src/app.py
assert_eq "current" "$(ve_state done-item)" "restoring the content makes it current again"

printf '\n# weaker\n' >> "$VE/tests/test_app.py"
assert_eq "stale" "$(ve_state done-item)" "a test change makes it stale"
git -C "$VE" checkout -q -- tests/test_app.py
rm "$VE/tests/test_app.py"
assert_eq "stale" "$(ve_state done-item)" "deleting a test makes it stale"
git -C "$VE" checkout -q -- tests/test_app.py
printf 'x = 1\n' > "$VE/src/extra.py"
assert_eq "stale" "$(ve_state done-item)" "an uncommitted new source file makes it stale"
rm "$VE/src/extra.py"
printf 'docs only\n' > "$VE/docs/work/done-item/notes.md"
assert_eq "current" "$(ve_state done-item)" "work-item notes outside the roots do not make it stale"
assert_eq "$before_status" "$(git -C "$VE" status --porcelain | grep -v notes.md)" "project-status wrote nothing"

printf 'def add(a, b):\n    return a - b\n' > "$VE/src/app.py"
(cd "$VE" && bash "$VERIFY" --work-item done-item >/dev/null 2>&1)
assert_contains "$(cat "$VE/docs/work/done-item/verification.json")" '"result": "fail"' "a failing run is recorded as fail"
assert_eq "failed" "$(ve_state done-item)" "failed evidence is never current"
(cd "$VE" && bash "$VERIFY" --work-item done-item --skip-test >/dev/null 2>&1)
assert_contains "$(cat "$VE/docs/work/done-item/verification.json")" '"result": "skipped"' "a run that skips tests is recorded as skipped"
assert_eq "failed" "$(ve_state done-item)" "a run that skips tests is not passing evidence"

# Review findings (2026-10-30): coverage, binding of the commands, tamper resistance,
# scope normalization and orientation.
git -C "$VE" checkout -q -- src/app.py
(cd "$VE" && bash "$VERIFY" --work-item done-item >/dev/null 2>&1)
assert_eq "current" "$(ve_state done-item)" "re-verifying restores current evidence"
make_done_item done-b 2026-10-30T11:00:00Z
printf '\n# later work\n' >> "$VE/src/app.py"
(cd "$VE" && bash "$VERIFY" --work-item done-b >/dev/null 2>&1)
assert_eq "current" "$(ve_state done-b)" "the newer item is current"
assert_eq "covered" "$(ve_state done-item)" "an older item is covered when newer passing evidence spans the same scope"
ve_attention="$(cd "$VE" && python3 "$REPO/scripts/project_status.py" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["verification_attention"])')"
assert_not_contains "$ve_attention" "done-item" "covered items do not need attention"

cp "$VE/.agent/project-manifest.md" "$TMP/manifest.bak"
sed -i.bak 's/^- test_cmd: .*/- test_cmd: `true`/' "$VE/.agent/project-manifest.md"
assert_eq "stale" "$(ve_state done-b)" "changing the test command makes the evidence stale"
cp "$TMP/manifest.bak" "$VE/.agent/project-manifest.md"; rm -f "$VE/.agent/project-manifest.md.bak"
assert_eq "current" "$(ve_state done-b)" "restoring the test command makes it current again"

cp "$VE/docs/work/done-b/verification.json" "$TMP/evidence.bak"
sed -i.bak 's/"schema": [0-9]*/"schema": 99/' "$VE/docs/work/done-b/verification.json"
assert_eq "unknown" "$(ve_state done-b)" "evidence with an unknown schema is unknown"
printf 'not json' > "$VE/docs/work/done-b/verification.json"
assert_eq "unknown" "$(ve_state done-b)" "unreadable evidence is unknown"
cp "$TMP/evidence.bak" "$VE/docs/work/done-b/verification.json"; rm -f "$VE/docs/work/done-b/verification.json.bak"

(cd "$VE" && python3 "$REPO/scripts/verification_evidence.py" record --work-item done-b --result pass --exit-code 0 --checks 1 >/dev/null 2>&1); direct_rc=$?
assert_neq "0" "$direct_rc" "recording evidence outside verify.sh is refused"

(cd "$VE" && bash "$VERIFY" --work-item >/dev/null 2>&1); empty_rc=$?
assert_eq "2" "$empty_rc" "--work-item without a slug is a usage error"

make_done_item merged-item 2026-10-30T12:00:00Z
python3 - "$VE/docs/work/merged-item/meta.yml" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text(path.read_text().replace(
    "delivery_status: awaiting_approval\n",
    "delivery_status: merged\ndelivery_evidence:\n  approval_ref: user:fixture-approval\n"
    "  merge_sha: 0123456789abcdef0123456789abcdef01234567\n",
))
PY
assert_eq "n/a" "$(ve_state merged-item)" "merged items are history and are not assessed"
make_done_item tz-item 2026-10-29T20:00:00-05:00
assert_eq "unknown" "$(ve_state tz-item)" "the cutoff compares instants, not local date strings"

mkdir -p "$VE/docs/work/active-x"
printf '# active\n' > "$VE/docs/work/active-x/implement-report.md"
cat > "$VE/docs/work/active-x/meta.yml" <<'EOF'
schema_version: work-item/v3
slug: active-x
title: active fixture
created_at: 2026-10-30T00:00:00Z
updated_at: 2026-10-30T00:00:00Z
execution_mode: bug-fix
work_status: active
delivery_status: not_requested
stages:
  implement: { skill: implement, file: implement-report.md, status: in_progress }
inputs:
  - fixture
EOF
slug_next="$(cd "$VE" && python3 "$REPO/scripts/project_status.py" --slug active-x --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["next_action"])')"
assert_contains "$slug_next" "active-x" "an active --slug keeps the next action on the focused item"
assert_contains "${slug_next%%;*}" "active-x" "an active --slug keeps the next action on the focused item"
assert_not_contains "$slug_next" "review attention" "verification attention does not override an active --slug"
assert_contains "$slug_next" "verification needs attention" "an active --slug still names the stale history in the next action"
assert_contains "$(cd "$VE" && python3 "$REPO/scripts/project_status.py" --json)" '"schema_version": 3' "the JSON contract version reflects the new fields"
# Recheck (2026-10-30): the only active item keeps orientation without --slug, as an active
# --slug does; the stale history is still listed and still fails --strict.
single_json="$(cd "$VE" && python3 "$REPO/scripts/project_status.py" --json)"
single_next="$(printf '%s' "$single_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["next_action"])')"
assert_contains "$single_next" "active-x" "the only active item keeps the next action without --slug"
assert_contains "${single_next%%;*}" "active-x" "the only active item keeps the next action"
assert_not_contains "$single_next" "review attention" "older verification attention does not take over the only active item"
assert_contains "$single_json" '"status": "attention"' "stale history still shows in the status with one active item (closetmate trial)"
assert_contains "$(printf '%s' "$single_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verification_attention"])')" "tz-item" "verification attention is still listed"
(cd "$VE" && python3 "$REPO/scripts/project_status.py" --strict >/dev/null); single_strict=$?
assert_eq "3" "$single_strict" "--strict still exits 3 with one active item"

cp "$VE/docs/work/done-b/verification.json" "$TMP/evidence.bak"
python3 - "$VE/docs/work/done-b/verification.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text()); data["command"] = ""
path.write_text(json.dumps(data))
PY
assert_eq "unknown" "$(ve_state done-b)" "evidence that names no test command is unknown"
cp "$TMP/evidence.bak" "$VE/docs/work/done-b/verification.json"

# Scope normalization, empty scope and repository mode use separate fixtures.
# The fixtures below run their tests with `python3 -B`. Writing bytecode beside the
# fixture source would make two environment-dependent failures that this host hides:
# a later `git add -A` commits the cache (a committed cache is a scope violation by
# design), and a same-size edit restored within the same second reuses a stale .pyc,
# because CPython validates a cache by the source's size and whole-second mtime.
# Apple's python3 keeps caches outside the tree (sys.pycache_prefix), so neither
# shows up on macOS; Linux CI sees both. The cache-filter assertions further down
# build their caches by hand, so they still exercise the product's own filtering.
make_scope_repo() { # dir roots-line
  mkdir -p "$1/src" "$1/tests" "$1/.agent" "$1/docs/work/item"
  git -C "$1" init -q
  cp "$VE/src/app.py" "$1/src/app.py"; cp "$VE/tests/test_app.py" "$1/tests/test_app.py"
  printf 'readme\n' > "$1/README.md"
  printf '## Paths\n%s\n\n## Stack\n- test_cmd: `python3 -B -m unittest discover -s tests`\n- typed_contracts: false\n' "$2" > "$1/.agent/project-manifest.md"
  printf '# item\n' > "$1/docs/work/item/implement-report.md"
  sed 's/^slug: .*/slug: item/' "$VE/docs/work/done-item/meta.yml" > "$1/docs/work/item/meta.yml"
  git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m fixture
  (cd "$1" && bash "$VERIFY" --work-item item >/dev/null 2>&1)
}
scope_state() { (cd "$1" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; print(next(i["verification"]["state"] for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item"))'; }
make_scope_repo "$TMP/scope-dot" '- source_roots: ./src
- tests_root: tests/'
printf '\n# edit\n' >> "$TMP/scope-dot/src/app.py"
assert_eq "stale" "$(scope_state "$TMP/scope-dot")" "./src and tests/ roots are normalized"
make_scope_repo "$TMP/scope-empty" '- source_roots: nonexistent'
assert_eq "unknown" "$(scope_state "$TMP/scope-empty")" "a scope that covers no files is unknown, not current"
make_scope_repo "$TMP/scope-repo" ''
assert_eq "current" "$(scope_state "$TMP/scope-repo")" "repository mode records current evidence"
printf 'changed\n' > "$TMP/scope-repo/README.md"
assert_eq "stale" "$(scope_state "$TMP/scope-repo")" "repository mode notices changes outside source roots"

# Recheck (2026-10-30): a newer run cannot cover an item after the item's test was deleted.
COV="$TMP/scope-covered"
make_scope_repo "$COV" '- source_roots: src
- tests_root: tests'
printf 'import unittest\nclass T(unittest.TestCase):\n    def test(self): self.assertTrue(True)\n' > "$COV/tests/test_two.py"
git -C "$COV" add -A && git -C "$COV" -c user.name=t -c user.email=t@example.invalid commit -q -m two
(cd "$COV" && bash "$VERIFY" --work-item item >/dev/null 2>&1)
sed 's/^slug: .*/slug: item2/' "$COV/docs/work/item/meta.yml" > "$TMP/item2-meta"
mkdir -p "$COV/docs/work/item2"; mv "$TMP/item2-meta" "$COV/docs/work/item2/meta.yml"
printf '# item2\n' > "$COV/docs/work/item2/implement-report.md"
printf 'def add(a, b):\n    return a - b\n' > "$COV/src/app.py"
rm "$COV/tests/test_app.py"
(cd "$COV" && bash "$VERIFY" --work-item item2 >/dev/null 2>&1)
item2_state="$( (cd "$COV" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; print(next(i["verification"]["state"] for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item2"))')"
assert_eq "current" "$item2_state" "the newer run over the remaining test passes"
assert_eq "stale" "$(scope_state "$COV")" "a newer run over fewer files does not cover a broken item whose test was deleted"

# Competitor test round 2: caches that test runs write must not make evidence stale, even
# when the repository does not ignore them.
CACHE="$TMP/scope-cache"
make_scope_repo "$CACHE" ''
mkdir -p "$CACHE/__pycache__" "$CACHE/tests/__pycache__" "$CACHE/.pytest_cache" "$CACHE/node_modules/x"
printf 'a' > "$CACHE/__pycache__/app.cpython-313.pyc"; printf 'b' > "$CACHE/tests/__pycache__/t.pyc"
printf 'c' > "$CACHE/.pytest_cache/v"; printf 'd' > "$CACHE/node_modules/x/i.js"; printf 'e' > "$CACHE/.coverage"
assert_eq "current" "$(scope_state "$CACHE")" "test-run caches do not make evidence stale"
printf 'changed\n' > "$CACHE/README.md"
assert_eq "stale" "$(scope_state "$CACHE")" "real files next to the caches still count"

# Competitor test rerun 3: an item left active after its run still has its evidence assessed.
ACT="$TMP/active-evidence"
make_scope_repo "$ACT" '- source_roots: src
- tests_root: tests'
python3 - "$ACT/docs/work/item/meta.yml" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1]); text = path.read_text()
text = text.replace("work_status: completed", "work_status: active")
text = re.sub(r"delivery_status: \w+", "delivery_status: not_requested", text)
text = re.sub(r"(?m)^documentation_impact:.*\n", "", text)
path.write_text(text)
PY
(cd "$ACT" && bash "$REPO/scripts/work-items.sh" --work-root docs/work check >/dev/null 2>&1); assert_eq "0" "$?" "the active fixture is a valid work item"
(cd "$ACT" && bash "$VERIFY" --work-item item >/dev/null 2>&1)
assert_eq "current" "$(scope_state "$ACT")" "an active item's recorded evidence is assessed"
printf 'def add(a, b):\n    return a - b\n' > "$ACT/src/app.py"
assert_eq "stale" "$(scope_state "$ACT")" "a code change makes an active item's evidence stale"
act_json="$(cd "$ACT" && python3 "$REPO/scripts/project_status.py" --json)"
assert_contains "$act_json" '"status": "attention"' "a stale active item puts the project in attention"
act_next="$(printf '%s' "$act_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["next_action"])')"
assert_not_contains "$act_next" "review attention" "the next action is not taken over by review attention"
assert_contains "$act_next" "verification needs attention" "and names its stale evidence"

# T08: the ledger, queued backlog items, verify timing and activity in status.
LG="$TMP/ledger"
make_scope_repo "$LG" '- source_roots: src
- tests_root: tests'
bash "$REPO/scripts/work-items.sh" --work-root "$LG/docs/work" new backlog-one --queued >/dev/null 2>&1
bash "$REPO/scripts/work-items.sh" --work-root "$LG/docs/work" new backlog-two --queued >/dev/null 2>&1
bash "$REPO/scripts/work-items.sh" --work-root "$LG/docs/work" new now-active >/dev/null 2>&1
(cd "$LG" && bash "$VERIFY" --work-item now-active >/dev/null 2>&1)
rm -f "$LG/docs/work/item/activity.jsonl"  # an item from before the activity log
lg_json="$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --json)"
assert_contains "$lg_json" '"multiple_active": false' "queued backlog items do not count as active"
assert_eq "['now-active']" "$(printf '%s' "$lg_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["ambiguity"]["active_slugs"])')" "only the started item is active"
assert_not_contains "$(printf '%s' "$lg_json" | python3 -c 'import json,sys; print([i["state"] for i in json.load(sys.stdin)["work_items"] if i["slug"]=="now-active"])')" "unknown" "a verified active item without a plan is not unknown"
assert_contains "$(tail -1 "$LG/docs/work/now-active/activity.jsonl")" '"started_at"' "verify logs when the run started"
assert_contains "$(cat "$LG/docs/work/now-active/verification.json")" '"started_at"' "verification evidence records the start time"
lg_text="$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger)"
assert_contains "$lg_text" "ledger: 4 work item(s)" "the ledger lists every work item, queued ones included"
assert_contains "$lg_text" "backlog-one [queued/not_requested]" "the ledger shows queued items"
assert_contains "$lg_text" "verify: current" "the ledger shows the last verification"
assert_contains "$lg_text" "prd=in_progress (prd.md)" "the text ledger names each stage's file (round 3 criterion E)"
assert_contains "$lg_text" "last: verify" "the ledger shows the last activity"
assert_contains "$lg_text" "test cases: n/a (mode has no QA stage)" "the ledger says when a mode has no test-case artifact"
assert_contains "$lg_text" "last: -" "an item without an activity log is listed with no last activity"
lg_md="$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger --markdown)"
assert_contains "$lg_md" "| Item | Status | State | Stages | Verification | Approval | Last activity | Sessions |" "the Markdown ledger has a header"
assert_contains "$lg_md" '`now-active`' "the Markdown ledger has a row per item"
lg_ljson="$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger --json)"
assert_contains "$lg_ljson" '"ledger"' "the ledger has a JSON form"
assert_contains "$lg_ljson" '"file": "prd.md"' "the JSON ledger carries stage paths"
lg_slug="$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger --slug backlog-one)"
assert_contains "$lg_slug" "ledger: 4 work item(s)" "--slug does not narrow the ledger"
printf '<<<<<<< HEAD\nnot json\n' >> "$LG/docs/work/now-active/activity.jsonl"
assert_contains "$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger)" "unreadable activity lines: 2" "conflict markers and malformed lines are reported, not fatal"
mkdir -p "$LG/docs/work/broken"; printf 'schema_version: work-item/v3\nslug: broken\n' > "$LG/docs/work/broken/meta.yml"
lg_bad="$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger)"
assert_contains "$lg_bad" "broken [" "an invalid item is still listed"
assert_contains "$lg_bad" "state=invalid error=" "an invalid item shows its first error"
lg_ro="$(git -C "$LG" status --porcelain docs/work | wc -l)"
(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger >/dev/null)
assert_eq "$lg_ro" "$(git -C "$LG" status --porcelain docs/work | wc -l)" "the ledger writes nothing"

# T08 review: every logging command, refusals, orphans, flags and a missing activity.py.
(cd "$LG" && SKILL_COMMONS_SESSION=handoff-42 python3 "$REPO/scripts/verification_evidence.py" approve --work-item now-active --by user:owner --agent-reported --reason "test fixture" >/dev/null 2>&1)
assert_contains "$(tail -1 "$LG/docs/work/now-active/activity.jsonl")" '"event": "approve"' "approve logs an event"
assert_contains "$(tail -1 "$LG/docs/work/now-active/activity.jsonl")" '"session_override": "handoff-42"' "an explicit session is recorded as session_override, not as a tool"
assert_contains "$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger --json)" '"handoff-42"' "the JSON ledger lists the explicit session"
printf 'def add(a, b):\n    return a - b\n' > "$LG/src/app.py"
(cd "$LG" && bash "$VERIFY" --work-item now-active >/dev/null 2>&1)
assert_contains "$(tail -1 "$LG/docs/work/now-active/activity.jsonl")" '"result": "fail"' "a failing verify is logged as fail"
git -C "$LG" checkout -q -- src/app.py
q_lines="$(wc -l < "$LG/docs/work/backlog-one/activity.jsonl")"
qv_rc=0; (cd "$LG" && bash "$VERIFY" --work-item backlog-one >/dev/null 2>&1) || qv_rc=$?
assert_neq "0" "$qv_rc" "verify refuses a queued item"
assert_eq "0" "$([ -e "$LG/docs/work/backlog-one/verification.json" ] && echo 1 || echo 0)" "a refused verify writes no evidence"
assert_eq "$q_lines" "$(wc -l < "$LG/docs/work/backlog-one/activity.jsonl")" "a refused verify logs nothing"
mkdir -p "$LG/docs/work/stray-folder"; printf 'notes\n' > "$LG/docs/work/stray-folder/notes.md"
assert_contains "$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger)" "omitted: 1 folder(s) without meta.yml" "the ledger says how many folders it omitted"
md_rc=0; (cd "$LG" && python3 "$REPO/scripts/project_status.py" --markdown >/dev/null 2>&1) || md_rc=$?
assert_eq "2" "$md_rc" "--markdown without --ledger is a usage error"
assert_contains "$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger --slug now-active 2>&1 >/dev/null)" "--slug is ignored" "the ledger says it ignores --slug"
assert_contains "$(cd "$LG" && python3 "$REPO/scripts/project_status.py" --ledger --json)" '"duration_seconds"' "the JSON ledger has the verification duration"
NOACT="$TMP/no-activity-install"
mkdir -p "$NOACT/skill/scripts" "$NOACT/skill/verification-before-completion/scripts"
cp "$REPO/scripts/verification_evidence.py" "$REPO/scripts/manifest-stack.sh" "$NOACT/skill/scripts/"
cp "$REPO/verification-before-completion/scripts/verify.sh" "$NOACT/skill/verification-before-completion/scripts/"
noact_rc=0; noact_out="$(cd "$LG" && bash "$NOACT/skill/verification-before-completion/scripts/verify.sh" --work-item now-active 2>&1)" || noact_rc=$?
assert_eq "0" "$noact_rc" "verify still records evidence when activity.py is missing"
assert_contains "$noact_out" "activity.py is missing" "and warns that the log was skipped"
QO="$TMP/queued-only"; mkdir -p "$QO/docs/work"
bash "$REPO/scripts/work-items.sh" --work-root "$QO/docs/work" new later --queued >/dev/null 2>&1
assert_contains "$(python3 "$REPO/scripts/project_status.py" --project-root "$QO" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["next_action"])')" "" "status runs with only queued work"
qo_next="$(python3 - "$REPO" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts")
import project_status
print(project_status.compute_next_action("PASS", {"multiple_active": False}, None, [], [], [], queued=2))
PY
)"
assert_contains "$qo_next" "2 queued: start one with work-items.sh start" "with no active work, the next action points at the backlog"
stale_out="$(bash "$REPO/scripts/work-items.sh" --work-root "$QO/docs/work" stale --days 30 --now 2030-01-01T00:00:00Z 2>&1)"
assert_contains "$stale_out" "later" "stale lists old queued items too"

# T05: acceptance segments and approvals are bound to the content they verified.
AC="$TMP/acceptance"
make_scope_repo "$AC" '- source_roots: src
- tests_root: tests'
cat > "$AC/docs/work/item/prd.md" <<'EOF'
# PRD

Background: the list is long.

## Acceptance Criteria

### AC-001: Sort
Given items, when sorted, then newest first.

### AC-002: Filter
Given items, when filtered by color, then only that color shows.

## Notes
Free text.
EOF
ac_status() { (cd "$AC" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; i=next(i for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item"); print(i[sys.argv[1]]["state"])' "${1:-verification}"; }
ac_detail() { (cd "$AC" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; i=next(i for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item"); print(i[sys.argv[1]].get("detail",""))' "${1:-verification}"; }
ac_edit() { python3 - "$AC/docs/work/item/prd.md" "$1" "$2" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1]); text = path.read_text()
assert sys.argv[2] in text, sys.argv[2]
path.write_text(text.replace(sys.argv[2], sys.argv[3], 1))
PY
}
cp "$AC/docs/work/item/prd.md" "$TMP/prd.orig"
(cd "$AC" && bash "$VERIFY" --work-item item >/dev/null 2>&1)
assert_contains "$(cat "$AC/docs/work/item/verification.json")" '"ref": "prd.md#AC-002"' "a run binds every AC segment in prd.md by default"
assert_eq "current" "$(ac_status)" "bound segments start current"
ac_edit "then only that color shows" "then every color shows"
assert_eq "stale" "$(ac_status)" "changing an acceptance criterion after done makes the evidence stale (S7b)"
assert_contains "$(ac_detail)" "prd.md#AC-002" "the stale detail names the changed criterion"
(cd "$AC" && python3 "$REPO/scripts/project_status.py" --strict >/dev/null); assert_eq "3" "$?" "--strict exits 3 on a changed criterion"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"
ac_edit "the list is long." "the list is long and slow."
assert_eq "current" "$(ac_status)" "editing a paragraph outside any criterion keeps the evidence current"
ac_edit "Free text." "Other text."
assert_eq "current" "$(ac_status)" "editing a later section keeps the evidence current"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"
ac_edit "Given items, when sorted, then newest first." "Given items,  when sorted;  then newest first!"
assert_eq "current" "$(ac_status)" "whitespace and punctuation edits do not count as changes"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"

ac_edit "then newest first" "then newest items first"
(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" reaffirm --work-item item --ref prd.md#AC-001 --reason "" >/dev/null 2>&1); assert_neq "0" "$?" "reaffirm needs a reason"
(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" reaffirm --work-item item --ref ../x.md#AC-001 --reason r >/dev/null 2>&1); assert_neq "0" "$?" "reaffirm refuses a segment outside the work item"
(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" reaffirm --work-item item --ref prd.md#AC-009 --reason r >/dev/null 2>&1); assert_neq "0" "$?" "reaffirm refuses a missing segment"
(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" reaffirm --work-item item --ref prd.md#AC-001 --reason "wording only" >/dev/null 2>&1); assert_eq "0" "$?" "reaffirm with a reason succeeds"
assert_eq "current" "$(ac_status)" "a reaffirmed segment is current again"
assert_contains "$(cat "$AC/docs/work/item/verification.json")" '"reason": "wording only"' "the reason is recorded"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py")" "reaffirmed=1" "status shows how many segments were reaffirmed"
ac_edit "then newest items first" "then oldest items first"
assert_eq "stale" "$(ac_status)" "editing a reaffirmed segment again makes it stale again"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"
(cd "$AC" && bash "$VERIFY" --work-item item >/dev/null 2>&1)

make_done_item_in() { sed "s/^slug: .*/slug: $2/" "$1/docs/work/item/meta.yml" > "$TMP/meta.$2"; mkdir -p "$1/docs/work/$2"; mv "$TMP/meta.$2" "$1/docs/work/$2/meta.yml"; printf '# r\n' > "$1/docs/work/$2/implement-report.md"; }
make_done_item_in "$AC" later
ac_edit "then only that color shows" "then every color shows"
printf '\n# later\n' >> "$AC/src/app.py"
(cd "$AC" && bash "$VERIFY" --work-item later >/dev/null 2>&1)
assert_eq "stale" "$(ac_status)" "newer code evidence does not cover a changed criterion"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"; git -C "$AC" checkout -q -- src/app.py

(cd "$AC" && bash "$VERIFY" --work-item item --covers prd.md#AC-001 >/dev/null 2>&1)
ac_edit "then only that color shows" "then every color shows"
assert_eq "current" "$(ac_status)" "--covers binds only the named criterion"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"
(cd "$AC" && bash "$VERIFY" --work-item item --covers prd.md#AC-404 >/dev/null 2>&1); assert_neq "0" "$?" "--covers with a missing criterion fails to record"
(cd "$AC" && bash "$VERIFY" --covers prd.md#AC-001 >/dev/null 2>&1); assert_eq "2" "$?" "--covers without --work-item is a usage error"

(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" approve --work-item item --by chuliying >/dev/null 2>&1); assert_neq "0" "$?" "an approver must be a typed reference"
(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" approve --work-item item --by user:chuliying --agent-reported --quote "ok, approve it" >/dev/null 2>&1); assert_eq "0" "$?" "approve binds the approval"
assert_eq "current" "$(ac_status approval)" "a fresh approval is current"
ac_edit "then newest first" "then oldest first"
assert_eq "stale" "$(ac_status approval)" "editing an approved criterion makes the approval stale"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --json)" "item (approval stale)" "a stale approval needs attention"
(cd "$AC" && python3 "$REPO/scripts/verification_evidence.py" reaffirm --work-item item --ref prd.md#AC-001 --reason "same meaning" --agent-reported >/dev/null 2>&1)
assert_eq "current" "$(ac_status approval)" "a reaffirmed approval is current again"
assert_contains "$(cat "$AC/docs/work/item/approval.json")" '"by": "user:chuliying"' "the approver reference is recorded"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"

# T11: how an approval was obtained. Every call without --agent-reported runs through the helper,
# so a developer's own terminal never receives the prompt.
# with_tty.py: `tty <answer> cmd` gives cmd a fresh pseudo-terminal without the agent variables and
# types <answer> at the prompt; `tty-agent` keeps the variables; `notty` runs cmd with no
# controlling terminal. It is written here, not shipped as a tool.
TTY="$TMP/with_tty.py"
cat > "$TTY" <<'HELPER'
import os
import pty
import select
import signal
import subprocess
import sys

# Test-only: the suite writes this file into its temp directory and sets the token.
if os.environ.get("SKILL_COMMONS_TEST") != "1":
    sys.exit("with_tty: test helper; run by tests/test_project_status.sh only")
sys.path.insert(0, sys.argv[1])
import activity  # noqa: E402

mode = sys.argv[2]
clean = {key: value for key, value in os.environ.items() if key not in activity.agent_env_vars()}
if mode == "notty":
    try:
        done = subprocess.run(sys.argv[3:], env=clean, start_new_session=True, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        sys.exit("with_tty: command did not finish in 60 s")
    sys.stdout.write(done.stdout + done.stderr)
    sys.exit(done.returncode)
answer, command = sys.argv[3], sys.argv[4:]
env = dict(os.environ) if mode == "tty-agent" else clean
try:
    pid, fd = pty.fork()
except OSError:
    print("with_tty: no pty available in this environment")
    sys.exit(3)
if pid == 0:
    os.execvpe(command[0], command, env)
seen = b""
sent = False
timed_out = False
while True:
    try:
        ready, _, _ = select.select([fd], [], [], 20)
    except InterruptedError:
        continue
    if not ready:
        timed_out = True
        break
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    seen += chunk
    if not sent and b"Type yes to confirm:" in seen:
        os.write(fd, answer.encode() + b"\n")
        sent = True
if timed_out:
    os.kill(pid, signal.SIGKILL)
os.waitpid(pid, 0) if timed_out else None
sys.stdout.write(seen.decode(errors="replace"))
if timed_out:
    print("with_tty: prompt not seen; the command was stopped")
    sys.exit(4)
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
HELPER
export SKILL_COMMONS_TEST=1
EV="$REPO/scripts/verification_evidence.py"
ac_field() { (cd "$AC" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; i=next(i for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item"); print(i["approval"].get(sys.argv[1]))' "$1"; }
git -C "$AC" config user.name "Sam Lee"
appr_before="$(cat "$AC/docs/work/item/approval.json")"
t11_out="$(cd "$AC" && python3 "$TTY" "$REPO/scripts" notty python3 "$EV" approve --work-item item --by user:sam)"; t11_rc=$?
assert_eq "2" "$t11_rc" "approve without a terminal is refused"
assert_contains "$t11_out" "no terminal: /dev/tty cannot be opened" "the refusal says why (CI, no agent)"
assert_contains "$t11_out" "approve --work-item item --by user:sam --agent-reported --quote" "the refusal prints the agent-reported command"
assert_eq "$appr_before" "$(cat "$AC/docs/work/item/approval.json")" "a refused approve writes nothing"
t11_out="$(cd "$AC" && CODEX_HOME=/x python3 "$TTY" "$REPO/scripts" tty-agent yes python3 "$EV" approve --work-item item --by user:sam)"; t11_rc=$?
assert_eq "2" "$t11_rc" "a terminal with an agent variable is refused (Codex PTY)"
assert_contains "$t11_out" "agent environment detected: CODEX_HOME" "the refusal names the variables it saw"
assert_contains "$t11_out" "env -u CODEX_HOME" "the refusal prints the env -u form for a person"
t11_out="$(cd "$AC" && python3 "$TTY" "$REPO/scripts" tty no python3 "$EV" approve --work-item item --by user:sam)"; t11_rc=$?
assert_neq "0" "$t11_rc" "an answer other than yes does not approve"
assert_eq "$appr_before" "$(cat "$AC/docs/work/item/approval.json")" "an unconfirmed approve writes nothing"
git -C "$AC" config user.name "朱麗英"
t11_out="$(cd "$AC" && python3 "$TTY" "$REPO/scripts" tty yes python3 "$EV" approve --work-item item)"; t11_rc=$?
assert_neq "0" "$t11_rc" "a non-ASCII git user.name needs --by"
assert_contains "$t11_out" "no usable ASCII characters; pass --by" "the refusal says why the name cannot be used"
git -C "$AC" config user.name "Sam Lee"
t11_out="$(cd "$TMP" && python3 "$TTY" "$REPO/scripts" notty python3 "$EV" approve --work-item item --by user:sam --project-root "$AC")"
assert_contains "$t11_out" "--project-root $(cd "$AC" && pwd -P)" "the printed command keeps the project root"
t11_out="$(cd "$AC" && python3 "$TTY" "$REPO/scripts" tty yes python3 "$EV" approve --work-item item)"; t11_rc=$?
assert_eq "0" "$t11_rc" "a person confirms at a terminal"
assert_contains "$t11_out" "prd.md#AC-001" "the prompt lists the segments"
assert_contains "$(cat "$AC/docs/work/item/approval.json")" '"by": "user:Sam-Lee"' "--by defaults to git config user.name"
assert_eq "terminal" "$(ac_field confirmation)" "the approval is confirmed at a terminal"
assert_contains "$(tail -1 "$AC/docs/work/item/activity.jsonl")" '"confirmation": "terminal"' "the activity line carries the level"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger)" "by user:Sam-Lee (terminal)" "the ledger shows the level"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger)" "approve" "the ledger lists the approve event"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger --json)" '"tools": "person"' "a terminal approval is shown as a person"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger --markdown)" "(terminal)" "the Markdown ledger shows the level"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py")" "approval=current(terminal)" "the status line shows the level"
ac_edit "then newest first" "then newest items first"
(cd "$AC" && python3 "$TTY" "$REPO/scripts" tty yes python3 "$EV" reaffirm --work-item item --ref prd.md#AC-001 --reason "same meaning" >/dev/null)
assert_eq "terminal" "$(ac_field confirmation)" "a terminal reaffirm keeps the terminal level"
ac_edit "then newest items first" "then the newest items first"
evid_before="$(cat "$AC/docs/work/item/verification.json")"
t11_out="$(cd "$AC" && python3 "$TTY" "$REPO/scripts" notty python3 "$EV" reaffirm --work-item item --ref prd.md#AC-001 --reason "same meaning")"; t11_rc=$?
assert_eq "2" "$t11_rc" "reaffirming an approved segment without a terminal is refused"
assert_eq "$evid_before" "$(cat "$AC/docs/work/item/verification.json")" "a refused reaffirm writes neither file"
(cd "$AC" && python3 "$TTY" "$REPO/scripts" notty python3 "$EV" reaffirm --work-item item --ref prd.md#AC-001 --reason "same meaning" --evidence-only >/dev/null); assert_eq "0" "$?" "--evidence-only reaffirms the evidence without the gate"
assert_eq "stale" "$(ac_status approval)" "--evidence-only leaves the approval stale"
(cd "$AC" && python3 "$EV" reaffirm --work-item item --ref prd.md#AC-001 --reason "same meaning" --agent-reported >/dev/null 2>&1); assert_eq "0" "$?" "an agent-reported reaffirm is recorded"
assert_eq "agent-reported" "$(ac_field confirmation)" "an agent reaffirm lowers a terminal approval"
assert_eq "terminal" "$(ac_field approved_confirmation)" "the original terminal level is kept"
assert_contains "$(cat "$AC/docs/work/item/approval.json")" '"basis": "same meaning"' "the reaffirm entry records its basis"
(cd "$AC" && python3 "$EV" approve --work-item item --by user:sam --agent-reported --quote "  " >/dev/null 2>&1); assert_neq "0" "$?" "--agent-reported with an empty quote is refused"
(cd "$AC" && python3 "$EV" approve --work-item item --by user:sam --quote "yes" >/dev/null 2>&1); assert_neq "0" "$?" "--quote without --agent-reported is refused"
(cd "$AC" && python3 "$EV" approve --work-item item --agent-reported --quote "yes" >/dev/null 2>&1); assert_neq "0" "$?" "--agent-reported needs --by"
(cd "$AC" && python3 "$EV" approve --work-item item --by user:sam --agent-reported --quote "Looks right, approve it" >/dev/null 2>&1)
assert_eq "agent-reported" "$(ac_field confirmation)" "an agent-reported approval says so"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger --json)" '"agent_reported_claim": {' "the JSON ledger labels the quote as the agent's claim"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger --json)" "Looks right, approve it" "the JSON ledger carries the quote"
assert_not_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --json)" "Looks right" "the status JSON does not carry the quote"
assert_not_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --ledger)" "Looks right" "the default ledger does not print the quote"
python3 - "$AC/docs/work/item/approval.json" 1 <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text()); data["schema"] = int(sys.argv[2])
for key in ("confirmation", "agent_env", "quote", "basis", "agents"):
    data.pop(key, None)
path.write_text(json.dumps(data))
PY
assert_eq "recorded before levels" "$(ac_field confirmation)" "an approval from before T11 is labeled, not rejected"
assert_eq "current" "$(ac_status approval)" "an approval from before T11 is still current"
python3 - "$AC/docs/work/item/approval.json" 3 <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text()); data["schema"] = int(sys.argv[2])
path.write_text(json.dumps(data))
PY
assert_eq "unknown" "$(ac_status approval)" "a newer approval format is unknown"
assert_contains "$(cd "$AC" && python3 "$REPO/scripts/project_status.py" --json)" "newer format; update the submodule" "the newer format names the fix"
python3 - "$AC/docs/work/item/approval.json" 2 <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text()); data["schema"] = int(sys.argv[2])
path.write_text(json.dumps(data))
PY
assert_eq "unknown" "$(ac_status approval)" "a schema 2 approval without a level is unknown, not pre-T11"
cp "$TMP/prd.orig" "$AC/docs/work/item/prd.md"
(cd "$AC" && python3 "$EV" approve --work-item item --by user:chuliying --agent-reported --quote "ok, approve it" >/dev/null 2>&1)

python3 - "$AC/docs/work/item/verification.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text())
data["schema"] = 1; data.pop("segments", None); data.pop("reaffirmed", None); data.pop("auto_covers", None)
path.write_text(json.dumps(data))
PY
(cd "$AC" && bash "$VERIFY" --work-item item >/dev/null 2>&1; python3 - docs/work/item/verification.json <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text())
data["schema"] = 1; data.pop("segments", None); data.pop("reaffirmed", None); data.pop("auto_covers", None)
path.write_text(json.dumps(data))
PY
)
assert_eq "current" "$(ac_status)" "evidence in the earlier format is still readable"

# Fable round 2 spot check: sub-headings, added criteria, checkboxes, code fences, digits,
# hand-written approvals and more caches.
SEG="$TMP/segments"
make_scope_repo "$SEG" '- source_roots: src
- tests_root: tests'
cat > "$SEG/docs/work/item/prd.md" <<'EOF'
# PRD

### AC-001: Sort
Given items, newest first.
#### Example
Ten items take 1.5 seconds.

### AC-002: Filter
```
AC-001 inside a code block is not a segment
```
- [ ] AC-010 checkbox criterion

## Notes
EOF
cp "$SEG/docs/work/item/prd.md" "$TMP/seg.orig"
seg_state() { (cd "$SEG" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; i=next(i for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item"); print(i[sys.argv[1]]["state"])' "${1:-verification}"; }
seg_edit() { python3 - "$SEG/docs/work/item/prd.md" "$1" "$2" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1]); text = path.read_text()
assert sys.argv[2] in text, sys.argv[2]
path.write_text(text.replace(sys.argv[2], sys.argv[3], 1))
PY
}
(cd "$SEG" && bash "$VERIFY" --work-item item >/dev/null 2>&1); assert_eq "0" "$?" "an ID inside a code block does not make the criterion ambiguous"
assert_contains "$(cat "$SEG/docs/work/item/verification.json")" '"ref": "prd.md#AC-010"' "a checkbox criterion is bound"
assert_eq "current" "$(seg_state)" "segments with sub-headings start current"
seg_edit "Ten items take 1.5 seconds." "Ten items take 15 seconds."
assert_eq "stale" "$(seg_state)" "an edit under a sub-heading inside a criterion counts, and 1.5 is not 15"
cp "$TMP/seg.orig" "$SEG/docs/work/item/prd.md"
printf '\n### AC-003: Export\nGiven items, export them.\n' >> "$SEG/docs/work/item/prd.md"
assert_eq "stale" "$(seg_state)" "a criterion added after the run makes default-bound evidence stale"
(cd "$SEG" && python3 "$REPO/scripts/verification_evidence.py" approve --work-item item --by user:owner --agent-reported --reason "test fixture" >/dev/null 2>&1)
assert_eq "current" "$(seg_state approval)" "an approval made after the criterion was added is current"
cp "$TMP/seg.orig" "$SEG/docs/work/item/prd.md"
(cd "$SEG" && bash "$VERIFY" --work-item item --covers prd.md#AC-001 >/dev/null 2>&1)
printf '\n### AC-003: Export\nGiven items, export them.\n' >> "$SEG/docs/work/item/prd.md"
assert_eq "current" "$(seg_state)" "explicit --covers is not affected by an added criterion"
cp "$TMP/seg.orig" "$SEG/docs/work/item/prd.md"
python3 - "$SEG/docs/work/item/approval.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); data = json.loads(path.read_text()); data["by"] = "owner"
path.write_text(json.dumps(data))
PY
assert_eq "unknown" "$(seg_state approval)" "a hand-written approval without a typed approver is unknown"
(cd "$SEG" && bash "$VERIFY" --work-item item >/dev/null 2>&1)
mkdir -p "$SEG/htmlcov" "$SEG/.hypothesis" "$SEG/src/target"
printf 'h' > "$SEG/htmlcov/index.html"; printf 'h' > "$SEG/.hypothesis/x"; printf 'c' > "$SEG/.coverage.host.123"; printf 't' > "$SEG/src/target/out"
assert_eq "current" "$(seg_state)" "coverage, hypothesis and build caches do not make evidence stale"

# T12: allowed_paths. The fixture item is completed and undelivered, so the scope is checked.
SC="$TMP/scope-check"
make_scope_repo "$SC" '- source_roots: src
- tests_root: tests'
sc_git() { git -C "$SC" -c user.name=t -c user.email=t@example.invalid "$@"; }
sc_status() { (cd "$SC" && python3 "$REPO/scripts/project_status.py"); }
sc_json() { (cd "$SC" && python3 "$REPO/scripts/project_status.py" --json) | python3 -c 'import json,sys; i=next(i for i in json.load(sys.stdin)["work_items"] if i["slug"]=="item"); print(json.dumps(i.get("scope")))'; }
assert_eq "null" "$(sc_json)" "without allowed_paths the scope is not checked"
assert_not_contains "$(sc_status)" "scope=" "without allowed_paths the status line has no scope"
sc_base="$(sc_git rev-parse HEAD)"
printf 'allowed_paths: src/, tests/**/*.py\nbase_commit: %s\n' "$sc_base" >> "$SC/docs/work/item/meta.yml"
sc_git add -A && sc_git commit -q -m "declare scope"
assert_contains "$(sc_status)" "scope=ok" "changes inside allowed_paths are ok"
printf '\n# in scope\n' >> "$SC/src/app.py"
assert_contains "$(sc_status)" "scope=ok" "an uncommitted change inside allowed_paths is ok"
printf 'changed\n' >> "$SC/README.md"
assert_contains "$(sc_status)" "scope=1 outside allowed_paths: README.md" "an uncommitted change outside allowed_paths is listed"
assert_contains "$(cd "$SC" && python3 "$REPO/scripts/project_status.py" --json)" "item (scope: 1 outside allowed_paths)" "a scope violation needs attention"
sc_strict=0; (cd "$SC" && python3 "$REPO/scripts/project_status.py" --strict >/dev/null) || sc_strict=$?
assert_eq "3" "$sc_strict" "--strict fails on a scope violation"
sc_git add -A && sc_git commit -q -m "touch readme"
assert_contains "$(sc_status)" "README.md" "a committed change outside allowed_paths is listed"
mkdir -p "$SC/src/__pycache__"; printf 'x' > "$SC/src/__pycache__/app.cpython-313.pyc"; printf 'x' > "$SC/tests/__pycache__.pyc"
assert_not_contains "$(sc_status)" "__pycache__" "an uncommitted cache is not a violation"
sc_git add -f src/__pycache__/app.cpython-313.pyc && sc_git commit -q -m "commit a cache"
assert_contains "$(sc_status)" "src/__pycache__/app.cpython-313.pyc" "a committed cache outside allowed_paths is a violation"
sc_git rm -q README.md && sc_git commit -q -m "delete readme"
assert_contains "$(sc_json)" '"README.md"' "a deletion counts"
mkdir -p "$SC/.claude"; printf '{}' > "$SC/.claude/settings.json"; printf 'n\n' > "$SC/docs/work/item/notes.md"
assert_not_contains "$(sc_status)" ".claude/settings.json" "generated agent directories are always allowed"
assert_not_contains "$(sc_status)" "notes.md" "the work root is always allowed"
rm -rf "$SC/.claude" "$SC/docs/work/item/notes.md" "$SC/tests/__pycache__.pyc"
(cd "$SC" && bash "$VERIFY" --work-item item >/dev/null 2>"$TMP/sc-verify.err")
assert_contains "$(cat "$SC/docs/work/item/verification.json")" '"violations": [' "verify records the scope"
assert_contains "$(cat "$TMP/sc-verify.err")" "outside allowed_paths" "verify reports the violations"
sed -i.bak 's#^allowed_paths: .*#allowed_paths: src/, tests/**/*.py, README.md, src/__pycache__/#' "$SC/docs/work/item/meta.yml" && rm -f "$SC/docs/work/item/meta.yml.bak"
assert_contains "$(sc_status)" "allowed_paths changed since the last run: was src/, tests/**/*.py" "a widened allowed_paths list is shown"
sc_git add -A && sc_git commit -q -m "widen"
sed -i.bak "s#^base_commit: .*#base_commit: 0123456789abcdef0123456789abcdef01234567#" "$SC/docs/work/item/meta.yml" && rm -f "$SC/docs/work/item/meta.yml.bak"
assert_contains "$(sc_status)" "does not resolve" "an unresolvable base_commit falls back to uncommitted changes and says so"
sed -i.bak "/^base_commit: /d" "$SC/docs/work/item/meta.yml" && rm -f "$SC/docs/work/item/meta.yml.bak"
assert_contains "$(sc_status)" "no base_commit recorded" "a missing base_commit says only uncommitted changes are checked"
sc_git checkout -q -- docs/work/item/meta.yml

# Commits merged in from the default branch are not the item's own.
sc_main="$(sc_git rev-parse --abbrev-ref HEAD)"
sc_git checkout -q -b feature
sed -i.bak "s#^base_commit: .*#base_commit: $(sc_git rev-parse HEAD)#" "$SC/docs/work/item/meta.yml" && rm -f "$SC/docs/work/item/meta.yml.bak"
sc_git add -A && sc_git commit -q -m "start on feature"
sc_git checkout -q "$sc_main"; printf 'other\n' > "$SC/OTHER.md"; sc_git add OTHER.md && sc_git commit -q -m "main moves"
sc_git checkout -q feature && sc_git merge -q --no-edit "$sc_main"
assert_not_contains "$(sc_status)" "OTHER.md" "a change merged in from the default branch is not a violation"
printf 'mine\n' > "$SC/MINE.md"; sc_git add MINE.md && sc_git commit -q -m "feature change"
assert_contains "$(sc_status)" "MINE.md" "the item's own commit after the merge is still checked"

# Several active items: the shared range is shown, not attention on its own.
sed -i.bak 's/^work_status: completed/work_status: active/; s/^delivery_status: .*/delivery_status: not_requested/' "$SC/docs/work/item/meta.yml" && rm -f "$SC/docs/work/item/meta.yml.bak"
mkdir -p "$SC/docs/work/other"; sed 's/^slug: item/slug: other/' "$SC/docs/work/item/meta.yml" > "$SC/docs/work/other/meta.yml"; printf '# o\n' > "$SC/docs/work/other/implement-report.md"
assert_not_contains "$(cd "$SC" && python3 "$REPO/scripts/project_status.py" --json)" "(scope:" "with several active items a scope violation is not attention"
assert_contains "$(sc_status)" "MINE.md" "with several active items the violations are still shown"

# work-items new records base_commit; start of a queued item replaces it.
WI="$TMP/scope-new"; mkdir -p "$WI" && git -C "$WI" init -q && git -C "$WI" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
(cd "$WI" && bash "$REPO/scripts/work-items.sh" new later --queued >/dev/null 2>&1)
assert_contains "$(cat "$WI/docs/work/later/meta.yml")" "base_commit: $(git -C "$WI" rev-parse HEAD)" "new records the base commit"
git -C "$WI" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m later
(cd "$WI" && bash "$REPO/scripts/work-items.sh" start later >/dev/null 2>&1)
assert_contains "$(cat "$WI/docs/work/later/meta.yml")" "base_commit: $(git -C "$WI" rev-parse HEAD)" "start replaces the base commit"
assert_eq "1" "$(grep -c '^base_commit:' "$WI/docs/work/later/meta.yml")" "start keeps one base_commit"
printf 'allowed_paths: ,\n' >> "$WI/docs/work/later/meta.yml"
assert_contains "$(cd "$WI" && bash "$REPO/scripts/work-items.sh" check 2>&1)" "comma-separated list of paths or globs on one line" "an empty allowed_paths is invalid"

# Fable T12 review: shared range with a completed item, rebase, remote default branch without
# origin/HEAD, a project below the Git top level, pattern forms and validation messages.
RB="$TMP/scope-rebase"
make_scope_repo "$RB" '- source_roots: src'
rb() { git -C "$RB" -c user.name=t -c user.email=t@example.invalid "$@"; }
rb_status() { (cd "$RB" && python3 "$REPO/scripts/project_status.py"); }
rb_main="$(rb rev-parse --abbrev-ref HEAD)"
git init -q --bare "$TMP/scope-remote.git"; rb remote add origin "$TMP/scope-remote.git"; rb push -q origin "$rb_main"
rb checkout -q -b feature
printf 'pre\n' > "$RB/PRE.md"; rb add PRE.md && rb commit -q -m "before the item"
printf 'allowed_paths: src\nbase_commit: %s\n' "$(rb rev-parse HEAD)" >> "$RB/docs/work/item/meta.yml"
rb add -A && rb commit -q -m "item starts"
assert_contains "$(rb_status)" "scope=ok" "a bare folder name allows everything under it"
rb checkout -q "$rb_main"; printf 'up\n' > "$RB/UP.md"; rb add UP.md && rb commit -q -m "main moves"; rb push -q origin "$rb_main"
rb reset -q --hard HEAD~1; rb checkout -q feature
assert_eq "" "$(rb symbolic-ref -q refs/remotes/origin/HEAD)" "the remote has no origin/HEAD"
rb merge -q --no-edit "origin/$rb_main"
assert_not_contains "$(rb_status)" "UP.md" "a merge from origin's default branch is excluded even when local main is behind and origin/HEAD is unset"
rb reset -q --hard HEAD~1
rb rebase -q "origin/$rb_main" 2>/dev/null
assert_contains "$(rb_status)" "not an ancestor of HEAD (rebased)" "a rebased base falls back and says so"
assert_not_contains "$(rb_status)" "PRE.md" "a rebase does not list commits from before the item"
rb checkout -q "$rb_main"; rb merge -q --ff-only "origin/$rb_main"
printf 'allowed_paths: src\nbase_commit: %s\n' "$(rb rev-parse HEAD)" >> "$RB/docs/work/item/meta.yml"
rb add -A && rb commit -q -m "item on main"
assert_contains "$(rb_status)" "on the default branch: commits pulled from others since base_commit also count" "work on the default branch says pulled commits count"

# A completed item beside an active one: the shared range is shown, not attention.
mkdir -p "$RB/docs/work/next"; sed 's/^slug: item/slug: next/; s/^work_status: completed/work_status: active/; s/^delivery_status: .*/delivery_status: not_requested/; s#^allowed_paths: .*#allowed_paths: lib/#' "$RB/docs/work/item/meta.yml" > "$RB/docs/work/next/meta.yml"; printf '# n\n' > "$RB/docs/work/next/implement-report.md"
mkdir -p "$RB/lib"; printf 'x\n' > "$RB/lib/x.py"; rb add -A && rb commit -q -m "next item works"
assert_contains "$(rb_status)" "share this branch" "items sharing a branch are named"
assert_not_contains "$(cd "$RB" && python3 "$REPO/scripts/project_status.py" --json)" "(scope:" "a completed item does not get attention for the next item's commits"

# A project below the Git top level.
SUB="$TMP/scope-sub"; mkdir -p "$SUB"; git -C "$SUB" init -q
make_scope_repo "$SUB/proj" '- source_roots: src'; rm -rf "$SUB/proj/.git"
printf 'allowed_paths: ./src/, tests/\n' >> "$SUB/proj/docs/work/item/meta.yml"
git -C "$SUB" add -A && git -C "$SUB" -c user.name=t -c user.email=t@example.invalid commit -q -m sub
printf '\n# edit\n' >> "$SUB/proj/src/app.py"; printf 'n\n' > "$SUB/proj/docs/work/item/notes.md"; printf 'o\n' > "$SUB/proj/OUT.md"; printf 'top\n' > "$SUB/TOP.md"
sub_out="$(cd "$SUB/proj" && python3 "$REPO/scripts/project_status.py")"
assert_contains "$sub_out" "scope=1 outside allowed_paths: OUT.md" "paths are project-relative below the Git top level, and ./ is accepted"
assert_not_contains "$sub_out" "TOP.md" "files outside the project are not the item's"

# Validation messages.
VM="$TMP/scope-validate"; make_scope_repo "$VM" ''
printf 'allowed_paths: "src/, tests/" # only these\n' >> "$VM/docs/work/item/meta.yml"
assert_contains "$(cd "$VM" && bash "$REPO/scripts/work-items.sh" check 2>&1)" "must not contain quotes or a # comment" "a quoted or commented allowed_paths is refused"
sed -i.bak '/^allowed_paths:/d' "$VM/docs/work/item/meta.yml" && rm -f "$VM/docs/work/item/meta.yml.bak"
printf 'allowed_paths:\n' >> "$VM/docs/work/item/meta.yml"
assert_contains "$(cd "$VM" && bash "$REPO/scripts/work-items.sh" check 2>&1)" "comma-separated list of paths or globs on one line" "a YAML list form says to use one line"

finish
