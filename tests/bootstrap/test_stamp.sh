#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/stamp.sh"

printf 'hello world' > "$TMP/a.txt"
s1=$(compute_stamp "$TMP/a.txt")
s2=$(compute_stamp "$TMP/a.txt")
assert_eq "$s1" "$s2" "stamp is deterministic"
assert_eq "12" "${#s1}" "stamp is 12 chars"

printf 'different' > "$TMP/b.txt"
s3=$(compute_stamp "$TMP/b.txt")
assert_neq "$s1" "$s3" "different content -> different stamp"

if compute_stamp "$TMP/nope.txt" 2>/dev/null; then fail "should error on missing file"; else echo "  ok: errors on missing file"; TESTS_PASS=$((TESTS_PASS+1)); fi

finish
