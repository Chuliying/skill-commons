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

# The private source repo itself remains a bootstrap N/A/unknown context.
SELF="$(python3 "$REPO/scripts/project_status.py" --project-root "$REPO" --json)"
self_bootstrap="$(printf '%s' "$SELF" | python3 -c 'import json,sys;print(json.load(sys.stdin)["probes"]["bootstrap"]["state"])')"
assert_eq "unknown" "$self_bootstrap" "source repository bootstrap is unknown/N/A"

finish
