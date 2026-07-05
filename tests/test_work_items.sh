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

write_item active-fresh active 2026-07-01T00:00:00+00:00 ready plan/implementation.md
write_item active-stale active 2026-05-01T00:00:00+00:00 ready plan/implementation.md
write_item shipped-old shipped 2026-01-02T00:00:00+00:00 done plan/implementation.md
write_item awaiting-review active 2026-07-01T00:00:00+00:00 awaiting-approval plan/implementation.md
write_item approved-review active 2026-07-01T00:00:00+00:00 approved plan/implementation.md

list_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" list)"
assert_contains "$list_output" "active-fresh" "list includes active work items"
assert_contains "$list_output" "shipped-old" "list includes shipped work items"

active_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" list --status active)"
assert_contains "$active_output" "active-stale" "list filters by status"
assert_not_contains "$active_output" "shipped-old" "status filter excludes other states"

stale_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" stale --days 30 --now 2026-07-04T00:00:00+00:00)"
assert_contains "$stale_output" "active-stale" "stale finds old active item"
assert_not_contains "$stale_output" "active-fresh" "stale ignores fresh active item"
assert_not_contains "$stale_output" "shipped-old" "stale ignores non-active item"

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

set +e
check_output="$(bash "$REPO/scripts/work-items.sh" --work-root "$WORK_ROOT" check 2>&1)"
check_rc=$?
set -e
assert_neq "0" "$check_rc" "check rejects schema violations"
assert_contains "$check_output" "invalid work-item status" "check reports invalid work-item status"
assert_contains "$check_output" "invalid stage status" "check reports invalid stage status"
assert_contains "$check_output" "artifact does not exist" "check reports missing artifact"
assert_contains "$check_output" "missing required field: title" "check reports missing required fields"

finish
