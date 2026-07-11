#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/render.sh"

dir="$TMP/directive.md"
printf 'DIRECTIVE LINE ONE\nDIRECTIVE LINE TWO\n' > "$dir"

# render_block writes fence + body + stamp
bf="$TMP/block.txt"
render_block "$dir" "abc123def456" > "$bf"
bc="$(cat "$bf")"
assert_contains "$bc" "skill-commons:start" "block has start fence"
assert_contains "$bc" "skill-commons:end" "block has end fence"
assert_contains "$bc" "DIRECTIVE LINE ONE" "block has body"
assert_contains "$bc" "skill-commons-stamp: abc123def456" "block has stamp"

# upsert into a file with pre-existing user content -> content preserved
tgt="$TMP/AGENTS.md"
printf '# My Project\nUser notes here.\n' > "$tgt"
upsert_block "$tgt" "$bf"
tc="$(cat "$tgt")"
assert_contains "$tc" "User notes here." "preserves user content"
assert_contains "$tc" "DIRECTIVE LINE ONE" "adds managed block"

# upsert again with a NEW stamp -> old block replaced, not duplicated
render_block "$dir" "999999999999" > "$bf"
upsert_block "$tgt" "$bf"
tc="$(cat "$tgt")"
assert_contains "$tc" "skill-commons-stamp: 999999999999" "new stamp present"
assert_not_contains "$tc" "skill-commons-stamp: abc123def456" "old stamp gone"
n=$(grep -c "skill-commons:start" "$tgt")
assert_eq "1" "$n" "exactly one managed block"
assert_contains "$tc" "User notes here." "still preserves user content"

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

file_inode() {
  stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1"
}

# Removal validates the complete fence before replacing the original and uses
# a same-directory rename, preserving the user's file mode.
chmod 0640 "$tgt"
before_mode="$(file_mode "$tgt")"
before_inode="$(file_inode "$tgt")"
remove_managed_block "$tgt"
assert_eq "$before_mode" "$(file_mode "$tgt")" "managed-block removal preserves file mode"
assert_neq "$before_inode" "$(file_inode "$tgt")" "managed-block removal atomically replaces the file"
assert_not_contains "$(cat "$tgt")" "skill-commons:start" "managed-block removal removes its fenced block"
assert_contains "$(cat "$tgt")" "User notes here." "managed-block removal preserves user content"

malformed="$TMP/malformed.md"
printf '%s\n' 'KEEP' "$AP_START" 'unterminated managed body' > "$malformed"
malformed_before="$(shasum -a 256 "$malformed")"
set +e
remove_managed_block "$malformed" >/dev/null 2>&1
malformed_rc=$?
set -e
assert_neq "0" "$malformed_rc" "managed-block removal rejects malformed fences"
assert_eq "$malformed_before" "$(shasum -a 256 "$malformed")" "malformed removal leaves the original untouched"

# cursor rule has frontmatter + stamp
rc_out=$(render_cursor_rule "$dir" "stmp00stmp00")
assert_contains "$rc_out" "alwaysApply: true" "cursor rule alwaysApply"
assert_contains "$rc_out" "DIRECTIVE LINE ONE" "cursor rule body"
assert_contains "$rc_out" "skill-commons-stamp: stmp00stmp00" "cursor rule stamp"

finish
