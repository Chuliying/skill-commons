#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

SCRIPT="$REPO/scripts/export-coauthors.sh"
assert_file "$SCRIPT" "export-coauthors helper exists"

# Fixture: a private-dev stand-in repo with commits from the exporter (self)
# and two colleagues; one colleague authors twice to prove email-level dedupe.
FIXTURE="$TMP/dev"
git init -q "$FIXTURE" >/dev/null 2>&1
git -C "$FIXTURE" config user.name "Exporter"
git -C "$FIXTURE" config user.email "exporter@example.com"

commit_as() { # name email msg
  printf '%s\n' "$3" >> "$FIXTURE/log.txt"
  git -C "$FIXTURE" add log.txt
  git -C "$FIXTURE" -c user.name="$1" -c user.email="$2" \
    commit -q -m "$3" >/dev/null
}

commit_as "Exporter" "exporter@example.com" "baseline"
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
commit_as "Renee Wang" "renee@example.com" "feat: one"
commit_as "Alex Chen" "alex@example.com" "fix: two"
commit_as "Renee Wang" "renee@example.com" "feat: three"
commit_as "Exporter" "exporter@example.com" "chore: self"
MID="$(git -C "$FIXTURE" rev-parse HEAD)"
commit_as "Casey Liu" "casey@example.com" "docs: four"

# Full range since baseline: both colleagues once each, self excluded.
out="$(bash "$SCRIPT" -C "$FIXTURE" "$BASE")"
assert_contains "$out" "Co-authored-by: Renee Wang <renee@example.com>" "colleague author becomes a trailer"
assert_contains "$out" "Co-authored-by: Alex Chen <alex@example.com>" "second colleague becomes a trailer"
assert_contains "$out" "Co-authored-by: Casey Liu <casey@example.com>" "post-mid colleague included up to HEAD"
assert_not_contains "$out" "exporter@example.com" "exporting author is excluded by default"
renee_count="$(printf '%s\n' "$out" | grep -c "renee@example.com")"
assert_eq "1" "$renee_count" "repeat author is deduplicated to one trailer"

# Bounded range: until stops before Casey's commit.
bounded="$(bash "$SCRIPT" -C "$FIXTURE" "$BASE" "$MID")"
assert_not_contains "$bounded" "casey@example.com" "until ref bounds the scanned range"
assert_contains "$bounded" "renee@example.com" "bounded range still reports in-range authors"

# Extra exclusion drops a listed colleague.
pruned="$(bash "$SCRIPT" -C "$FIXTURE" --exclude "alex@example.com" "$BASE")"
assert_not_contains "$pruned" "alex@example.com" "--exclude removes the given email"
assert_contains "$pruned" "renee@example.com" "--exclude leaves other authors intact"

# Empty range: no output, success exit.
empty="$(bash "$SCRIPT" -C "$FIXTURE" HEAD HEAD)"
status=$?
assert_eq "0" "$status" "empty range exits zero"
assert_eq "" "$empty" "empty range emits nothing"

# Unknown ref fails loudly instead of emitting garbage.
if bash "$SCRIPT" -C "$FIXTURE" no-such-ref >/dev/null 2>&1; then
  fail "unknown since ref must exit non-zero"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: unknown since ref exits non-zero"
fi

finish
