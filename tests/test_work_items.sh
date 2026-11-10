#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)" && [ -n "$TMP" ] && [ -d "$TMP" ] || { echo "cannot create a temp directory" >&2; exit 1; }
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
# D3 says work-history prose does not count as integrated project documentation.
# Another work item's report is work-history too, so the rule is bounded by the work
# root, not by the item's own directory: "legal" is a project document outside the
# work root, not "anything that is not mine".
write_v3_item cross-item-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:docs/work/work-history-path-impact/plan/plan.md' \
  >> "$WORK_ROOT/cross-item-doc-impact/meta.yml"
# The same escape through a symlink: lexically the path is an ordinary project
# document, and only the resolved target shows it is another item's work-history.
ln -s "$WORK_ROOT/work-history-path-impact/plan/plan.md" "$WORKSPACE/docs/cross-item-link.md"
write_v3_item cross-item-link-doc-impact completed not_requested 2026-07-28T00:00:00+00:00 done plan/plan.md
printf '%s\n' 'documentation_impact: doc:docs/cross-item-link.md' \
  >> "$WORK_ROOT/cross-item-link-doc-impact/meta.yml"
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
assert_contains "$check_output" "documentation_impact names work-history under the work root: implement-report.md" "work-history prose is not a documentation-impact result"
assert_contains "$check_output" "documentation_impact names work-history under the work root: docs/work/work-history-path-impact/plan/plan.md" "a workspace-relative path into the work item is work-history too"
assert_contains "$check_output" "cross-item-doc-impact/meta.yml: documentation_impact names work-history under the work root" "another work item's history is work-history too"
assert_contains "$check_output" "documentation_impact resolves to work-history under the work root: docs/cross-item-link.md" "a symlink resolving into another work item is work-history too"
assert_contains "$check_output" "documentation_impact names a document that does not exist: this-file-does-not-exist-anywhere.md; record doc:<project-document> or n/a:<bounded reason>" "a documentation-impact result must name a document that exists"
assert_contains "$check_output" "documentation_impact names a document outside the workspace: docs/external.md resolves to" "a doc: path that escapes the workspace is not a project document"
assert_contains "$check_output" "; name a project document inside the workspace and record doc:<project-document> or n/a:<bounded reason>" "the escape message names the remedy"
assert_contains "$check_output" "documentation_impact resolves to work-history under the work root: docs/history-link.md" "a symlink resolving back into the work item is work-history too"
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

# A folder holding a lifecycle artifact but no meta.yml is a work item the checker
# cannot see; reporting "passed" for it hides the missing metadata. Folders with
# only supporting notes are not work items and stay out of the count.
ORPHAN_ROOT="$TMP/orphan-ws/docs/work"
mkdir -p "$ORPHAN_ROOT/demo" "$ORPHAN_ROOT/notes-only"
git init -q "$TMP/orphan-ws" >/dev/null 2>&1
printf '# PRD\n' > "$ORPHAN_ROOT/demo/prd.md"
printf '# Notes\n' > "$ORPHAN_ROOT/notes-only/inventory.md"
orphan_rc=0
orphan_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$ORPHAN_ROOT" check 2>&1)" || orphan_rc=$?
assert_neq "0" "$orphan_rc" "a lifecycle artifact without meta.yml fails the check"
assert_contains "$orphan_output" "demo" "the orphaned work item is named"
assert_not_contains "$orphan_output" "notes-only" "a supporting-notes folder is not treated as a work item"

# A handoff checks one work item, and the natural reading of "this work item" points
# --work-root at the item's own directory. The checker scans only the work root's
# children, so that root reported "0 valid" and passed. A work root that is itself a
# work item is refused, and `check --item <slug>` checks exactly one work item.
SCOPE_WS="$TMP/scope-ws"
SCOPE_ROOT="$SCOPE_WS/docs/work"
mkdir -p "$SCOPE_ROOT"
write_doc_impact_item "$SCOPE_ROOT" scope-valid 'n/a:scoped check fixture'
# Completed work that never recorded its implement stage.
write_doc_impact_item "$SCOPE_ROOT" scope-invalid 'n/a:scoped check fixture'
sed -i.bak '/^  implement:/d' "$SCOPE_ROOT/scope-invalid/meta.yml"
rm -f "$SCOPE_ROOT/scope-invalid/meta.yml.bak"
# A sibling holding a lifecycle artifact but no meta.yml, which a whole-root check fails.
mkdir -p "$SCOPE_ROOT/scope-orphan"
printf '# PRD\n' > "$SCOPE_ROOT/scope-orphan/prd.md"
# Valid work items reachable only through a path, never through a slug: one nested
# below the work root and one beside it.
write_doc_impact_item "$SCOPE_ROOT/scope-nest" inner 'n/a:scoped check fixture'
write_doc_impact_item "$SCOPE_WS/docs" scope-outside 'n/a:scoped check fixture'

item_root_rc=0
item_root_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT/scope-valid" check 2>&1)" || item_root_rc=$?
assert_neq "0" "$item_root_rc" "check refuses a work root that is itself a work item"
assert_contains "$item_root_output" "is a work item, not the directory that holds work items" "the refusal says the work root is a work item"
assert_contains "$item_root_output" "/docs/work check --item scope-valid" "the refusal names the parent work root and the --item form"
assert_not_contains "$item_root_output" "work-item check passed" "a work-item directory as work root is never a vacuous pass"

item_root_item_rc=0
item_root_item_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT/scope-valid" check --item scope-valid 2>&1)" || item_root_item_rc=$?
assert_neq "0" "$item_root_item_rc" "check --item also refuses a work root that is itself a work item"
assert_contains "$item_root_item_output" "is a work item, not the directory that holds work items" "check --item gives the same refusal"

absent_rc=0
absent_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT" check --item scope-absent 2>&1)" || absent_rc=$?
assert_neq "0" "$absent_rc" "check --item fails when the named work item does not exist"
assert_contains "$absent_output" "scope-absent/meta.yml: work item metadata is missing" "check --item names the missing meta.yml"
assert_not_contains "$absent_output" "work-item check passed" "a missing work item is never a pass"

orphan_item_rc=0
orphan_item_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT" check --item scope-orphan 2>&1)" || orphan_item_rc=$?
assert_neq "0" "$orphan_item_rc" "check --item fails for a folder with lifecycle artifacts but no meta.yml"
assert_contains "$orphan_item_output" "scope-orphan/meta.yml: work item metadata is missing" "check --item names the orphan's missing meta.yml"

invalid_item_rc=0
invalid_item_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT" check --item scope-invalid 2>&1)" || invalid_item_rc=$?
assert_neq "0" "$invalid_item_rc" "check --item fails for an invalid work item"
assert_contains "$invalid_item_output" "scope-invalid/meta.yml: personal-feature completed work requires stage: implement" "check --item prints the work item's FAIL lines"
assert_contains "$invalid_item_output" "work-item check failed: 1/1 invalid" "check --item counts only the named work item"

valid_item_rc=0
valid_item_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT" check --item scope-valid 2>&1)" || valid_item_rc=$?
assert_eq "0" "$valid_item_rc" "check --item passes a valid work item although siblings are invalid"
if printf '%s\n' "$valid_item_output" | grep -q '^PASS .*/docs/work/scope-valid/meta\.yml$'; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check --item prints the PASS line for that work item"
else
  fail "check --item prints the PASS line for that work item"
fi
assert_contains "$valid_item_output" "work-item check passed: 1 valid" "check --item reports exactly one valid work item"
assert_not_contains "$valid_item_output" "scope-invalid" "check --item does not report an invalid sibling"
assert_not_contains "$valid_item_output" "scope-orphan" "check --item leaves sibling orphans to the whole-root check"

# --item takes a slug, never a path: each of these would otherwise reach the work root
# itself, a nested item, an item beside the root, or an absolute location.
for bad_item in '..' '.' '' 'scope-nest/inner' '../scope-outside' 'scope-valid/' "$SCOPE_WS/docs/scope-outside"; do
  bad_rc=0
  bad_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT" check --item "$bad_item" 2>&1)" || bad_rc=$?
  assert_neq "0" "$bad_rc" "check --item rejects '$bad_item'"
  assert_contains "$bad_output" "is not a work-item slug" "check --item says why '$bad_item' is rejected"
  assert_not_contains "$bad_output" "PASS " "check --item '$bad_item' validates nothing"
done

# A repeated --item would silently check only the last one and could pass while an
# earlier named item is invalid, so it is refused.
repeat_rc=0
repeat_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT" check --item scope-invalid --item scope-valid 2>&1)" || repeat_rc=$?
assert_neq "0" "$repeat_rc" "check refuses a repeated --item instead of checking only the last one"
assert_contains "$repeat_output" "names one work item" "the repeated --item refusal says why"
assert_not_contains "$repeat_output" "PASS " "a repeated --item validates nothing"

# Compatibility: a new consuming repository has an empty work root, and list/stale are
# informational, so neither changes behavior.
EMPTY_ROOT="$TMP/empty-ws/docs/work"
mkdir -p "$EMPTY_ROOT"
empty_rc=0
empty_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$EMPTY_ROOT" check 2>&1)" || empty_rc=$?
assert_eq "0" "$empty_rc" "an empty work root still passes check"
assert_contains "$empty_output" "work-item check passed: 0 valid" "an empty work root still reports 0 valid"
for informational in list stale; do
  info_rc=0
  bash "$REPO/scripts/work-items.sh" --work-root "$SCOPE_ROOT/scope-valid" "$informational" >/dev/null 2>&1 || info_rc=$?
  assert_eq "0" "$info_rc" "$informational keeps exit 0 on a work-item directory"
done

# T07: `new` creates a valid work item so an agent need not read ARTIFACTS.md and the PRD
# template first (competitor test round 2, criterion D).
NEW_ROOT="$(mktemp -d)"
new_rc=0; new_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" new due-date --title "Add due dates" --input user:owner-2026-10-30 2>&1)" || new_rc=$?
assert_eq "0" "$new_rc" "new creates a work item"
assert_file "$NEW_ROOT/due-date/meta.yml" "new writes meta.yml"
assert_file "$NEW_ROOT/due-date/prd.md" "new writes a PRD skeleton for personal-feature"
assert_file "$NEW_ROOT/due-date/implement-report.md" "new writes an implement report stub"
assert_contains "$new_output" "complete due-date" "new names the close-out command"
check_new_rc=0; bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" check --item due-date >/dev/null 2>&1 || check_new_rc=$?
assert_eq "0" "$check_new_rc" "the new work item passes check"
assert_contains "$(cat "$NEW_ROOT/due-date/prd.md")" "### AC-001:" "the skeleton has an acceptance criterion to fill"
assert_not_contains "$(cat "$NEW_ROOT/due-date/prd.md")" "Non-functional Requirements" "team-tier sections are left out"
prd_rc=0; python3 "$REPO/scripts/check-prd.py" --prd "$NEW_ROOT/due-date/prd.md" --tier core >/dev/null 2>&1 || prd_rc=$?
assert_neq "0" "$prd_rc" "an unfilled skeleton does not pass the PRD check"
again_rc=0; bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" new due-date >/dev/null 2>&1 || again_rc=$?
assert_eq "2" "$again_rc" "new refuses an existing work item"
bad_rc=0; bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" new ../escape >/dev/null 2>&1 || bad_rc=$?
assert_neq "0" "$bad_rc" "new refuses a path as a slug"
assert_eq "0" "$([ -e "$NEW_ROOT/../escape" ] && echo 1 || echo 0)" "a refused slug writes nothing"
bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" new fix-crash --mode bug-fix >/dev/null 2>&1
assert_eq "0" "$([ -e "$NEW_ROOT/fix-crash/prd.md" ] && echo 1 || echo 0)" "a bug-fix work item has no PRD"
bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" new no-prd --no-prd >/dev/null 2>&1
assert_eq "0" "$([ -e "$NEW_ROOT/no-prd/prd.md" ] && echo 1 || echo 0)" "--no-prd skips the PRD skeleton"
all_rc=0; bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" check >/dev/null 2>&1 || all_rc=$?
assert_eq "0" "$all_rc" "every generated work item passes check"
# Fable T07 review: the core skeleton keeps every core FR field and drops only team blocks.
skeleton="$(cat "$NEW_ROOT/due-date/prd.md")"
for field in "**Data source**" "**Permissions / Visibility**" "**Boundary conditions**" "### Risk and evidence"; do
  assert_contains "$skeleton" "$field" "the core skeleton keeps $field"
done
assert_not_contains "$skeleton" "**Input**:" "a label whose block is team-only is dropped"
assert_not_contains "$skeleton" "NFR has measurable" "Gate 1 does not ask about a section the core tier lacks"
assert_contains "$(cat "$NEW_ROOT/due-date/meta.yml")" "  - user:owner-2026-10-30" "--input is recorded"
team_rc=0; team_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" new team-thing --mode team-feature 2>&1)" || team_rc=$?
assert_eq "0" "$team_rc" "new creates a team-feature item"
assert_contains "$(cat "$NEW_ROOT/team-thing/prd.md")" "Non-functional Requirements" "a team-feature PRD keeps the team tier"
assert_contains "$team_output" "--tier team" "a team-feature item names the team PRD check"
assert_contains "$team_output" "spec (spec)" "new lists the stages the mode still needs"
team_meta_before="$(cat "$NEW_ROOT/team-thing/meta.yml")"
refuse_rc=0; refuse_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" complete team-thing --na x 2>&1)" || refuse_rc=$?
assert_eq "1" "$refuse_rc" "complete refuses an item that does not pass check"
assert_contains "$refuse_output" "requires stage: spec" "complete says what is missing"
assert_eq "$team_meta_before" "$(cat "$NEW_ROOT/team-thing/meta.yml")" "a refused complete leaves meta.yml unchanged"
both_rc=0; bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" complete due-date >/dev/null 2>&1 || both_rc=$?
assert_eq "2" "$both_rc" "complete needs --doc or --na"
done_rc=0; bash "$REPO/scripts/work-items.sh" --work-root "$NEW_ROOT" complete due-date --na "single-file CLI change" >/dev/null 2>&1 || done_rc=$?
assert_eq "0" "$done_rc" "complete closes out a personal-feature item"
done_meta="$(cat "$NEW_ROOT/due-date/meta.yml")"
assert_contains "$done_meta" "work_status: completed" "complete sets work_status"
assert_contains "$done_meta" "documentation_impact: n/a:single-file CLI change" "complete records documentation_impact"
assert_not_contains "$done_meta" "status: in_progress" "complete leaves no unfinished stage"
rm -rf "$NEW_ROOT"

# T08: queued items, start, complete edge cases, and the activity log.
Q_ROOT="$(mktemp -d)"
wi() { bash "$REPO/scripts/work-items.sh" --work-root "$Q_ROOT" "$@"; }
q_rc=0; wi new later-thing --queued >/dev/null 2>&1 || q_rc=$?
assert_eq "0" "$q_rc" "new --queued creates a backlog item"
assert_contains "$(cat "$Q_ROOT/later-thing/meta.yml")" "work_status: queued" "a backlog item is queued"
qc_rc=0; wi check --item later-thing >/dev/null 2>&1 || qc_rc=$?
assert_eq "0" "$qc_rc" "a queued item passes check"
early_rc=0; early_out="$(wi complete later-thing --na x 2>&1)" || early_rc=$?
assert_eq "2" "$early_rc" "complete refuses a queued item"
assert_contains "$early_out" "start first" "complete says to start a queued item first"
st_rc=0; wi start later-thing >/dev/null 2>&1 || st_rc=$?
assert_eq "0" "$st_rc" "start moves a queued item to active"
assert_contains "$(cat "$Q_ROOT/later-thing/meta.yml")" "work_status: active" "the started item is active"
again_st=0; wi start later-thing >/dev/null 2>&1 || again_st=$?
assert_eq "2" "$again_st" "start refuses an item that is not queued"
wi complete later-thing --na "single-file change" >/dev/null 2>&1
lines_before="$(wc -l < "$Q_ROOT/later-thing/activity.jsonl")"
redo_out="$(wi complete later-thing --na other 2>&1)"
assert_contains "$redo_out" "already completed" "complete on a completed item changes nothing"
assert_eq "$lines_before" "$(wc -l < "$Q_ROOT/later-thing/activity.jsonl")" "a repeated complete adds no activity line"
assert_not_contains "$(cat "$Q_ROOT/later-thing/meta.yml")" "n/a:other" "a repeated complete keeps documentation_impact"
events="$(python3 -c 'import json,sys; print(" ".join(json.loads(l)["event"] for l in open(sys.argv[1])))' "$Q_ROOT/later-thing/activity.jsonl")"
assert_eq "new start complete" "$events" "new, start and complete each log one event"
wi new team-item --mode team-feature >/dev/null 2>&1
team_lines="$(wc -l < "$Q_ROOT/team-item/activity.jsonl")"
wi complete team-item --na x >/dev/null 2>&1 || true
assert_eq "$team_lines" "$(wc -l < "$Q_ROOT/team-item/activity.jsonl")" "a refused complete logs nothing"
mkdir -p "$Q_ROOT/abandoned-item"
sed -e 's/^slug: .*/slug: abandoned-item/' -e 's/^work_status: .*/work_status: abandoned/' "$Q_ROOT/team-item/meta.yml" > "$Q_ROOT/abandoned-item/meta.yml"
cp "$Q_ROOT/team-item/prd.md" "$Q_ROOT/team-item/implement-report.md" "$Q_ROOT/abandoned-item/"
ab_rc=0; wi complete abandoned-item --na x >/dev/null 2>&1 || ab_rc=$?
assert_eq "2" "$ab_rc" "complete refuses an abandoned item"
assert_contains "$(cat "$Q_ROOT/abandoned-item/meta.yml")" "work_status: abandoned" "a refused complete leaves the abandoned item as it was"
agents="$(env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_PLUGIN_ROOT -u CURSOR_TRACE_ID -u CURSOR_PLUGIN_ROOT CODEX_THREAD_ID=thread-1 CODEX_SANDBOX=seatbelt CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=claude-1 bash "$REPO/scripts/work-items.sh" --work-root "$Q_ROOT" new nested >/dev/null 2>&1; tail -1 "$Q_ROOT/nested/activity.jsonl")"
assert_contains "$agents" '"tool": "codex"' "an inherited environment records codex"
assert_contains "$agents" '"tool": "claude-code"' "and the claude-code parent, without choosing one"
none_line="$(SKILL_COMMONS_SESSION=none CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=claude-1 bash "$REPO/scripts/work-items.sh" --work-root "$Q_ROOT" new private >/dev/null 2>&1; tail -1 "$Q_ROOT/private/activity.jsonl")"
assert_not_contains "$none_line" "claude-1" "SKILL_COMMONS_SESSION=none records no session id"
assert_contains "$none_line" '"tool": "claude-code"' "SKILL_COMMONS_SESSION=none still records the tool"
plain="$(env -i PATH="$PATH" HOME="$HOME" bash "$REPO/scripts/work-items.sh" --work-root "$Q_ROOT" new plain >/dev/null 2>&1; tail -1 "$Q_ROOT/plain/activity.jsonl")"
assert_contains "$plain" '"agents": []' "a plain terminal records no tool"
rm -rf "$Q_ROOT"

finish
