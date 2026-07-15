#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

plan_sync_skill="$(cat "$REPO/plan-sync/SKILL.md")"
plan_sync_template="$(cat "$REPO/plan-sync/templates/plan.md")"
subagent_skill="$(cat "$REPO/subagent-driven-development/SKILL.md")"
plan_sync_bytes="$(wc -c < "$REPO/plan-sync/SKILL.md" | tr -d ' ')"
if [ "$plan_sync_bytes" -le 6912 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Plan Sync stays within its context budget"
else
  fail "Plan Sync stays within 6912 bytes (got $plan_sync_bytes)"
fi
assert_contains "$plan_sync_skill" "validates reference, shape, and consistency only" "Plan Sync states its recorded-evidence boundary"
assert_contains "$plan_sync_skill" "authored PASS into behavioral proof" "Plan Sync does not overclaim execution attestation"
assert_contains "$plan_sync_skill" 'sibling metadata contains a `plan`' "Plan Sync names the sibling metadata stage precisely"
assert_contains "$plan_sync_skill" 'stage whose `skill` is `plan-sync`' "Plan Sync names the sibling metadata skill precisely"
assert_contains "$plan_sync_skill" "progress/commentary" "Plan Sync keeps skill transparency in progress updates"
assert_contains "$plan_sync_skill" "final answer" "Plan Sync keeps internal skill narration out of the final answer"
for token in "behavior-changing feature" "demoable or verifiable end to end" "fresh context" "next integration checkpoint" "expand" "migrate" "contract"; do
  assert_contains "$plan_sync_skill" "$token" "Plan Sync defines vertical decomposition contract: $token"
done
assert_contains "$plan_sync_skill" "label alone" "Plan Sync rejects label-only horizontal exceptions"
assert_contains "$subagent_skill" "does not re-slice" "subagent execution preserves approved task decomposition"
assert_not_contains "$plan_sync_template" "vertical slice" "raw Plan template keeps normative slice guidance out"

TEMPLATE_WORKSPACE="$TMP/template-workspace"
TEMPLATE_ITEM="$TEMPLATE_WORKSPACE/docs/work/template"
TEMPLATE_PLAN="$TEMPLATE_ITEM/plan"
mkdir -p "$TEMPLATE_PLAN" "$TEMPLATE_WORKSPACE/.git"
cp "$REPO/plan-sync/templates/plan.md" "$TEMPLATE_PLAN/plan.md"
cat > "$TEMPLATE_ITEM/meta.yml" <<'EOF'
stages:
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
EOF
set +e
template_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$TEMPLATE_PLAN" 2>&1)"
template_rc=$?
set -e
assert_neq "0" "$template_rc" "raw canonical template fails validation"
assert_contains "$template_output" "placeholder" "template failure identifies placeholders"
assert_contains "$template_output" "plan.md:" "template failure includes location"

CANONICAL_WORKSPACE="$TMP/canonical-workspace"
CANONICAL_ITEM="$CANONICAL_WORKSPACE/docs/work/canonical"
CANONICAL_PLAN="$CANONICAL_ITEM/plan"
mkdir -p "$CANONICAL_PLAN" "$CANONICAL_WORKSPACE/.git" "$CANONICAL_WORKSPACE/docs/reference"
printf 'Architecture fixture.\n' > "$CANONICAL_WORKSPACE/docs/reference/architecture map.md"
cat > "$CANONICAL_ITEM/prd.md" <<'EOF'
# Canonical fixture PRD

AC-001: The canonical fixture validates.
AC-0010: Longer identifier fixture.
EOF
cat > "$CANONICAL_ITEM/evidence.md" <<'EOF'
# Verification evidence

T01-PASS: prerequisite verification passed.
T02-PASS: dependent verification passed.
EOF
cat > "$CANONICAL_ITEM/meta.yml" <<'EOF'
slug: canonical
title: Canonical fixture
created_at: 2026-07-10T00:00:00+08:00
updated_at: 2026-07-10T00:00:00+08:00
status: active
stages:
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
inputs:
  - canonical-fixture
EOF
cat > "$CANONICAL_PLAN/plan.md" <<'EOF'
# Plan: canonical fixture

## Plan
- Format: canonical-v2
- Concurrency: 1
- Intent: Deliver a dependency-aware change.
- Scope: Two ordered tasks.
- Non-goals: No unrelated files.

## Sources
- local: ../prd.md#AC-001
- local: ../../../../docs/reference
- local: ../../../../docs/reference/architecture map.md
- user: decision:canonical-fixture
- external: https://example.com/issues/123

## Tasks

### T01 | prepare fixture
- Status: done
- Depends On: []

#### Intent
Create the prerequisite behavior.

#### Expected Result
The prerequisite is available.

#### Definition of Done
- The prerequisite check passes.

#### Verification
- Run the prerequisite check.

#### Verification Evidence
- PASS | local:../evidence.md#T01-PASS | Run the prerequisite check.

### T02 | consume fixture
- Status: pending
- Depends On: [T01]

#### Intent
Use the prerequisite behavior.

#### Expected Result
The final behavior is observable.

#### Definition of Done
- The final check passes.

#### Verification
- Run the final check.

## Change Log
- 2026-07-10: Created the canonical fixture.
EOF

if python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$CANONICAL_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: canonical-v2 plan passes validation"
else
  fail "canonical-v2 plan passes validation"
fi

# Real type/markup syntax in code spans and fences is not a template placeholder.
GENERIC_ROOT="$TMP/generic-markup"
cp -R "$CANONICAL_WORKSPACE" "$GENERIC_ROOT"
GENERIC_PLAN="$GENERIC_ROOT/docs/work/canonical/plan/plan.md"
perl -0pi -e 's/The final behavior is observable\./The final behavior returns `Map<String, Object>` and `Promise<string>`.\n\n```tsx\nconst view = <Widget \/>\nconst intrinsic = <div>ready<\/div>\nconst icon = <svg><path d="M0 0" \/><\/svg>\n```/' "$GENERIC_PLAN"
set +e
generic_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$GENERIC_PLAN")" 2>&1)"
generic_rc=$?
set -e
assert_eq "0" "$generic_rc" "canonical Plan accepts generics and JSX by fenced language context"

# Placeholder-shaped values still fail in prose and runnable shell examples.
PROSE_PLACEHOLDER_ROOT="$TMP/prose-angle-placeholder"
cp -R "$CANONICAL_WORKSPACE" "$PROSE_PLACEHOLDER_ROOT"
PROSE_PLACEHOLDER_PLAN="$PROSE_PLACEHOLDER_ROOT/docs/work/canonical/plan/plan.md"
perl -0pi -e 's/Deliver a dependency-aware change\./Deliver a <project root> change./' "$PROSE_PLACEHOLDER_PLAN"
set +e
prose_placeholder_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$PROSE_PLACEHOLDER_PLAN")" 2>&1)"
prose_placeholder_rc=$?
set -e
assert_neq "0" "$prose_placeholder_rc" "prose angle-bracket placeholders fail validation"
assert_contains "$prose_placeholder_output" "angle-bracket value" "prose placeholder failure names the reason"

SHELL_PLACEHOLDER_ROOT="$TMP/shell-angle-placeholder"
cp -R "$CANONICAL_WORKSPACE" "$SHELL_PLACEHOLDER_ROOT"
SHELL_PLACEHOLDER_PLAN="$SHELL_PLACEHOLDER_ROOT/docs/work/canonical/plan/plan.md"
perl -0pi -e 's/The final behavior is observable\./Run the QA command.\n\n```sh\nbash <qa-skill-dir>\/scripts\/run-qa.sh\n```/' "$SHELL_PLACEHOLDER_PLAN"
set +e
shell_placeholder_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$SHELL_PLACEHOLDER_PLAN")" 2>&1)"
shell_placeholder_rc=$?
set -e
assert_neq "0" "$shell_placeholder_rc" "runnable shell placeholders fail validation"
assert_contains "$shell_placeholder_output" "angle-bracket value" "shell placeholder failure names the reason"

INLINE_PLACEHOLDER_ROOT="$TMP/inline-angle-placeholder"
cp -R "$CANONICAL_WORKSPACE" "$INLINE_PLACEHOLDER_ROOT"
INLINE_PLACEHOLDER_PLAN="$INLINE_PLACEHOLDER_ROOT/docs/work/canonical/plan/plan.md"
perl -0pi -e 's/The final behavior is observable\./Run `bash <qa-skill-dir>\/scripts\/run-qa.sh`./' "$INLINE_PLACEHOLDER_PLAN"
set +e
inline_placeholder_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$INLINE_PLACEHOLDER_PLAN")" 2>&1)"
inline_placeholder_rc=$?
set -e
assert_neq "0" "$inline_placeholder_rc" "inline runnable placeholders fail validation"
assert_contains "$inline_placeholder_output" "angle-bracket value" "inline placeholder failure names the reason"

DUPLICATE_PLAN_TITLE_ROOT="$TMP/duplicate-plan-title"
cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_PLAN_TITLE_ROOT"
DUPLICATE_PLAN_TITLE="$DUPLICATE_PLAN_TITLE_ROOT/docs/work/canonical/plan/plan.md"
printf '\n# Plan: conflicting title\n' >> "$DUPLICATE_PLAN_TITLE"
set +e
duplicate_title_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$DUPLICATE_PLAN_TITLE")" 2>&1)"
duplicate_title_rc=$?
set -e
assert_neq "0" "$duplicate_title_rc" "canonical Plan rejects duplicate plan titles"
assert_contains "$duplicate_title_output" 'exactly one `# Plan:` title' "duplicate plan title error is actionable"

for section in Plan Sources Tasks 'Change Log'; do
  DUPLICATE_TOP_SECTION_ROOT="$TMP/duplicate-top-${section// /-}"
  cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_TOP_SECTION_ROOT"
  duplicate_plan="$DUPLICATE_TOP_SECTION_ROOT/docs/work/canonical/plan/plan.md"
  printf '\n## %s\n\n- conflicting duplicate content\n' "$section" >> "$duplicate_plan"
  set +e
  duplicate_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$duplicate_plan")" 2>&1)"
  duplicate_rc=$?
  set -e
  assert_neq "0" "$duplicate_rc" "canonical Plan rejects duplicate $section section"
  assert_contains "$duplicate_output" "section \`## $section\` appears 2 times" "duplicate $section section error is actionable"
done

ROGUE_TASK_HEADING_ROOT="$TMP/rogue-task-heading"
cp -R "$CANONICAL_WORKSPACE" "$ROGUE_TASK_HEADING_ROOT"
ROGUE_TASK_HEADING_PLAN="$ROGUE_TASK_HEADING_ROOT/docs/work/canonical/plan/plan.md"
perl -0pi -e 's/\n## Change Log/\n### Rogue task\n\n- Status: done\n\n## Change Log/' "$ROGUE_TASK_HEADING_PLAN"
set +e
rogue_task_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$ROGUE_TASK_HEADING_PLAN")" 2>&1)"
rogue_task_rc=$?
set -e
assert_neq "0" "$rogue_task_rc" "canonical Plan rejects non-canonical task headings"
assert_contains "$rogue_task_output" "non-canonical task heading" "rogue task heading error is actionable"

for field in Format Concurrency Intent Scope Non-goals; do
  DUPLICATE_PLAN_FIELD_ROOT="$TMP/duplicate-plan-${field// /-}"
  cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_PLAN_FIELD_ROOT"
  duplicate_plan="$DUPLICATE_PLAN_FIELD_ROOT/docs/work/canonical/plan/plan.md"
  sed -i.bak "/^- $field:/p" "$duplicate_plan"
  rm -f "$duplicate_plan.bak"
  set +e
  duplicate_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$duplicate_plan")" 2>&1)"
  duplicate_rc=$?
  set -e
  assert_neq "0" "$duplicate_rc" "canonical Plan rejects duplicate $field"
  assert_contains "$duplicate_output" "Plan field $field" "duplicate $field error is actionable"
done

for field in Status 'Depends On' 'Blocker Reason' 'Blocker Ref' 'Unblocked Ref'; do
  DUPLICATE_TASK_FIELD_ROOT="$TMP/duplicate-task-${field// /-}"
  cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_TASK_FIELD_ROOT"
  duplicate_plan="$DUPLICATE_TASK_FIELD_ROOT/docs/work/canonical/plan/plan.md"
  if ! grep -q "^- $field:" "$duplicate_plan"; then
    sed -i.bak "/^- Depends On: \[T01\]/a\\
- $field: external:duplicate-fixture" "$duplicate_plan"
    rm -f "$duplicate_plan.bak"
  fi
  sed -i.bak "/^- $field:/p" "$duplicate_plan"
  rm -f "$duplicate_plan.bak"
  set +e
  duplicate_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$duplicate_plan")" 2>&1)"
  duplicate_rc=$?
  set -e
  assert_neq "0" "$duplicate_rc" "canonical task rejects duplicate $field"
  assert_contains "$duplicate_output" "task field $field" "duplicate task $field error is actionable"
done

for subsection in Intent 'Expected Result' 'Definition of Done' Verification 'Verification Evidence'; do
  DUPLICATE_SUBSECTION_ROOT="$TMP/duplicate-subsection-${subsection// /-}"
  cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_SUBSECTION_ROOT"
  duplicate_plan="$DUPLICATE_SUBSECTION_ROOT/docs/work/canonical/plan/plan.md"
  sed -i.bak "/^#### $subsection$/p" "$duplicate_plan"
  rm -f "$duplicate_plan.bak"
  set +e
  duplicate_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$(dirname "$duplicate_plan")" 2>&1)"
  duplicate_rc=$?
  set -e
  assert_neq "0" "$duplicate_rc" "canonical task rejects duplicate $subsection subsection"
  assert_contains "$duplicate_output" "task subsection $subsection" "duplicate $subsection subsection error is actionable"
done

DUPLICATE_DEPENDENCY_ROOT="$TMP/duplicate-dependency-entry"
cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_DEPENDENCY_ROOT"
DUPLICATE_DEPENDENCY_PLAN="$DUPLICATE_DEPENDENCY_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Depends On: \[T01\]/- Depends On: [T01,T01]/' "$DUPLICATE_DEPENDENCY_PLAN/plan.md"
set +e
duplicate_dependency_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$DUPLICATE_DEPENDENCY_PLAN" 2>&1)"
duplicate_dependency_rc=$?
set -e
assert_neq "0" "$duplicate_dependency_rc" "canonical task rejects duplicate dependency IDs"
assert_contains "$duplicate_dependency_output" "duplicate dependencies" "duplicate dependency error is actionable"

RETIRED_LITE_ROOT="$TMP/retired-lite-v1"
cp -R "$CANONICAL_WORKSPACE" "$RETIRED_LITE_ROOT"
RETIRED_LITE_PLAN="$RETIRED_LITE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Format: canonical-v2/- Format: lite-v1/' "$RETIRED_LITE_PLAN/plan.md"
set +e
retired_lite_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$RETIRED_LITE_PLAN" 2>&1)"
retired_lite_rc=$?
set -e
assert_neq "0" "$retired_lite_rc" "lite-v1 is rejected in v0.7"
assert_contains "$retired_lite_output" 'requires Format `canonical-v2`' "single canonical format error is actionable"

WRAPPED_VERIFICATION_ROOT="$TMP/canonical-wrapped-verification"
cp -R "$CANONICAL_WORKSPACE" "$WRAPPED_VERIFICATION_ROOT"
WRAPPED_VERIFICATION_PLAN="$WRAPPED_VERIFICATION_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Run the prerequisite check\./- Run the prerequisite\n  check./' "$WRAPPED_VERIFICATION_PLAN/plan.md"
if python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$WRAPPED_VERIFICATION_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: wrapped Verification command matches complete evidence command"
else
  fail "wrapped Verification command matches complete evidence command"
fi

CANONICAL_MISSING_DOD_ROOT="$TMP/canonical-missing-dod"
cp -R "$CANONICAL_WORKSPACE" "$CANONICAL_MISSING_DOD_ROOT"
CANONICAL_MISSING_DOD="$CANONICAL_MISSING_DOD_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/\n#### Definition of Done\n.*?(?=\n#### Verification)//s' "$CANONICAL_MISSING_DOD/plan.md"
set +e
canonical_dod_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$CANONICAL_MISSING_DOD" 2>&1)"
canonical_dod_rc=$?
set -e
assert_neq "0" "$canonical_dod_rc" "canonical-v2 requires Definition of Done"
assert_contains "$canonical_dod_output" "Definition of Done" "canonical-v2 missing DoD is actionable"

DONE_WITHOUT_EVIDENCE_ROOT="$TMP/canonical-done-without-evidence"
cp -R "$CANONICAL_WORKSPACE" "$DONE_WITHOUT_EVIDENCE_ROOT"
DONE_WITHOUT_EVIDENCE_PLAN="$DONE_WITHOUT_EVIDENCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/\n#### Verification Evidence\n- PASS \| local:\.\.\/evidence\.md#T01-PASS \| Run the prerequisite check\.//s' "$DONE_WITHOUT_EVIDENCE_PLAN/plan.md"
set +e
done_without_evidence_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$DONE_WITHOUT_EVIDENCE_PLAN" 2>&1)"
done_without_evidence_rc=$?
set -e
assert_neq "0" "$done_without_evidence_rc" "done canonical task requires verification evidence"
assert_contains "$done_without_evidence_output" "Verification Evidence" "missing done evidence error is actionable"

MISMATCHED_EVIDENCE_ROOT="$TMP/canonical-mismatched-evidence"
cp -R "$CANONICAL_WORKSPACE" "$MISMATCHED_EVIDENCE_ROOT"
MISMATCHED_EVIDENCE_PLAN="$MISMATCHED_EVIDENCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/Run the prerequisite check\.\n\n### T02/Run a different check.\n\n### T02/' "$MISMATCHED_EVIDENCE_PLAN/plan.md"
set +e
mismatched_evidence_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MISMATCHED_EVIDENCE_PLAN" 2>&1)"
mismatched_evidence_rc=$?
set -e
assert_neq "0" "$mismatched_evidence_rc" "verification evidence must match a declared command"
assert_contains "$mismatched_evidence_output" "does not match Verification" "mismatched evidence error is actionable"

MISSING_EVIDENCE_REF_ROOT="$TMP/canonical-missing-evidence-ref"
cp -R "$CANONICAL_WORKSPACE" "$MISSING_EVIDENCE_REF_ROOT"
MISSING_EVIDENCE_REF_PLAN="$MISSING_EVIDENCE_REF_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#local:\.\./evidence\.md#local:../missing-evidence.md#' "$MISSING_EVIDENCE_REF_PLAN/plan.md"
set +e
missing_evidence_ref_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MISSING_EVIDENCE_REF_PLAN" 2>&1)"
missing_evidence_ref_rc=$?
set -e
assert_neq "0" "$missing_evidence_ref_rc" "verification evidence requires a durable existing reference"
assert_contains "$missing_evidence_ref_output" "does not exist" "missing evidence reference is actionable"

FAILED_EVIDENCE_ROOT="$TMP/canonical-failed-evidence"
cp -R "$CANONICAL_WORKSPACE" "$FAILED_EVIDENCE_ROOT"
FAILED_EVIDENCE_PLAN="$FAILED_EVIDENCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- PASS \| local:\.\./- FAIL | local:../' "$FAILED_EVIDENCE_PLAN/plan.md"
set +e
failed_evidence_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$FAILED_EVIDENCE_PLAN" 2>&1)"
failed_evidence_rc=$?
set -e
assert_neq "0" "$failed_evidence_rc" "done task rejects failed verification evidence"
assert_contains "$failed_evidence_output" "requires PASS evidence" "failed evidence error is actionable"

USER_EVIDENCE_ROOT="$TMP/canonical-user-evidence"
cp -R "$CANONICAL_WORKSPACE" "$USER_EVIDENCE_ROOT"
USER_EVIDENCE_PLAN="$USER_EVIDENCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#local:\.\./evidence\.md#user:claimed-pass#' "$USER_EVIDENCE_PLAN/plan.md"
set +e
user_evidence_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$USER_EVIDENCE_PLAN" 2>&1)"
user_evidence_rc=$?
set -e
assert_neq "0" "$user_evidence_rc" "done task rejects user assertion as execution evidence"
assert_contains "$user_evidence_output" "cannot use a user reference" "user evidence rejection is actionable"

INVALID_CONCURRENCY_ROOT="$TMP/canonical-invalid-concurrency"
cp -R "$CANONICAL_WORKSPACE" "$INVALID_CONCURRENCY_ROOT"
INVALID_CONCURRENCY_PLAN="$INVALID_CONCURRENCY_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Concurrency: 1/- Concurrency: 0/' "$INVALID_CONCURRENCY_PLAN/plan.md"
set +e
invalid_concurrency_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$INVALID_CONCURRENCY_PLAN" 2>&1)"
invalid_concurrency_rc=$?
set -e
assert_neq "0" "$invalid_concurrency_rc" "canonical concurrency must be positive"
assert_contains "$invalid_concurrency_output" "Concurrency" "invalid concurrency error names the field"

CONCURRENCY_LIMIT_ROOT="$TMP/canonical-concurrency-limit"
cp -R "$CANONICAL_WORKSPACE" "$CONCURRENCY_LIMIT_ROOT"
CONCURRENCY_LIMIT_PLAN="$CONCURRENCY_LIMIT_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Status: done/- Status: in_progress/; s/- Status: pending/- Status: in_progress/; s/- Depends On: \[T01\]/- Depends On: []/' "$CONCURRENCY_LIMIT_PLAN/plan.md"
set +e
concurrency_limit_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$CONCURRENCY_LIMIT_PLAN" 2>&1)"
concurrency_limit_rc=$?
set -e
assert_neq "0" "$concurrency_limit_rc" "canonical concurrency limits in-progress tasks"
assert_contains "$concurrency_limit_output" "in_progress tasks exceed Concurrency" "concurrency overflow is actionable"

CONCURRENCY_TWO_ROOT="$TMP/canonical-concurrency-two"
cp -R "$CONCURRENCY_LIMIT_ROOT" "$CONCURRENCY_TWO_ROOT"
CONCURRENCY_TWO_PLAN="$CONCURRENCY_TWO_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Concurrency: 1/- Concurrency: 2/' "$CONCURRENCY_TWO_PLAN/plan.md"
if python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$CONCURRENCY_TWO_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: explicit concurrency permits bounded parallel work"
else
  fail "explicit concurrency permits bounded parallel work"
fi

SAFE_DEFAULT_ROOT="$TMP/canonical-safe-concurrency-default"
cp -R "$CANONICAL_WORKSPACE" "$SAFE_DEFAULT_ROOT"
SAFE_DEFAULT_PLAN="$SAFE_DEFAULT_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/^- Concurrency: 1\n//m' "$SAFE_DEFAULT_PLAN/plan.md"
safe_default_status="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$SAFE_DEFAULT_PLAN" --json 2>&1)"
assert_contains "$safe_default_status" '"limit": 1' "missing concurrency metadata safely defaults to one"

EARLY_ACTIVE_ROOT="$TMP/canonical-early-active"
cp -R "$CANONICAL_WORKSPACE" "$EARLY_ACTIVE_ROOT"
EARLY_ACTIVE_PLAN="$EARLY_ACTIVE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Status: done/- Status: pending/; s/(### T02 .*?- Status:) pending/$1 in_progress/s' "$EARLY_ACTIVE_PLAN/plan.md"
set +e
early_active_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$EARLY_ACTIVE_PLAN" 2>&1)"
early_active_rc=$?
set -e
assert_neq "0" "$early_active_rc" "in-progress task requires completed dependencies"
assert_contains "$early_active_output" "unmet dependencies" "early active dependency error is actionable"

BLOCKED_MISSING_STRUCTURE_ROOT="$TMP/canonical-blocked-missing-structure"
cp -R "$CANONICAL_WORKSPACE" "$BLOCKED_MISSING_STRUCTURE_ROOT"
BLOCKED_MISSING_STRUCTURE_PLAN="$BLOCKED_MISSING_STRUCTURE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Status: pending/- Status: blocked/' "$BLOCKED_MISSING_STRUCTURE_PLAN/plan.md"
set +e
blocked_missing_structure_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$BLOCKED_MISSING_STRUCTURE_PLAN" 2>&1)"
blocked_missing_structure_rc=$?
set -e
assert_neq "0" "$blocked_missing_structure_rc" "blocked task requires structured reason and reference"
assert_contains "$blocked_missing_structure_output" "Blocker Reason" "missing blocker structure is actionable"

INVALID_BLOCKER_REF_ROOT="$TMP/canonical-invalid-blocker-ref"
cp -R "$CANONICAL_WORKSPACE" "$INVALID_BLOCKER_REF_ROOT"
INVALID_BLOCKER_REF_PLAN="$INVALID_BLOCKER_REF_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Status: pending\n- Depends On: \[T01\]/- Status: blocked\n- Depends On: [T01]\n- Blocker Reason: Waiting for approval\n- Blocker Ref: untyped prose/' "$INVALID_BLOCKER_REF_PLAN/plan.md"
set +e
invalid_blocker_ref_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$INVALID_BLOCKER_REF_PLAN" 2>&1)"
invalid_blocker_ref_rc=$?
set -e
assert_neq "0" "$invalid_blocker_ref_rc" "blocked task requires a typed durable reference"
assert_contains "$invalid_blocker_ref_output" "typed local, user, or external reference" "invalid blocker reference is actionable"

CLEARED_MISSING_REF_ROOT="$TMP/canonical-cleared-missing-ref"
cp -R "$CANONICAL_WORKSPACE" "$CLEARED_MISSING_REF_ROOT"
CLEARED_MISSING_REF_PLAN="$CLEARED_MISSING_REF_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Status: pending\n- Depends On: \[T01\]/- Status: pending\n- Depends On: [T01]\n- Blocker Reason: Waiting for approval\n- Blocker Ref: external:ticket-123/' "$CLEARED_MISSING_REF_PLAN/plan.md"
set +e
cleared_missing_ref_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$CLEARED_MISSING_REF_PLAN" 2>&1)"
cleared_missing_ref_rc=$?
set -e
assert_neq "0" "$cleared_missing_ref_rc" "cleared blocker requires structured unblock reference"
assert_contains "$cleared_missing_ref_output" "Unblocked Ref" "missing unblock reference is actionable"

MISSING_SOURCE_ROOT="$TMP/canonical-missing-source"
cp -R "$CANONICAL_WORKSPACE" "$MISSING_SOURCE_ROOT"
MISSING_SOURCE_PLAN="$MISSING_SOURCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#- local: ../prd\.md#- local: ../missing.md#' "$MISSING_SOURCE_PLAN/plan.md"
set +e
missing_source_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MISSING_SOURCE_PLAN" 2>&1)"
missing_source_rc=$?
set -e
assert_neq "0" "$missing_source_rc" "canonical local source must exist"
assert_contains "$missing_source_output" "does not exist" "missing local source error is actionable"

MISSING_ANCHOR_ROOT="$TMP/canonical-missing-anchor"
cp -R "$CANONICAL_WORKSPACE" "$MISSING_ANCHOR_ROOT"
MISSING_ANCHOR_PLAN="$MISSING_ANCHOR_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/#AC-001/#AC-999/' "$MISSING_ANCHOR_PLAN/plan.md"
set +e
missing_anchor_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MISSING_ANCHOR_PLAN" 2>&1)"
missing_anchor_rc=$?
set -e
assert_neq "0" "$missing_anchor_rc" "canonical local source anchor must exist"
assert_contains "$missing_anchor_output" 'anchor `AC-999`' "missing anchor error names the literal ID"

ANCHOR_BOUNDARY_ROOT="$TMP/canonical-anchor-boundary"
cp -R "$CANONICAL_WORKSPACE" "$ANCHOR_BOUNDARY_ROOT"
ANCHOR_BOUNDARY_PLAN="$ANCHOR_BOUNDARY_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/^AC-001:.*\n//m' "$ANCHOR_BOUNDARY_ROOT/docs/work/canonical/prd.md"
set +e
anchor_boundary_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$ANCHOR_BOUNDARY_PLAN" 2>&1)"
anchor_boundary_rc=$?
set -e
assert_neq "0" "$anchor_boundary_rc" "source anchor requires an exact literal-ID boundary"
assert_contains "$anchor_boundary_output" 'anchor `AC-001`' "substring-only anchor failure names the literal ID"

MISSING_META_ROOT="$TMP/canonical-missing-meta"
cp -R "$CANONICAL_WORKSPACE" "$MISSING_META_ROOT"
MISSING_META_PLAN="$MISSING_META_ROOT/docs/work/canonical/plan"
rm "$MISSING_META_ROOT/docs/work/canonical/meta.yml"
set +e
missing_meta_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MISSING_META_PLAN" 2>&1)"
missing_meta_rc=$?
set -e
assert_neq "0" "$missing_meta_rc" "canonical-v2 requires sibling meta.yml"
assert_contains "$missing_meta_output" "meta.yml" "missing metadata error names meta.yml"

WRONG_STAGE_ROOT="$TMP/canonical-wrong-stage"
cp -R "$CANONICAL_WORKSPACE" "$WRONG_STAGE_ROOT"
WRONG_STAGE_PLAN="$WRONG_STAGE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/skill: plan-sync/skill: spec/' "$WRONG_STAGE_ROOT/docs/work/canonical/meta.yml"
set +e
wrong_stage_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$WRONG_STAGE_PLAN" 2>&1)"
wrong_stage_rc=$?
set -e
assert_neq "0" "$wrong_stage_rc" "canonical meta plan stage requires plan-sync skill"
assert_contains "$wrong_stage_output" 'skill `plan-sync`' "wrong plan stage skill is actionable"

WRONG_STAGE_FILE_ROOT="$TMP/canonical-wrong-stage-file"
cp -R "$CANONICAL_WORKSPACE" "$WRONG_STAGE_FILE_ROOT"
WRONG_STAGE_FILE_PLAN="$WRONG_STAGE_FILE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#file: plan/plan\.md#file: plan/other.md#' "$WRONG_STAGE_FILE_ROOT/docs/work/canonical/meta.yml"
set +e
wrong_stage_file_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$WRONG_STAGE_FILE_PLAN" 2>&1)"
wrong_stage_file_rc=$?
set -e
assert_neq "0" "$wrong_stage_file_rc" "canonical meta plan stage must resolve to current plan"
assert_contains "$wrong_stage_file_output" "current plan.md" "wrong plan stage file is actionable"

DUPLICATE_STAGE_ROOT="$TMP/canonical-duplicate-stage"
cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_STAGE_ROOT"
DUPLICATE_STAGE_PLAN="$DUPLICATE_STAGE_ROOT/docs/work/canonical/plan"
cat >> "$DUPLICATE_STAGE_ROOT/docs/work/canonical/meta.yml" <<'EOF'
stages:
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
EOF
set +e
duplicate_stage_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$DUPLICATE_STAGE_PLAN" 2>&1)"
duplicate_stage_rc=$?
set -e
assert_neq "0" "$duplicate_stage_rc" "canonical meta rejects duplicate plan stages"
assert_contains "$duplicate_stage_output" "exactly one plan stage" "duplicate plan-stage error is actionable"

MISSING_STAGE_ROOT="$TMP/canonical-missing-stage"
cp -R "$CANONICAL_WORKSPACE" "$MISSING_STAGE_ROOT"
MISSING_STAGE_PLAN="$MISSING_STAGE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/^  plan:.*\n//m' "$MISSING_STAGE_ROOT/docs/work/canonical/meta.yml"
set +e
missing_stage_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MISSING_STAGE_PLAN" 2>&1)"
missing_stage_rc=$?
set -e
assert_neq "0" "$missing_stage_rc" "canonical meta requires exactly one plan stage"
assert_contains "$missing_stage_output" "found 0" "missing plan-stage error reports the count"

DIRECTORY_ANCHOR_ROOT="$TMP/canonical-directory-anchor"
cp -R "$CANONICAL_WORKSPACE" "$DIRECTORY_ANCHOR_ROOT"
DIRECTORY_ANCHOR_PLAN="$DIRECTORY_ANCHOR_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#- local: ../../../../docs/reference#- local: ../../../../docs/reference\#REF-001#' "$DIRECTORY_ANCHOR_PLAN/plan.md"
set +e
directory_anchor_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$DIRECTORY_ANCHOR_PLAN" 2>&1)"
directory_anchor_rc=$?
set -e
assert_neq "0" "$directory_anchor_rc" "canonical directory source cannot carry an anchor"
assert_contains "$directory_anchor_output" "directory source cannot use an anchor" "directory anchor error is actionable"

ABSOLUTE_SOURCE_ROOT="$TMP/canonical-absolute-source"
cp -R "$CANONICAL_WORKSPACE" "$ABSOLUTE_SOURCE_ROOT"
ABSOLUTE_SOURCE_PLAN="$ABSOLUTE_SOURCE_ROOT/docs/work/canonical/plan"
absolute_source="$ABSOLUTE_SOURCE_ROOT/docs/work/canonical/prd.md"
perl -0pi -e "s#- local: ../prd\\.md#- local: $absolute_source#" "$ABSOLUTE_SOURCE_PLAN/plan.md"
set +e
absolute_source_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$ABSOLUTE_SOURCE_PLAN" 2>&1)"
absolute_source_rc=$?
set -e
assert_neq "0" "$absolute_source_rc" "canonical local source rejects absolute paths"
assert_contains "$absolute_source_output" "must be relative" "absolute source error is actionable"

printf 'outside workspace\n' > "$TMP/outside.md"
ESCAPE_SOURCE_ROOT="$TMP/canonical-escape-source"
cp -R "$CANONICAL_WORKSPACE" "$ESCAPE_SOURCE_ROOT"
ESCAPE_SOURCE_PLAN="$ESCAPE_SOURCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#- local: ../prd\.md#- local: ../../../../../outside.md#' "$ESCAPE_SOURCE_PLAN/plan.md"
set +e
escape_source_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$ESCAPE_SOURCE_PLAN" 2>&1)"
escape_source_rc=$?
set -e
assert_neq "0" "$escape_source_rc" "canonical local source rejects Git-workspace escape"
assert_contains "$escape_source_output" "escapes Git workspace" "workspace escape error is actionable"

SYMLINK_SOURCE_ROOT="$TMP/canonical-symlink-source"
cp -R "$CANONICAL_WORKSPACE" "$SYMLINK_SOURCE_ROOT"
SYMLINK_SOURCE_PLAN="$SYMLINK_SOURCE_ROOT/docs/work/canonical/plan"
ln -s "$TMP/outside.md" "$SYMLINK_SOURCE_ROOT/docs/reference/escaped.md"
perl -0pi -e 's#- local: ../prd\.md#- local: ../../../../docs/reference/escaped.md#' "$SYMLINK_SOURCE_PLAN/plan.md"
set +e
symlink_source_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$SYMLINK_SOURCE_PLAN" 2>&1)"
symlink_source_rc=$?
set -e
assert_neq "0" "$symlink_source_rc" "canonical local source rejects symlink escape"
assert_contains "$symlink_source_output" "escapes Git workspace" "symlink escape error is actionable"

PROSE_SOURCE_ROOT="$TMP/canonical-prose-source"
cp -R "$CANONICAL_WORKSPACE" "$PROSE_SOURCE_ROOT"
PROSE_SOURCE_PLAN="$PROSE_SOURCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#- local: ../prd\.md#- PRD: `../prd.md`#' "$PROSE_SOURCE_PLAN/plan.md"
set +e
prose_source_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$PROSE_SOURCE_PLAN" 2>&1)"
prose_source_rc=$?
set -e
assert_neq "0" "$prose_source_rc" "canonical Sources reject labels and backticks"
assert_contains "$prose_source_output" "typed source" "source syntax error describes the typed contract"

MULTIPLE_SOURCE_ROOT="$TMP/canonical-multiple-source"
cp -R "$CANONICAL_WORKSPACE" "$MULTIPLE_SOURCE_ROOT"
MULTIPLE_SOURCE_PLAN="$MULTIPLE_SOURCE_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#- local: ../prd\.md#- local: ../prd.md, ../prd.md#' "$MULTIPLE_SOURCE_PLAN/plan.md"
set +e
multiple_source_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MULTIPLE_SOURCE_PLAN" 2>&1)"
multiple_source_rc=$?
set -e
assert_neq "0" "$multiple_source_rc" "canonical local source does not guess among multiple paths"

INVALID_EXTERNAL_ROOT="$TMP/canonical-invalid-external"
cp -R "$CANONICAL_WORKSPACE" "$INVALID_EXTERNAL_ROOT"
INVALID_EXTERNAL_PLAN="$INVALID_EXTERNAL_ROOT/docs/work/canonical/plan"
perl -0pi -e 's#https://example\.com/issues/123#https://example.com/one https://example.com/two#' "$INVALID_EXTERNAL_PLAN/plan.md"
set +e
invalid_external_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$INVALID_EXTERNAL_PLAN" 2>&1)"
invalid_external_rc=$?
set -e
assert_neq "0" "$invalid_external_rc" "canonical external source is one URL or opaque ID"
assert_contains "$invalid_external_output" "URL or durable opaque ID" "invalid external source error is actionable"

set +e
planctl_check_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$MISSING_SOURCE_PLAN" 2>&1)"
planctl_check_rc=$?
planctl_invalid_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$MISSING_SOURCE_PLAN" --json 2>&1)"
planctl_invalid_rc=$?
set -e
assert_neq "0" "$planctl_check_rc" "planctl check propagates invalid canonical plan"
assert_contains "$planctl_check_output" "does not exist" "planctl check propagates validation details"
assert_neq "0" "$planctl_invalid_rc" "planctl status propagates invalid canonical plan"
assert_contains "$planctl_invalid_output" "does not exist" "planctl status propagates validation details"
assert_contains "$planctl_invalid_output" '"active_task": null' "invalid canonical plan has no actionable task"
assert_contains "$planctl_invalid_output" '"ready_tasks": []' "invalid canonical plan fails ready state closed"

NON_UTF8_ROOT="$TMP/non-utf8-plan"
cp -R "$CANONICAL_WORKSPACE" "$NON_UTF8_ROOT"
NON_UTF8_PLAN="$NON_UTF8_ROOT/docs/work/canonical/plan"
printf '\377\376\n' > "$NON_UTF8_PLAN/plan.md"
set +e
non_utf8_check_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$NON_UTF8_PLAN" 2>&1)"
non_utf8_check_rc=$?
non_utf8_status_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$NON_UTF8_PLAN" --json 2>&1)"
non_utf8_status_rc=$?
set -e
assert_neq "0" "$non_utf8_check_rc" "planctl check fails closed on non-UTF-8 plans"
assert_neq "0" "$non_utf8_status_rc" "planctl status fails closed on non-UTF-8 plans"
assert_not_contains "$non_utf8_check_output" "Traceback" "planctl check contains plan read errors"
assert_not_contains "$non_utf8_status_output" "Traceback" "planctl status contains plan read errors"
assert_contains "$non_utf8_check_output" "cannot read plan artifacts" "planctl check reports a compact read error"
assert_contains "$non_utf8_status_output" "cannot read plan artifacts" "planctl status reports a compact read error"

UNKNOWN_DEP_ROOT="$TMP/unknown-dependency"
cp -R "$CANONICAL_WORKSPACE" "$UNKNOWN_DEP_ROOT"
UNKNOWN_DEP_PLAN="$UNKNOWN_DEP_ROOT/docs/work/canonical/plan"
perl -0pi -e 's/- Depends On: \[T01\]/- Depends On: [T999]/' "$UNKNOWN_DEP_PLAN/plan.md"
set +e
unknown_dep_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$UNKNOWN_DEP_PLAN" 2>&1)"
unknown_dep_rc=$?
set -e
assert_neq "0" "$unknown_dep_rc" "unknown dependency is rejected"
assert_contains "$unknown_dep_output" 'unknown dependency `T999`' "unknown dependency error names the task"

CYCLE_PLAN="$TMP/dependency-cycle"
cp -R "$CANONICAL_WORKSPACE" "$CYCLE_PLAN"
CYCLE_PLAN="$CYCLE_PLAN/docs/work/canonical/plan"
perl -0pi -e 's/(### T01 .*?- Depends On:) \[[^\n]*\]/$1 [T02]/s' "$CYCLE_PLAN/plan.md"
set +e
cycle_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$CYCLE_PLAN" 2>&1)"
cycle_rc=$?
set -e
assert_neq "0" "$cycle_rc" "dependency cycle is rejected"
assert_contains "$cycle_output" "dependency cycle" "cycle error explains the path"

MALFORMED_JOURNAL_ROOT="$TMP/canonical-malformed-journal"
cp -R "$CANONICAL_WORKSPACE" "$MALFORMED_JOURNAL_ROOT"
MALFORMED_JOURNAL_PLAN="$MALFORMED_JOURNAL_ROOT/docs/work/canonical/plan"
cat > "$MALFORMED_JOURNAL_PLAN/journal.md" <<'EOF'
# Journal: canonical fixture

## Events

- malformed journal event
EOF
set +e
malformed_journal_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$MALFORMED_JOURNAL_PLAN" 2>&1)"
malformed_journal_rc=$?
set -e
assert_neq "0" "$malformed_journal_rc" "malformed canonical journal event is rejected"
assert_contains "$malformed_journal_output" "malformed event" "malformed journal error is actionable"

DUPLICATE_JOURNAL_ROOT="$TMP/canonical-duplicate-journal-shape"
cp -R "$CANONICAL_WORKSPACE" "$DUPLICATE_JOURNAL_ROOT"
DUPLICATE_JOURNAL_PLAN="$DUPLICATE_JOURNAL_ROOT/docs/work/canonical/plan"
cat > "$DUPLICATE_JOURNAL_PLAN/journal.md" <<'EOF'
# Journal: canonical fixture

## Events

- 2026-07-10T00:00:00+08:00 | decision | First record.

# Journal: conflicting title

## Events

- 2026-07-10T00:01:00+08:00 | decision | Conflicting record.
EOF
set +e
duplicate_journal_output="$(python3 "$REPO/plan-sync/scripts/validate_consistency.py" --plan-dir "$DUPLICATE_JOURNAL_PLAN" 2>&1)"
duplicate_journal_rc=$?
set -e
assert_neq "0" "$duplicate_journal_rc" "canonical journal rejects duplicate title and Events sections"
assert_contains "$duplicate_journal_output" 'exactly one `# Journal:` title' "duplicate journal title error is actionable"
assert_contains "$duplicate_journal_output" 'section `## Events` appears 2 times' "duplicate journal Events error is actionable"

GOAL_JOURNEY_ROOT="$TMP/goal-journey"
cp -R "$REPO/tests/fixtures/plan-sync-goal-journey" "$GOAL_JOURNEY_ROOT"
mkdir -p "$GOAL_JOURNEY_ROOT/.git"
GOAL_JOURNEY_ITEM="$GOAL_JOURNEY_ROOT/docs/work/goal-journey"
GOAL_JOURNEY_PLAN="$GOAL_JOURNEY_ITEM/plan"

if python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$GOAL_JOURNEY_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: neutral Goal journey create state validates"
else
  fail "neutral Goal journey create state validates"
fi
goal_create_status="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$GOAL_JOURNEY_PLAN" --json 2>&1)"
assert_contains "$goal_create_status" '"plan_state": "ready"' "create state is repository-ready"
assert_contains "$goal_create_status" '"active_task": "T01"' "dependencies select prerequisite despite document order"
assert_contains "$goal_create_status" '"ready_tasks"' "create state exposes ready tasks"
assert_contains "$goal_create_status" '"dependency_blocked"' "create state exposes dependency-blocked tasks"

perl -0pi -e 's/(### T01 .*?- Status:) pending\n- Depends On: \[\]/$1 blocked\n- Depends On: []\n- Blocker Reason: Waiting for explicit approval\n- Blocker Ref: external:ticket-123/s' "$GOAL_JOURNEY_PLAN/plan.md"
printf '%s\n' '- 2026-07-10T00:05:00+08:00 | blocker | T01 waits on external:ticket-123.' >> "$GOAL_JOURNEY_PLAN/journal.md"
if python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$GOAL_JOURNEY_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: neutral Goal journey structured drift validates"
else
  fail "neutral Goal journey structured drift validates"
fi
goal_drift_status="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$GOAL_JOURNEY_PLAN" --json 2>&1)"
assert_contains "$goal_drift_status" '"plan_state": "blocked"' "structured blocker drives blocked repository state"
assert_contains "$goal_drift_status" '"active_task": null' "dependency-blocked work is not selected active"
assert_contains "$goal_drift_status" '"Waiting for explicit approval"' "status carries structured blocker reason"

printf '%s\n' '- 2026-07-10T00:06:00+08:00 | decision | The blocker is resolved in prose only.' >> "$GOAL_JOURNEY_PLAN/journal.md"
goal_prose_status="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$GOAL_JOURNEY_PLAN" --json 2>&1)"
assert_contains "$goal_prose_status" '"plan_state": "blocked"' "prose cannot clear a structured blocker"
assert_contains "$goal_prose_status" '"active_task": null' "prose-only unblock leaves task non-actionable"

perl -0pi -e 's/- Status: blocked\n- Depends On: \[\]\n- Blocker Reason: Waiting for explicit approval\n- Blocker Ref: external:ticket-123/- Status: pending\n- Depends On: []\n- Blocker Reason: Waiting for explicit approval\n- Blocker Ref: external:ticket-123\n- Unblocked Ref: external:approval-456/' "$GOAL_JOURNEY_PLAN/plan.md"
if python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$GOAL_JOURNEY_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: neutral Goal journey structured resume validates"
else
  fail "neutral Goal journey structured resume validates"
fi
goal_resume_status="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$GOAL_JOURNEY_PLAN" --json 2>&1)"
assert_contains "$goal_resume_status" '"plan_state": "ready"' "structured unblock restores ready repository state"
assert_contains "$goal_resume_status" '"active_task": "T01"' "resume selects the prerequisite"

if (cd "$GOAL_JOURNEY_ROOT" && bash verify.sh T01); then
  printf '%s\n' 'T01-PASS: bash verify.sh T01 exited zero.' >> "$GOAL_JOURNEY_ITEM/evidence.md"
else
  fail "neutral Goal journey T01 verification command passes"
fi
perl -0pi -e 's/(### T01 .*?- Status:) pending/$1 done/s; s/(### T01 .*?#### Verification\n\n- bash verify\.sh T01)/$1\n\n#### Verification Evidence\n\n- PASS | local:..\/evidence.md#T01-PASS | bash verify.sh T01/s' "$GOAL_JOURNEY_PLAN/plan.md"
if python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$GOAL_JOURNEY_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: evidenced T01 completion validates"
else
  fail "evidenced T01 completion validates"
fi
goal_t01_status="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$GOAL_JOURNEY_PLAN" --json 2>&1)"
assert_contains "$goal_t01_status" '"active_task": "T02"' "T01 evidence makes dependent T02 ready"

if (cd "$GOAL_JOURNEY_ROOT" && bash verify.sh T02); then
  printf '%s\n' 'T02-PASS: bash verify.sh T02 exited zero.' >> "$GOAL_JOURNEY_ITEM/evidence.md"
else
  fail "neutral Goal journey T02 verification command passes"
fi
perl -0pi -e 's/(### T02 .*?- Status:) pending/$1 done/s; s/(### T02 .*?#### Verification\n\n- bash verify\.sh T02)/$1\n\n#### Verification Evidence\n\n- PASS | local:..\/evidence.md#T02-PASS | bash verify.sh T02/s' "$GOAL_JOURNEY_PLAN/plan.md"
if python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$GOAL_JOURNEY_PLAN" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: evidenced complete journey validates"
else
  fail "evidenced complete journey validates"
fi
goal_complete_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$GOAL_JOURNEY_PLAN" --goal-status 2>&1)"
assert_contains "$goal_complete_output" "plan_state=complete" "Goal status reports repository plan completion"
assert_contains "$goal_complete_output" "host_goal=unmanaged" "Goal status disclaims host lifecycle ownership"
assert_contains "$goal_complete_output" "active=none" "complete repository plan has no active task"
assert_not_contains "$goal_complete_output" "host_goal=complete" "repository status never claims host Goal completion"

goal_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" status --plan-dir "$CANONICAL_PLAN" --goal-status 2>&1)" || goal_rc=$?
goal_rc="${goal_rc:-0}"
assert_eq "0" "$goal_rc" "goal status command succeeds"
assert_contains "$goal_output" "goal-status" "goal status output is not labeled evidence"
assert_contains "$goal_output" "consistency=PASS" "goal status reports consistency"
assert_contains "$goal_output" "active=T02" "goal status reports the next active task"

set +e
retired_unlock_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" unlock --plan-dir "$CANONICAL_PLAN" 2>&1)"
retired_unlock_rc=$?
set -e
assert_neq "0" "$retired_unlock_rc" "dead lock-recovery command is absent from canonical-only Plan Sync"
assert_contains "$retired_unlock_output" "invalid choice" "retired unlock command fails at argument parsing"

RETIRED_TRACKED_PLAN="$TMP/retired-tracked-v1"
mkdir -p "$RETIRED_TRACKED_PLAN"
: > "$RETIRED_TRACKED_PLAN/implementation.md"
: > "$RETIRED_TRACKED_PLAN/tasks.md"
: > "$RETIRED_TRACKED_PLAN/notes.md"
set +e
retired_tracked_output="$(python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$RETIRED_TRACKED_PLAN" 2>&1)"
retired_tracked_rc=$?
set -e
assert_neq "0" "$retired_tracked_rc" "tracked-v1 plan files fail closed"
assert_contains "$retired_tracked_output" "implementation.md" "retirement detects implementation.md"
assert_contains "$retired_tracked_output" "tasks.md" "retirement detects tasks.md"
assert_contains "$retired_tracked_output" "notes.md" "retirement detects notes.md"
assert_contains "$retired_tracked_output" "v0.7" "tracked-v1 retirement names the breaking version"
assert_contains "$retired_tracked_output" "migrate to canonical" "tracked-v1 retirement gives migration guidance"
assert_contains "$retired_tracked_output" "pin skill-commons v0.6" "tracked-v1 retirement gives pin fallback"

if python3 - "$REPO/tests/fixtures/planning-decomposition.tsv" <<'PY'
from collections import Counter
import csv
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
assert "does not prove" in lines[0]
rows = list(csv.DictReader(lines[1:], delimiter="\t"))
assert [int(item["id"]) for item in rows] == list(range(1, 10))
allowed = {"vertical", "non-feature", "horizontal-exception", "expand-contract", "reject-horizontal"}
assert {item["expected_class"] for item in rows} == allowed
assert Counter(item["expected_class"] for item in rows) == {
    "vertical": 2,
    "non-feature": 2,
    "horizontal-exception": 1,
    "expand-contract": 1,
    "reject-horizontal": 3,
}
for item in rows:
    assert item["prompt"].strip()
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: planning decomposition fixture schema is valid"
else
  fail "planning decomposition fixture schema is valid"
fi

finish
