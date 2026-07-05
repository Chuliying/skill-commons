#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/platform.sh"

# json_escape handles quotes and newlines
esc=$(json_escape 'a"b
c')
assert_contains "$esc" '\"' "escapes double quote"
assert_contains "$esc" '\n' "escapes newline"

# claude-code emits hook JSON wrapping the body
out=$(emit "claude-code" "DIRECTIVE_BODY" "")
assert_contains "$out" '"hookSpecificOutput"' "cc emits hookSpecificOutput"
assert_contains "$out" 'DIRECTIVE_BODY' "cc includes body"

# non-cc emits plain text body
out=$(emit "codex" "DIRECTIVE_BODY" "")
assert_not_contains "$out" 'hookSpecificOutput' "codex is plain text"
assert_contains "$out" 'DIRECTIVE_BODY' "codex includes body"

# warnings are prepended
out=$(emit "codex" "BODY" "WARNTEXT")
assert_contains "$out" 'WARNTEXT' "warnings included"

# detect_platform returns a non-empty token
p=$(detect_platform)
assert_neq "" "$p" "detect_platform returns something"

finish
