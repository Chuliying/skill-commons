#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"

CHECK="$REPO/bootstrap/check.sh"

# Healthy setup: onboard a temp project first
mkdir -p "$TMP/.agent"
printf '## skill-commons bootstrap\n- platforms: claude-code, cursor, codex\n- delivery_mode: personal\n' > "$TMP/.agent/project-manifest.md"
bash "$REPO/bootstrap/onboard.sh" "$TMP" >/dev/null

# claude-code: emits hook JSON, no warning, exit 0
out=$(bash "$CHECK" --platform claude-code --project-root "$TMP"); rc=$?
assert_eq "0" "$rc" "check exits 0 when healthy"
assert_contains "$out" "hookSpecificOutput" "cc output is hook JSON"
assert_not_contains "$out" "⚠️" "no warning when healthy"

# codex: plain text, includes directive
out=$(bash "$CHECK" --platform codex --project-root "$TMP")
assert_not_contains "$out" "hookSpecificOutput" "codex plain text"
assert_contains "$out" "skill-router" "directive injected"

# drift: corrupt the CLAUDE.md stamp -> warning
sed -i.bak 's/skill-commons-stamp: [a-f0-9]*/skill-commons-stamp: deadbeefdead/' "$TMP/CLAUDE.md"
out=$(bash "$CHECK" --platform claude-code --project-root "$TMP"); rc=$?
assert_eq "0" "$rc" "check still exits 0 on drift"
assert_contains "$out" "onboard.sh" "drift warning mentions onboard.sh"

# missing coverage: remove cursor rule -> warning for cursor platform
rm -f "$TMP/.cursor/rules/skill-commons.mdc"
out=$(bash "$CHECK" --platform cursor --project-root "$TMP")
assert_contains "$out" "onboard.sh" "coverage warning mentions onboard.sh"

# uninitialized submodule: point at an empty directive via override -> init warning
empty="$TMP/empty-directive.md"; : > "$empty"
out=$(AGENT_DIRECTIVE="$empty" bash "$CHECK" --platform codex --project-root "$TMP")
assert_contains "$out" "submodule update --init" "init warning when directive empty"

finish
