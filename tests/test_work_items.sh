#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

WORK_ROOT="$TMP/work"
mkdir -p "$WORK_ROOT"

write_item() {
  slug="$1"
  status="$2"
  updated_at="$3"
  stage_status="$4"
  artifact="$5"
  mkdir -p "$WORK_ROOT/$slug/plan"
  if [ "$artifact" != "missing.md" ]; then
    printf '# Artifact\n' > "$WORK_ROOT/$slug/$artifact"
  fi
  printf '%s\n' \
    "slug: $slug" \
    "title: Item $slug" \
    'created_at: 2026-01-01T00:00:00+00:00' \
    "updated_at: $updated_at" \
    "status: $status" \
    'stages:' \
    "  plan: { skill: plan-sync, file: $artifact, status: $stage_status }" \
    'inputs:' \
    '  - request.md' \
    > "$WORK_ROOT/$slug/meta.yml"
}

write_v3_item() {
  slug="$1"
  work_status="$2"
  delivery_status="$3"
  updated_at="$4"
  stage_status="$5"
  artifact="$6"
  evidence_kind="${7:-none}"
  mkdir -p "$WORK_ROOT/$slug/plan"
  if [ "$artifact" != "missing.md" ]; then
    printf '# Artifact\n' > "$WORK_ROOT/$slug/$artifact"
  fi
  printf '# PRD\n' > "$WORK_ROOT/$slug/prd.md"
  printf '# Implement report\n' > "$WORK_ROOT/$slug/implement-report.md"
  {
    printf '%s\n' \
      'schema_version: work-item/v3' \
      "slug: $slug" \
      "title: Item $slug" \
      'created_at: 2026-01-01T00:00:00+00:00' \
      "updated_at: $updated_at" \
      'execution_mode: refactor' \
      "work_status: $work_status" \
      "delivery_status: $delivery_status"
    if [ "$evidence_kind" != none ]; then
      printf '%s\n' 'delivery_evidence:'
      case "$evidence_kind" in
        approval)
          printf '%s\n' '  approval_ref: user:release-approved-2026-07-10'
          ;;
        pr)
          printf '%s\n' \
            '  approval_ref: user:release-approved-2026-07-10' \
            '  pr_url: https://example.test/pull/42'
          ;;
        merge)
          printf '%s\n' \
            '  approval_ref: user:release-approved-2026-07-10' \
            '  merge_sha: 0123456789abcdef0123456789abcdef01234567'
          ;;
        deploy)
          printf '%s\n' \
            '  approval_ref: user:release-approved-2026-07-10' \
            '  merge_sha: 0123456789abcdef0123456789abcdef01234567' \
            '  deployment_id: deploy-2026-07-10-001'
          ;;
      esac
    fi
    printf '%s\n' \
      'stages:' \
      '  prd: { skill: to-prd, file: prd.md, status: done }' \
      "  plan: { skill: plan-sync, file: $artifact, status: $stage_status }" \
      '  implement: { skill: implement, file: implement-report.md, status: done }' \
      'inputs:' \
      '  - request.md'
  } > "$WORK_ROOT/$slug/meta.yml"
}

write_item active-fresh active 2026-07-01T00:00:00+00:00 ready plan/implementation.md
write_item active-stale active 2026-05-01T00:00:00+00:00 ready plan/implementation.md
write_item shipped-old shipped 2026-01-02T00:00:00+00:00 done plan/implementation.md
write_item awaiting-review active 2026-07-01T00:00:00+00:00 awaiting-approval plan/implementation.md
write_item approved-review active 2026-07-01T00:00:00+00:00 approved plan/implementation.md
write_v3_item v3-active active not_requested 2026-07-01T00:00:00+00:00 ready plan/plan.md
write_v3_item v3-completed completed approved 2026-07-01T00:00:00+00:00 done plan/plan.md approval
write_v3_item v3-pr completed pr_created 2026-07-01T00:00:00+00:00 done plan/plan.md pr
write_v3_item v3-merged completed merged 2026-07-01T00:00:00+00:00 done plan/plan.md merge
write_v3_item v3-deployed completed deployed 2026-07-01T00:00:00+00:00 done plan/plan.md deploy

list_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" list)"
assert_contains "$list_output" "active-fresh" "list includes active work items"
assert_contains "$list_output" "shipped-old" "list includes shipped work items"
assert_contains "$list_output" "v3-completed" "list includes v3 completed work items"

active_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" list --status active)"
assert_contains "$active_output" "active-stale" "list filters by status"
assert_not_contains "$active_output" "shipped-old" "status filter excludes other states"

completed_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" list --status completed)"
assert_contains "$completed_output" "v3-completed" "list filters v3 work status"
assert_contains "$completed_output" "shipped-old" "legacy shipped maps to completed work status"

stale_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" stale --days 30 --now 2026-07-04T00:00:00+00:00)"
assert_contains "$stale_output" "active-stale" "stale finds old active item"
assert_not_contains "$stale_output" "active-fresh" "stale ignores fresh active item"
assert_not_contains "$stale_output" "shipped-old" "stale ignores non-active item"
assert_not_contains "$stale_output" "v3-completed" "stale ignores completed v3 item"

if bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" check >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check accepts valid work-item metadata"
else
  fail "check accepts valid work-item metadata"
fi

write_item invalid-state unknown 2026-07-01T00:00:00+00:00 ready plan/implementation.md
write_item invalid-stage active 2026-07-01T00:00:00+00:00 imaginary plan/implementation.md
write_item missing-file active 2026-07-01T00:00:00+00:00 ready missing.md
write_item missing-title active 2026-07-01T00:00:00+00:00 ready plan/implementation.md
sed -i.bak '/^title:/d' "$WORK_ROOT/missing-title/meta.yml"
rm -f "$WORK_ROOT/missing-title/meta.yml.bak"

write_v3_item missing-approval completed approved 2026-07-01T00:00:00+00:00 done plan/plan.md
write_v3_item missing-pr completed pr_created 2026-07-01T00:00:00+00:00 done plan/plan.md approval
write_v3_item missing-merge completed merged 2026-07-01T00:00:00+00:00 done plan/plan.md approval
write_v3_item missing-deploy completed deployed 2026-07-01T00:00:00+00:00 done plan/plan.md merge
write_v3_item invalid-v3-state shipped not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
write_v3_item premature-approval active approved 2026-07-01T00:00:00+00:00 done plan/plan.md approval
write_v3_item premature-awaiting active awaiting_approval 2026-07-01T00:00:00+00:00 done plan/plan.md
write_v3_item evidence-without-delivery completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md approval
write_v3_item invalid-pr-url completed pr_created 2026-07-01T00:00:00+00:00 done plan/plan.md pr
sed -i.bak 's#https://example.test/pull/42#pull/42#' "$WORK_ROOT/invalid-pr-url/meta.yml"
rm -f "$WORK_ROOT/invalid-pr-url/meta.yml.bak"
write_v3_item invalid-merge-sha completed merged 2026-07-01T00:00:00+00:00 done plan/plan.md merge
sed -i.bak 's/0123456789abcdef0123456789abcdef01234567/deadbeef/' "$WORK_ROOT/invalid-merge-sha/meta.yml"
rm -f "$WORK_ROOT/invalid-merge-sha/meta.yml.bak"
write_v3_item unknown-evidence completed approved 2026-07-01T00:00:00+00:00 done plan/plan.md approval
sed -i.bak '/approval_ref:/a\
  ticket: RELEASE-42' "$WORK_ROOT/unknown-evidence/meta.yml"
rm -f "$WORK_ROOT/unknown-evidence/meta.yml.bak"
write_v3_item premature-pr-evidence completed approved 2026-07-01T00:00:00+00:00 done plan/plan.md approval
sed -i.bak '/approval_ref:/a\
  pr_url: https://example.test/pull/42' "$WORK_ROOT/premature-pr-evidence/meta.yml"
rm -f "$WORK_ROOT/premature-pr-evidence/meta.yml.bak"
write_v3_item premature-merge-evidence completed pr_created 2026-07-01T00:00:00+00:00 done plan/plan.md pr
sed -i.bak '/pr_url:/a\
  merge_sha: 0123456789abcdef0123456789abcdef01234567' "$WORK_ROOT/premature-merge-evidence/meta.yml"
rm -f "$WORK_ROOT/premature-merge-evidence/meta.yml.bak"
write_v3_item premature-deploy-evidence completed merged 2026-07-01T00:00:00+00:00 done plan/plan.md merge
sed -i.bak '/merge_sha:/a\
  deployment_id: deploy-2026-07-10-001' "$WORK_ROOT/premature-deploy-evidence/meta.yml"
rm -f "$WORK_ROOT/premature-deploy-evidence/meta.yml.bak"
write_v3_item duplicate-stage-field completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's#file: plan/plan.md#file: missing.md, file: plan/plan.md#' "$WORK_ROOT/duplicate-stage-field/meta.yml"
rm -f "$WORK_ROOT/duplicate-stage-field/meta.yml.bak"
write_v3_item unknown-stage-field completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's#status: done#status: done, owner: agent#' "$WORK_ROOT/unknown-stage-field/meta.yml"
rm -f "$WORK_ROOT/unknown-stage-field/meta.yml.bak"
write_v3_item malformed-stage-chunk completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's#skill: plan-sync,#skill: plan-sync, malformed,#' "$WORK_ROOT/malformed-stage-chunk/meta.yml"
rm -f "$WORK_ROOT/malformed-stage-chunk/meta.yml.bak"
write_v3_item invalid-mode completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's/execution_mode: refactor/execution_mode: ad-hoc/' "$WORK_ROOT/invalid-mode/meta.yml"
rm -f "$WORK_ROOT/invalid-mode/meta.yml.bak"
write_v3_item completed-active-stage completed not_requested 2026-07-01T00:00:00+00:00 pending plan/plan.md
write_v3_item completed-missing-prd completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak '/^  prd:/d' "$WORK_ROOT/completed-missing-prd/meta.yml"
rm -f "$WORK_ROOT/completed-missing-prd/meta.yml.bak"
write_v3_item completed-team-incomplete completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's/execution_mode: refactor/execution_mode: team-feature/' "$WORK_ROOT/completed-team-incomplete/meta.yml"
rm -f "$WORK_ROOT/completed-team-incomplete/meta.yml.bak"
write_v3_item refactor-with-qa completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
printf '# QA plan\n' > "$WORK_ROOT/refactor-with-qa/qa-plan.md"
sed -i.bak '/^inputs:/i\
  qa-plan: { skill: qa, file: qa-plan.md, status: done }' "$WORK_ROOT/refactor-with-qa/meta.yml"
rm -f "$WORK_ROOT/refactor-with-qa/meta.yml.bak"
write_v3_item unknown-top-level completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'alternate_delivery_truth: pr_created' >> "$WORK_ROOT/unknown-top-level/meta.yml"
write_v3_item scalar-stages completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's/^stages:$/stages: bogus-scalar/' "$WORK_ROOT/scalar-stages/meta.yml"
rm -f "$WORK_ROOT/scalar-stages/meta.yml.bak"
write_v3_item scalar-inputs completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's/^inputs:$/inputs: bogus-scalar/' "$WORK_ROOT/scalar-inputs/meta.yml"
rm -f "$WORK_ROOT/scalar-inputs/meta.yml.bak"
write_v3_item scalar-delivery-evidence completed approved 2026-07-01T00:00:00+00:00 done plan/plan.md approval
sed -i.bak 's/^delivery_evidence:$/delivery_evidence: bogus-scalar/' "$WORK_ROOT/scalar-delivery-evidence/meta.yml"
rm -f "$WORK_ROOT/scalar-delivery-evidence/meta.yml.bak"
write_v3_item completed-skipped-required completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's#prd.md, status: done#prd.md, status: skipped#' "$WORK_ROOT/completed-skipped-required/meta.yml"
rm -f "$WORK_ROOT/completed-skipped-required/meta.yml.bak"
write_v3_item completed-superseded-required completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md
sed -i.bak 's#implement-report.md, status: done#implement-report.md, status: superseded#' "$WORK_ROOT/completed-superseded-required/meta.yml"
rm -f "$WORK_ROOT/completed-superseded-required/meta.yml.bak"
write_v3_item invalid-approval-ref completed approved 2026-07-01T00:00:00+00:00 done plan/plan.md approval
sed -i.bak 's#user:release-approved-2026-07-10#yes#' "$WORK_ROOT/invalid-approval-ref/meta.yml"
rm -f "$WORK_ROOT/invalid-approval-ref/meta.yml.bak"
write_v3_item invalid-deployment-id completed deployed 2026-07-01T00:00:00+00:00 done plan/plan.md deploy
sed -i.bak 's#deploy-2026-07-10-001#yes#' "$WORK_ROOT/invalid-deployment-id/meta.yml"
rm -f "$WORK_ROOT/invalid-deployment-id/meta.yml.bak"
write_item unstamped-post-v3 shipped 2026-07-11T00:00:00+00:00 done plan/implementation.md
sed -i.bak 's#created_at: 2026-01-01T00:00:00+00:00#created_at: 2026-07-11T00:00:00+00:00#' "$WORK_ROOT/unstamped-post-v3/meta.yml"
rm -f "$WORK_ROOT/unstamped-post-v3/meta.yml.bak"

set +e
check_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" check 2>&1)"
check_rc=$?
set -e
assert_neq "0" "$check_rc" "check rejects schema violations"
assert_contains "$check_output" "invalid work-item status" "check reports invalid work-item status"
assert_contains "$check_output" "invalid stage status" "check reports invalid stage status"
assert_contains "$check_output" "artifact does not exist" "check reports missing artifact"
assert_contains "$check_output" "missing required field: title" "check reports missing required fields"
assert_contains "$check_output" "approved requires delivery evidence: approval_ref" "approved transition requires evidence"
assert_contains "$check_output" "pr_created requires delivery evidence: pr_url" "PR transition requires evidence"
assert_contains "$check_output" "merged requires delivery evidence: merge_sha" "merge transition requires evidence"
assert_contains "$check_output" "deployed requires delivery evidence: deployment_id" "deploy transition requires evidence"
assert_contains "$check_output" "invalid work status" "v3 rejects legacy shipped work status"
assert_contains "$check_output" "delivery status approved requires work_status completed" "approval cannot precede work completion"
assert_contains "$check_output" "delivery status awaiting_approval requires work_status completed" "approval request cannot precede work completion"
assert_contains "$check_output" "not_requested must not carry delivery evidence" "non-delivery state rejects fabricated evidence"
assert_contains "$check_output" "invalid delivery evidence pr_url" "PR transition validates an HTTPS URL"
assert_contains "$check_output" "invalid delivery evidence merge_sha" "merge transition validates a full commit SHA"
assert_contains "$check_output" "unsupported delivery evidence: ticket" "delivery evidence keys are closed"
assert_contains "$check_output" "approved does not allow delivery evidence: pr_url" "approval rejects premature PR evidence"
assert_contains "$check_output" "pr_created does not allow delivery evidence: merge_sha" "PR state rejects premature merge evidence"
assert_contains "$check_output" "merged does not allow delivery evidence: deployment_id" "merge state rejects premature deployment evidence"
assert_contains "$check_output" "duplicate stage field: file" "stage inline map rejects duplicate fields"
assert_contains "$check_output" "unknown stage field: owner" "stage inline map rejects unknown fields"
assert_contains "$check_output" "malformed stage field" "stage inline map rejects chunks without a colon"
assert_contains "$check_output" "invalid execution mode" "work item rejects an unknown execution mode"
assert_contains "$check_output" "completed work item stage plan must not remain pending" "completed work rejects active stage state"
assert_contains "$check_output" "refactor completed work requires stage: prd" "completed work enforces required mode artifacts"
assert_contains "$check_output" "team-feature completed work requires stage: spec" "completed team work enforces its full artifact contract"
assert_contains "$check_output" "refactor forbids stage: qa-plan" "execution mode rejects absent artifacts"
assert_contains "$check_output" "unknown top-level field: alternate_delivery_truth" "work item rejects unknown top-level fields"
assert_contains "$check_output" "container field stages must not have a scalar value" "stages requires canonical container syntax"
assert_contains "$check_output" "container field inputs must not have a scalar value" "inputs requires canonical container syntax"
assert_contains "$check_output" "container field delivery_evidence must not have a scalar value" "delivery evidence requires canonical container syntax"
assert_contains "$check_output" "required stage prd must not be skipped" "completed work rejects skipped required artifacts"
assert_contains "$check_output" "required stage implement must not be superseded" "completed work rejects superseded required artifacts"
assert_contains "$check_output" "invalid delivery evidence approval_ref" "approval evidence requires a typed durable reference"
assert_contains "$check_output" "invalid delivery evidence deployment_id" "deployment evidence requires identifier shape"
assert_contains "$check_output" "created after work-item/v3 adoption must declare schema_version" "new metadata cannot omit the v3 stamp"

finish
