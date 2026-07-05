#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/manifest.sh"

# missing manifest -> defaults
assert_eq ".agent/skills/_shared" "$(get_submodule_path "$TMP/none.md")" "default submodule path"
assert_eq "claude-code cursor codex" "$(get_platforms "$TMP/none.md")" "default platforms"

# explicit values parsed
m="$TMP/manifest.md"
printf '## skill-commons bootstrap\n- submodule_path: vendor/playbook\n- platforms: claude-code, codex\n' > "$m"
assert_eq "vendor/playbook" "$(get_submodule_path "$m")" "parsed submodule path"
assert_eq "claude-code codex" "$(get_platforms "$m")" "parsed platforms (comma->space)"

finish
