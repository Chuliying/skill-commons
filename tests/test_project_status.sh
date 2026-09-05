#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
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
        "⚠️ 設定已過期 (stamp 000000000000 ≠ abcdef123456),請執行: bash bootstrap/onboard.sh\n",
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
assert_contains "$MULTI" '"schema_version": 2' "project-status emits the v3-aware schema"
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

finish
