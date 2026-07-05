#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

TEMPLATE_PLAN="$TMP/template"
mkdir -p "$TEMPLATE_PLAN"
cp "$REPO/plan-sync/templates/implementation.md" "$TEMPLATE_PLAN/implementation.md"
cp "$REPO/plan-sync/templates/tasks.md" "$TEMPLATE_PLAN/tasks.md"
cp "$REPO/plan-sync/templates/notes.md" "$TEMPLATE_PLAN/notes.md"

set +e
template_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$TEMPLATE_PLAN" 2>&1)"
template_rc=$?
set -e
assert_neq "0" "$template_rc" "raw three-file templates fail validation"
assert_contains "$template_output" "placeholder" "template failure identifies placeholders"
assert_contains "$template_output" "implementation.md:" "placeholder failure includes location"

NORMAL_PLAN="$TMP/normal"
mkdir -p "$NORMAL_PLAN"
cat > "$NORMAL_PLAN/implementation.md" <<'EOF'
# Plan: fixture plan

## Metadata
- Plan Name: fixture plan
- Plan Slug: fixture-plan
- Status: active
- Created At: 2026-07-04 00:00
- Updated At: 2026-07-04 00:00

## Goal
Deliver one verified fixture.

## Success Criteria
- SC01: The fixture validator passes.

## Scope
- In: Validator behavior.

## Non-goals
- Out: Production deployment.

## Assumptions
- A01: Python 3.10 is available.

## Decisions
- D01: Keep one implementation section.

## Implementation Sections

### I01 | validate-fixture
- Key: validate-fixture
- Title: Validate fixture
- Status: active
- Summary: Validate a complete plan fixture.

#### Intent
Prove that completed content passes consistency checks.

#### Logic
Parse the three artifacts and compare their stable identifiers.

#### Edge Cases
- EC01: Missing files fail.

#### Impact Areas
- File/Artifact: fixture files
- Workflow/Area: plan validation

#### Validation
- V01: The validator exits zero.

#### Open Questions
- Q01: None.
EOF
python3 "$REPO/plan-sync/scripts/sync_tasks.py" --plan-dir "$NORMAL_PLAN" --write >/dev/null
cat > "$NORMAL_PLAN/notes.md" <<'EOF'
# Notes: fixture plan

## Current State Snapshot
- Active Intent: Validate a complete fixture.
- Current Decisions: Keep one section.
- Current Scope: Plan consistency.
- Open Risks: None.
- Next Action: Run validation.
- Last Updated: 2026-07-04 00:00

## Event Log
- N001 | 2026-07-04 00:00 | create | [I01][T01] | Initialized a complete fixture.
EOF

if python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$NORMAL_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: completed three-file plan passes validation"
else
  fail "completed three-file plan passes validation"
fi

LITE_PLAN="$TMP/lite"
mkdir -p "$LITE_PLAN"
cat > "$LITE_PLAN/plan.md" <<'EOF'
# Plan: lite fixture

## Plan
- Intent: Deliver a small verified change.
- Scope: One script and its test.
- Non-goals: No public API changes.

## Tasks

### T01 | implement fixture
- Status: pending

#### Intent
Create the fixture behavior.

#### Expected Result
The command returns the documented output.

#### Verification
- Run the fixture test and observe exit zero.

## Change Log
- 2026-07-04: Created the Lite plan.
EOF

if python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$LITE_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Lite single-file plan passes validation"
else
  fail "Lite single-file plan passes validation"
fi

cp "$NORMAL_PLAN/implementation.md" "$LITE_PLAN/implementation.md"
set +e
mixed_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$LITE_PLAN" 2>&1)"
mixed_rc=$?
set -e
assert_neq "0" "$mixed_rc" "Lite and three-file artifacts cannot coexist"
assert_contains "$mixed_output" "mixes Lite plan.md" "mixed-mode failure explains the conflict"

finish
