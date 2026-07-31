#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

# The fixture workspace mirrors the real layout `<workspace>/docs/work`, so a
# `doc:` result is resolved against the same base a project uses. The workspace is a
# real `git init` working tree because that is what anchors a workspace-relative
# `doc:` path; a hand-made `.git` directory is not a working tree and would forge the
# anchor the checker reads.
WORKSPACE="$TMP/ws"
WORK_ROOT="$WORKSPACE/docs/work"
mkdir -p "$WORK_ROOT" "$WORKSPACE/docs/v3-namesake-doc"
git init -q "$WORKSPACE" >/dev/null 2>&1
printf '# Decisions\n' > "$WORKSPACE/docs/decisions.md"
printf '# Overview\n' > "$WORKSPACE/docs/v3-namesake-doc/overview.md"

write_item() {
  slug="$1"
  status="$2"
  updated_at="$3"
  stage_status="$4"
  artifact="$5"
  skill="${6:-plan-sync}"
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
    "  plan: { skill: $skill, file: $artifact, status: $stage_status }" \
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
  extra_stage="${8:-none}"
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
      '  implement: { skill: implement, file: implement-report.md, status: done }'
    if [ "$extra_stage" = qa-plan ]; then
      printf '%s\n' '  qa-plan: { skill: qa, file: qa-plan.md, status: done }'
    fi
    printf '%s\n' \
      'inputs:' \
      '  - request.md'
  } > "$WORK_ROOT/$slug/meta.yml"
}

# A minimal completed v3 item whose only open question is its documentation-impact
# result, written into an arbitrary work root. `--work-root` is public, so the
# fixtures using this helper put work roots at non-default locations and depths.
write_doc_impact_item() { # root slug documentation_impact
  root="$1"
  slug="$2"
  impact="$3"
  mkdir -p "$root/$slug"
  printf '# Implement report\n' > "$root/$slug/implement-report.md"
  printf '%s\n' \
    'schema_version: work-item/v3' \
    "slug: $slug" \
    "title: Item $slug" \
    'created_at: 2026-07-28T00:00:00+00:00' \
    'updated_at: 2026-07-28T00:00:00+00:00' \
    'execution_mode: personal-feature' \
    'work_status: completed' \
    'delivery_status: not_requested' \
    'stages:' \
    '  implement: { skill: implement, file: implement-report.md, status: done }' \
    'inputs:' \
    '  - request.md' \
    "documentation_impact: $impact" \
    > "$root/$slug/meta.yml"
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
# D3: a completed work item records exactly one documentation-impact result, in one of
# two forms. The rule is forward-only from the D3 adoption boundary, so the
# 2026-07-01 items above stay valid without the field.
write_v3_item v3-documented completed approved 2026-07-28T00:00:00+00:00 done plan/plan.md approval
printf '%s\n' 'documentation_impact: doc:docs/decisions.md' >> "$WORK_ROOT/v3-documented/meta.yml"
write_v3_item v3-documented-na completed approved 2026-07-28T00:00:00+00:00 done plan/plan.md approval
printf '%s\n' 'documentation_impact: n/a:internal test fixture, no project document changed' \
  >> "$WORK_ROOT/v3-documented-na/meta.yml"
# A project document may legitimately sit in a directory that happens to share the
# work item's name. Only the work item's own directory is work-history.
write_v3_item v3-namesake-doc completed approved 2026-07-28T00:00:00+00:00 done plan/plan.md approval
printf '%s\n' 'documentation_impact: doc:docs/v3-namesake-doc/overview.md' \
  >> "$WORK_ROOT/v3-namesake-doc/meta.yml"

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

# `<workspace>/docs/work` is only ARTIFACTS.md's default and `--work-root` is public, so
# the workspace a `doc:` result resolves against cannot be a fixed number of levels
# above the work root. Here the work root is `<workspace>/.work`, one level down, and
# `doc:README.md` names the workspace README that exists.
ALT_WORKSPACE="$TMP/alt-depth-ws"
ALT_ROOT="$ALT_WORKSPACE/.work"
mkdir -p "$ALT_ROOT"
git init -q "$ALT_WORKSPACE" >/dev/null 2>&1
printf '# Alt workspace\n' > "$ALT_WORKSPACE/README.md"
write_doc_impact_item "$ALT_ROOT" alt-depth-doc doc:README.md
set +e
alt_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$ALT_ROOT" check 2>&1)"
alt_rc=$?
set -e
assert_eq "0" "$alt_rc" "a doc: result resolves against the workspace holding a non-default work root"
assert_not_contains "$alt_output" "does not exist" "a workspace document is not reported absent because of work-root depth"

# Without a Git working tree there is no workspace anchor, so existence cannot be
# verified at all. The check fails closed rather than guessing a base directory.
NOGIT_ROOT="$TMP/nogit/.work"
mkdir -p "$NOGIT_ROOT"
printf '# Readme\n' > "$TMP/nogit/README.md"
write_doc_impact_item "$NOGIT_ROOT" nogit-doc doc:README.md
set +e
nogit_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$NOGIT_ROOT" check 2>&1)"
nogit_rc=$?
set -e
assert_neq "0" "$nogit_rc" "a doc: result outside any Git working tree fails closed"
assert_contains "$nogit_output" "is not inside a Git working tree" "the fail-closed message names the missing workspace anchor"
assert_contains "$nogit_output" "record doc:<project-document> or n/a:<bounded reason>" "the fail-closed message names the remedy"

write_item invalid-state unknown 2026-07-01T00:00:00+00:00 ready plan/implementation.md
write_item invalid-stage active 2026-07-01T00:00:00+00:00 imaginary plan/implementation.md
write_item missing-file active 2026-07-01T00:00:00+00:00 ready missing.md
write_item missing-title active 2026-07-01T00:00:00+00:00 ready plan/implementation.md
# An Execution Mode name (team-feature) is not a skill; only real skill folders
# may own a stage, otherwise a stage points at nothing that can produce it.
write_item unknown-skill active 2026-07-01T00:00:00+00:00 ready plan/implementation.md team-feature
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
write_v3_item refactor-with-qa completed not_requested 2026-07-01T00:00:00+00:00 done plan/plan.md none qa-plan
printf '# QA plan\n' > "$WORK_ROOT/refactor-with-qa/qa-plan.md"
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
# Dated after the repository's v3 adoption boundary (see V3_ADOPTION_TIME in
# scripts/work_items.py, moved to the reconciliation date because dev main forked
# before v3 existed). An item created from then on must carry the stamp.
# D3 negatives. Each item is completed after the D3 adoption boundary, so the
# documentation-impact result is mandatory and its two legal forms are closed.
write_v3_item missing-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
write_v3_item untyped-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: docs/decisions.md' >> "$WORK_ROOT/untyped-doc-impact/meta.yml"
write_v3_item work-history-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:implement-report.md' >> "$WORK_ROOT/work-history-doc-impact/meta.yml"
write_v3_item work-history-path-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:docs/work/work-history-path-impact/plan/plan.md' \
  >> "$WORK_ROOT/work-history-path-impact/meta.yml"
# A named document that does not exist proves no document was updated.
write_v3_item absent-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:this-file-does-not-exist-anywhere.md' \
  >> "$WORK_ROOT/absent-doc-impact/meta.yml"
# A `doc:` path whose resolved target leaves the workspace is not a project document:
# the project's own documentation demonstrably was not updated. The symlink is inside
# the workspace, so only resolving the target catches the escape.
mkdir -p "$TMP/outside-ws"
printf '# Outside the workspace\n' > "$TMP/outside-ws/external.md"
ln -s "$TMP/outside-ws/external.md" "$WORKSPACE/docs/external.md"
write_v3_item escaping-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:docs/external.md' \
  >> "$WORK_ROOT/escaping-doc-impact/meta.yml"
# A symlink inside the workspace that resolves back into the work item is still
# work-history: the lexical adjacent-pair match cannot see it, only the resolved
# target tells the truth.
write_v3_item history-link-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '# Work history\n' > "$WORK_ROOT/history-link-doc-impact/implement-report.md"
ln -s "$WORK_ROOT/history-link-doc-impact/implement-report.md" "$WORKSPACE/docs/history-link.md"
printf '%s\n' 'documentation_impact: doc:docs/history-link.md' \
  >> "$WORK_ROOT/history-link-doc-impact/meta.yml"
# A `doc:` value is workspace-relative, so the two syntactic ways out of the workspace
# stay rejected before any resolution happens.
write_v3_item traversal-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:../../../outside-ws/external.md' \
  >> "$WORK_ROOT/traversal-doc-impact/meta.yml"
write_v3_item absolute-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' "documentation_impact: doc:$TMP/outside-ws/external.md" \
  >> "$WORK_ROOT/absolute-doc-impact/meta.yml"
write_v3_item empty-na-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: n/a:' >> "$WORK_ROOT/empty-na-doc-impact/meta.yml"
write_v3_item unbounded-na-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf 'documentation_impact: n/a:%s\n' "$(printf 'reason %.0s' $(seq 1 40))" \
  >> "$WORK_ROOT/unbounded-na-doc-impact/meta.yml"
write_item unstamped-post-v3 shipped 2026-07-26T00:00:00+00:00 done plan/implementation.md
sed -i.bak 's#created_at: 2026-01-01T00:00:00+00:00#created_at: 2026-07-26T00:00:00+00:00#' "$WORK_ROOT/unstamped-post-v3/meta.yml"
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
assert_contains "$check_output" "unknown skill" "check reports a stage owned by a non-skill name"
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
assert_contains "$check_output" "completed work requires exactly one documentation_impact result" "completed work requires a documentation-impact result"
assert_contains "$check_output" "invalid documentation_impact: docs/decisions.md" "documentation impact rejects an untyped value"
assert_contains "$check_output" "documentation_impact names work-history inside the work item: implement-report.md" "work-history prose is not a documentation-impact result"
assert_contains "$check_output" "documentation_impact names work-history inside the work item: docs/work/work-history-path-impact/plan/plan.md" "a workspace-relative path into the work item is work-history too"
assert_contains "$check_output" "documentation_impact names a document that does not exist: this-file-does-not-exist-anywhere.md; record doc:<project-document> or n/a:<bounded reason>" "a documentation-impact result must name a document that exists"
assert_contains "$check_output" "documentation_impact names a document outside the workspace: docs/external.md resolves to" "a doc: path that escapes the workspace is not a project document"
assert_contains "$check_output" "; name a project document inside the workspace and record doc:<project-document> or n/a:<bounded reason>" "the escape message names the remedy"
assert_contains "$check_output" "documentation_impact resolves to work-history inside the work item: docs/history-link.md" "a symlink resolving back into the work item is work-history too"
assert_contains "$check_output" "documentation_impact doc must be a workspace-relative path: ../../../outside-ws/external.md" "a traversal path is not a workspace-relative document"
assert_contains "$check_output" "documentation_impact doc must be a workspace-relative path: $TMP/outside-ws/external.md" "an absolute path is not a workspace-relative document"
assert_contains "$check_output" "documentation_impact n/a needs a bounded reason" "an empty N/A reason is not a documentation-impact result"
assert_contains "$check_output" "documentation_impact n/a reason must be at most 200 characters" "the N/A reason stays bounded"

# J6: when the completion check fails, the machine view names the failed check and the
# remedy, the state does not advance to complete, and an authored PASS in the work
# item's own report cannot override the failure.
J6_ROOT="$TMP/j6"
mkdir -p "$J6_ROOT/blocked"
printf '# Implement report\nVerification: PASS\nAll green, work is complete.\n' \
  > "$J6_ROOT/blocked/implement-report.md"
printf '%s\n' \
  'schema_version: work-item/v3' \
  'slug: blocked' \
  'title: Completion claimed by an authored PASS' \
  'created_at: 2026-07-28T00:00:00+00:00' \
  'updated_at: 2026-07-28T00:00:00+00:00' \
  'execution_mode: personal-feature' \
  'work_status: completed' \
  'delivery_status: not_requested' \
  'stages:' \
  '  implement: { skill: implement, file: implement-report.md, status: done }' \
  'inputs:' \
  '  - request.md' \
  > "$J6_ROOT/blocked/meta.yml"
set +e
j6_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$J6_ROOT" check 2>&1)"
j6_rc=$?
set -e
assert_neq "0" "$j6_rc" "an authored PASS does not advance work to complete"
assert_contains "$j6_output" "completed work requires exactly one documentation_impact result" "failed completion check names the failed check"
assert_contains "$j6_output" "n/a:<bounded reason>" "failed completion check names what to do next"

finish
