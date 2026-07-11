#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/stamp.sh"
stamp=$(compute_stamp "$REPO/bootstrap/directive.md")

assert_missing() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $2"
  else
    fail "$2"
  fi
}

assert_invalid_platform_selection() {
  local name="$1" platform_line="$2" expected="$3"
  local root="$TMP/$name" output rc
  mkdir -p "$root/.agent"
  printf '%s\n' \
    '## skill-commons bootstrap' \
    "$platform_line" \
    '- delivery_mode: personal' > "$root/.agent/project-manifest.md"
  set +e
  output="$(bash "$REPO/bootstrap/onboard.sh" "$root" 2>&1)"
  rc=$?
  set -e
  assert_neq "0" "$rc" "onboard rejects $name platform selection"
  assert_contains "$output" "$expected" "onboard explains $name platform selection"
  assert_missing "$root/AGENTS.md" "$name platform rejection happens before AGENTS shim mutation"
  assert_missing "$root/CLAUDE.md" "$name platform rejection happens before CLAUDE shim mutation"
  assert_missing "$root/.cursor/rules/skill-commons.mdc" "$name platform rejection happens before Cursor shim mutation"
  assert_missing "$root/.codex/skills" "$name platform rejection happens before skill mutation"
  assert_missing "$root/.agent/guardrails.md" "$name platform rejection happens before guardrail publication"
}

# Consuming platform selection is fail-closed. Missing, unknown, or duplicate
# values must be rejected before the first shim or generated skill is touched.
assert_invalid_platform_selection "missing" "- delivery_note: no-platform" "platform selection is required"
assert_invalid_platform_selection "unknown" "- platforms: codex, mystery-agent" "unknown platform: mystery-agent"
assert_invalid_platform_selection "duplicate" "- platforms: codex, codex" "duplicate platform: codex"

for duplicate_key in submodule_path platforms profile delivery_mode capability_packs; do
  DUPLICATE_KEY_PROJECT="$TMP/duplicate-key-$duplicate_key"
  mkdir -p "$DUPLICATE_KEY_PROJECT/.agent"
  printf '%s\n' \
    '## skill-commons bootstrap' \
    '- submodule_path: .agent/skills/_shared' \
    '- platforms: codex' \
    '- profile:' \
    '- delivery_mode: personal' \
    '- capability_packs:' \
    "- $duplicate_key: duplicate-value" > "$DUPLICATE_KEY_PROJECT/.agent/project-manifest.md"
  set +e
  duplicate_key_output="$(bash "$REPO/bootstrap/onboard.sh" "$DUPLICATE_KEY_PROJECT" 2>&1)"
  duplicate_key_rc=$?
  set -e
  assert_neq "0" "$duplicate_key_rc" "onboard rejects duplicate bootstrap key $duplicate_key"
  assert_contains "$duplicate_key_output" "duplicate bootstrap key: $duplicate_key" "duplicate $duplicate_key error is actionable"
  assert_missing "$DUPLICATE_KEY_PROJECT/AGENTS.md" "duplicate $duplicate_key fails before shim mutation"
done

# Managed adapter ancestors and prerequisite leaves must not redirect writes
# outside the consuming project.
AGENT_ESCAPE_PROJECT="$TMP/agent-ancestor-escape"
AGENT_ESCAPE_OUTSIDE="$TMP/agent-ancestor-outside"
mkdir -p "$AGENT_ESCAPE_PROJECT" "$AGENT_ESCAPE_OUTSIDE"
ln -s "$AGENT_ESCAPE_OUTSIDE" "$AGENT_ESCAPE_PROJECT/.agent"
set +e
agent_escape_output="$(bash "$REPO/bootstrap/onboard.sh" "$AGENT_ESCAPE_PROJECT" 2>&1)"
agent_escape_rc=$?
set -e
assert_neq "0" "$agent_escape_rc" "onboard rejects a symlinked .agent ancestor"
assert_contains "$agent_escape_output" "ancestor is a symlink" "symlinked .agent error is actionable"
assert_missing "$AGENT_ESCAPE_OUTSIDE/project-manifest.md" "symlinked .agent writes no external manifest"
assert_missing "$AGENT_ESCAPE_OUTSIDE/guardrails.md" "symlinked .agent writes no external guardrails"

CURSOR_ESCAPE_PROJECT="$TMP/cursor-ancestor-escape"
CURSOR_ESCAPE_OUTSIDE="$TMP/cursor-ancestor-outside"
mkdir -p "$CURSOR_ESCAPE_PROJECT/.agent" "$CURSOR_ESCAPE_OUTSIDE"
printf '%s\n' '## skill-commons bootstrap' '- platforms: cursor' '- delivery_mode: personal' > "$CURSOR_ESCAPE_PROJECT/.agent/project-manifest.md"
ln -s "$CURSOR_ESCAPE_OUTSIDE" "$CURSOR_ESCAPE_PROJECT/.cursor"
set +e
cursor_escape_output="$(bash "$REPO/bootstrap/onboard.sh" "$CURSOR_ESCAPE_PROJECT" 2>&1)"
cursor_escape_rc=$?
set -e
assert_neq "0" "$cursor_escape_rc" "onboard rejects a symlinked .cursor ancestor"
assert_contains "$cursor_escape_output" "ancestor is a symlink" "symlinked .cursor error is actionable"
assert_missing "$CURSOR_ESCAPE_OUTSIDE/rules/skill-commons.mdc" "symlinked .cursor writes no external rule"
assert_missing "$CURSOR_ESCAPE_PROJECT/AGENTS.md" "ancestor preflight happens before shim mutation"

CURSOR_COLLISION="$TMP/cursor-rule-collision"
mkdir -p "$CURSOR_COLLISION/.agent" "$CURSOR_COLLISION/.cursor/rules"
printf '%s\n' '## skill-commons bootstrap' '- platforms: cursor' '- delivery_mode: personal' > "$CURSOR_COLLISION/.agent/project-manifest.md"
printf 'foreign exact-name rule\n' > "$CURSOR_COLLISION/.cursor/rules/skill-commons.mdc"
collision_before="$(shasum -a 256 "$CURSOR_COLLISION/.cursor/rules/skill-commons.mdc")"
set +e
collision_output="$(bash "$REPO/bootstrap/onboard.sh" "$CURSOR_COLLISION" 2>&1)"
collision_rc=$?
set -e
assert_neq "0" "$collision_rc" "onboard rejects an unowned Cursor rule collision"
assert_contains "$collision_output" "unowned Cursor rule" "Cursor collision error is actionable"
assert_eq "$collision_before" "$(shasum -a 256 "$CURSOR_COLLISION/.cursor/rules/skill-commons.mdc")" "Cursor collision preserves foreign content"
assert_missing "$CURSOR_COLLISION/AGENTS.md" "Cursor collision fails before shim mutation"

UNUSED_CURSOR_SYMLINK="$TMP/unused-cursor-symlink"
UNUSED_CURSOR_OUTSIDE="$TMP/unused-cursor-outside"
mkdir -p "$UNUSED_CURSOR_SYMLINK/.agent" "$UNUSED_CURSOR_OUTSIDE"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex' '- delivery_mode: personal' > "$UNUSED_CURSOR_SYMLINK/.agent/project-manifest.md"
ln -s "$UNUSED_CURSOR_OUTSIDE" "$UNUSED_CURSOR_SYMLINK/.cursor"
if bash "$REPO/bootstrap/onboard.sh" "$UNUSED_CURSOR_SYMLINK" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Codex-only onboard ignores an unused foreign Cursor symlink"
else
  fail "Codex-only onboard ignores an unused foreign Cursor symlink"
fi
assert_file "$UNUSED_CURSOR_SYMLINK/.codex/skills/skill-router/SKILL.md" "selected Codex adapter still converges"
assert_missing "$UNUSED_CURSOR_OUTSIDE/rules/skill-commons.mdc" "unused Cursor symlink receives no managed writes"

UNUSED_CLAUDE_SYMLINK="$TMP/unused-claude-symlink"
UNUSED_CLAUDE_OUTSIDE="$TMP/unused-claude-outside"
mkdir -p "$UNUSED_CLAUDE_SYMLINK/.agent" "$UNUSED_CLAUDE_OUTSIDE"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex' '- delivery_mode: personal' > "$UNUSED_CLAUDE_SYMLINK/.agent/project-manifest.md"
ln -s "$UNUSED_CLAUDE_OUTSIDE/foreign-claude.md" "$UNUSED_CLAUDE_SYMLINK/CLAUDE.md"
if bash "$REPO/bootstrap/onboard.sh" "$UNUSED_CLAUDE_SYMLINK" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Codex-only onboard ignores an unused foreign CLAUDE symlink"
else
  fail "Codex-only onboard ignores an unused foreign CLAUDE symlink"
fi
assert_file "$UNUSED_CLAUDE_SYMLINK/.codex/skills/skill-router/SKILL.md" "Codex converges beside an unused CLAUDE symlink"

UNUSED_SETTINGS_SYMLINK="$TMP/unused-settings-symlink"
UNUSED_SETTINGS_OUTSIDE="$TMP/unused-settings-outside"
mkdir -p "$UNUSED_SETTINGS_SYMLINK/.agent" "$UNUSED_SETTINGS_SYMLINK/.claude" "$UNUSED_SETTINGS_OUTSIDE"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex' '- delivery_mode: personal' > "$UNUSED_SETTINGS_SYMLINK/.agent/project-manifest.md"
printf '{"foreign":true}\n' > "$UNUSED_SETTINGS_OUTSIDE/settings.json"
ln -s "$UNUSED_SETTINGS_OUTSIDE/settings.json" "$UNUSED_SETTINGS_SYMLINK/.claude/settings.json"
if bash "$REPO/bootstrap/onboard.sh" "$UNUSED_SETTINGS_SYMLINK" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Codex-only onboard ignores an unused foreign Claude settings symlink"
else
  fail "Codex-only onboard ignores an unused foreign Claude settings symlink"
fi
assert_contains "$(cat "$UNUSED_SETTINGS_OUTSIDE/settings.json")" '"foreign":true' "unused foreign settings stay untouched"

for unsafe_submodule in '/tmp/external-skill-commons' '../external-skill-commons'; do
  UNSAFE_SUBMODULE_PROJECT="$TMP/unsafe-submodule-${unsafe_submodule%%/*}"
  mkdir -p "$UNSAFE_SUBMODULE_PROJECT/.agent"
  printf '%s\n' \
    '## skill-commons bootstrap' \
    "- submodule_path: $unsafe_submodule" \
    '- platforms: claude-code' \
    '- delivery_mode: personal' > "$UNSAFE_SUBMODULE_PROJECT/.agent/project-manifest.md"
  set +e
  unsafe_submodule_output="$(bash "$REPO/bootstrap/onboard.sh" "$UNSAFE_SUBMODULE_PROJECT" 2>&1)"
  unsafe_submodule_rc=$?
  set -e
  assert_neq "0" "$unsafe_submodule_rc" "onboard rejects unsafe submodule_path $unsafe_submodule"
  assert_contains "$unsafe_submodule_output" "submodule_path" "unsafe submodule path error is actionable"
  assert_missing "$UNSAFE_SUBMODULE_PROJECT/CLAUDE.md" "unsafe submodule path fails before Claude shim mutation"
done

SYMLINK_SUBMODULE_PROJECT="$TMP/symlink-submodule-path"
SYMLINK_SUBMODULE_OUTSIDE="$TMP/symlink-submodule-outside"
mkdir -p "$SYMLINK_SUBMODULE_PROJECT/.agent" "$SYMLINK_SUBMODULE_PROJECT/.vendor" "$SYMLINK_SUBMODULE_OUTSIDE/bootstrap"
printf '%s\n' \
  '## skill-commons bootstrap' \
  '- submodule_path: .vendor/shared' \
  '- platforms: claude-code' \
  '- delivery_mode: personal' > "$SYMLINK_SUBMODULE_PROJECT/.agent/project-manifest.md"
ln -s "$SYMLINK_SUBMODULE_OUTSIDE" "$SYMLINK_SUBMODULE_PROJECT/.vendor/shared"
printf '#!/usr/bin/env bash\ntouch "$1"\n' > "$SYMLINK_SUBMODULE_OUTSIDE/bootstrap/check.sh"
chmod +x "$SYMLINK_SUBMODULE_OUTSIDE/bootstrap/check.sh"
set +e
symlink_submodule_output="$(bash "$REPO/bootstrap/onboard.sh" "$SYMLINK_SUBMODULE_PROJECT" 2>&1)"
symlink_submodule_rc=$?
set -e
assert_neq "0" "$symlink_submodule_rc" "onboard rejects a symlinked submodule_path component"
assert_contains "$symlink_submodule_output" "submodule_path component is a symlink" "symlinked submodule path error is actionable"
assert_missing "$SYMLINK_SUBMODULE_PROJECT/CLAUDE.md" "symlinked submodule path fails before Claude shim mutation"

AMBIGUOUS_HOOK_PROJECT="$TMP/ambiguous-foreign-hook"
mkdir -p "$AMBIGUOUS_HOOK_PROJECT/.agent" "$AMBIGUOUS_HOOK_PROJECT/.claude"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex, claude-code' '- delivery_mode: personal' > "$AMBIGUOUS_HOOK_PROJECT/.agent/project-manifest.md"
printf 'KEEP AMBIGUOUS AGENTS\n' > "$AMBIGUOUS_HOOK_PROJECT/AGENTS.md"
printf 'KEEP AMBIGUOUS CLAUDE\n' > "$AMBIGUOUS_HOOK_PROJECT/CLAUDE.md"
cat > "$AMBIGUOUS_HOOK_PROJECT/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [{
      "matcher": "foreign",
      "hooks": [{
        "type": "command",
        "command": "bash tools/bootstrap/check.sh --platform claude-code --project-root \"$CLAUDE_PROJECT_DIR\""
      }]
    }]
  }
}
EOF
ambiguous_agents_before="$(shasum -a 256 "$AMBIGUOUS_HOOK_PROJECT/AGENTS.md")"
ambiguous_claude_before="$(shasum -a 256 "$AMBIGUOUS_HOOK_PROJECT/CLAUDE.md")"
ambiguous_before="$(shasum -a 256 "$AMBIGUOUS_HOOK_PROJECT/.claude/settings.json")"
set +e
ambiguous_output="$(bash "$REPO/bootstrap/onboard.sh" "$AMBIGUOUS_HOOK_PROJECT" 2>&1)"
ambiguous_rc=$?
set -e
assert_neq "0" "$ambiguous_rc" "onboard rejects an ambiguous unmarked bootstrap hook"
assert_contains "$ambiguous_output" "ambiguous unmarked" "ambiguous hook error is actionable"
assert_eq "$ambiguous_before" "$(shasum -a 256 "$AMBIGUOUS_HOOK_PROJECT/.claude/settings.json")" "ambiguous hook remains untouched"
assert_eq "$ambiguous_agents_before" "$(shasum -a 256 "$AMBIGUOUS_HOOK_PROJECT/AGENTS.md")" "ambiguous hook fails before AGENTS publication"
assert_eq "$ambiguous_claude_before" "$(shasum -a 256 "$AMBIGUOUS_HOOK_PROJECT/CLAUDE.md")" "ambiguous hook fails before CLAUDE publication"
assert_missing "$AMBIGUOUS_HOOK_PROJECT/.agent/guardrails.md" "ambiguous hook fails before guardrail publication"
assert_missing "$AMBIGUOUS_HOOK_PROJECT/.codex/skills" "ambiguous hook fails before generated-skill publication"

# A selected adapter dependency failure is also a preflight failure. A jq that
# cannot execute must not leave earlier platform shims behind.
BROKEN_JQ_PROJECT="$TMP/broken-jq-preflight"
BROKEN_JQ_BIN="$TMP/broken-jq-bin"
mkdir -p "$BROKEN_JQ_PROJECT/.agent" "$BROKEN_JQ_BIN"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex, claude-code' '- delivery_mode: personal' > "$BROKEN_JQ_PROJECT/.agent/project-manifest.md"
printf 'KEEP BROKEN JQ AGENTS\n' > "$BROKEN_JQ_PROJECT/AGENTS.md"
printf 'KEEP BROKEN JQ CLAUDE\n' > "$BROKEN_JQ_PROJECT/CLAUDE.md"
printf '%s\n' '#!/usr/bin/env bash' 'exit 127' > "$BROKEN_JQ_BIN/jq"
chmod +x "$BROKEN_JQ_BIN/jq"
broken_jq_agents_before="$(shasum -a 256 "$BROKEN_JQ_PROJECT/AGENTS.md")"
broken_jq_claude_before="$(shasum -a 256 "$BROKEN_JQ_PROJECT/CLAUDE.md")"
set +e
PATH="$BROKEN_JQ_BIN:$PATH" bash "$REPO/bootstrap/onboard.sh" "$BROKEN_JQ_PROJECT" >/dev/null 2>&1
broken_jq_rc=$?
set -e
assert_neq "0" "$broken_jq_rc" "onboard rejects an unusable selected adapter dependency"
assert_eq "$broken_jq_agents_before" "$(shasum -a 256 "$BROKEN_JQ_PROJECT/AGENTS.md")" "dependency failure happens before AGENTS publication"
assert_eq "$broken_jq_claude_before" "$(shasum -a 256 "$BROKEN_JQ_PROJECT/CLAUDE.md")" "dependency failure happens before CLAUDE publication"
assert_missing "$BROKEN_JQ_PROJECT/.agent/guardrails.md" "dependency failure happens before guardrail publication"

# Filesystem publication capability is part of preflight. A selected adapter
# directory that cannot accept atomic temp files must fail before any shim or
# generated-skill target is published.
READONLY_CURSOR_PROJECT="$TMP/readonly-cursor-preflight"
mkdir -p "$READONLY_CURSOR_PROJECT/.agent" "$READONLY_CURSOR_PROJECT/.cursor"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex, cursor' '- delivery_mode: personal' > "$READONLY_CURSOR_PROJECT/.agent/project-manifest.md"
chmod 0555 "$READONLY_CURSOR_PROJECT/.cursor"
set +e
readonly_cursor_output="$(bash "$REPO/bootstrap/onboard.sh" "$READONLY_CURSOR_PROJECT" 2>&1)"
readonly_cursor_rc=$?
set -e
chmod 0755 "$READONLY_CURSOR_PROJECT/.cursor"
assert_neq "0" "$readonly_cursor_rc" "onboard preflights selected adapter writability"
assert_contains "$readonly_cursor_output" "not writable" "adapter writability failure is actionable"
assert_missing "$READONLY_CURSOR_PROJECT/AGENTS.md" "adapter writability failure precedes shim publication"
assert_missing "$READONLY_CURSOR_PROJECT/.codex/skills" "adapter writability failure precedes generated skills"

# manifest enabling all three platforms; pre-existing AGENTS.md user content
mkdir -p "$TMP/.agent"
printf '## skill-commons bootstrap\n- platforms: claude-code, cursor, codex\n- delivery_mode: personal\n' > "$TMP/.agent/project-manifest.md"
printf '# Existing\nKEEP ME\n' > "$TMP/AGENTS.md"

bash "$REPO/bootstrap/onboard.sh" "$TMP"

assert_file "$TMP/AGENTS.md" "AGENTS.md exists"
assert_file "$TMP/CLAUDE.md" "CLAUDE.md exists"
assert_file "$TMP/.cursor/rules/skill-commons.mdc" "cursor rule exists"
assert_file "$TMP/.claude/settings.json" "settings.json exists"

agents="$(cat "$TMP/AGENTS.md")"
assert_contains "$agents" "KEEP ME" "AGENTS.md preserves user content"
assert_contains "$agents" "skill-commons-stamp: $stamp" "AGENTS.md has current stamp"

claude="$(cat "$TMP/CLAUDE.md")"
assert_contains "$claude" "skill-commons-stamp: $stamp" "CLAUDE.md has current stamp"

settings="$(cat "$TMP/.claude/settings.json")"
assert_contains "$settings" "bootstrap/check.sh" "settings.json wires check.sh"
assert_contains "$settings" "startup|clear|compact" "settings.json hook matcher"

# A SessionStart group may contain hooks owned by more than one tool. Updating
# skill-commons replaces only its matching hook element, never the whole group.
if command -v jq >/dev/null 2>&1; then
  settings_tmp="$TMP/.claude/settings.json.foreign-sibling"
  jq '
    (.hooks.SessionStart[]
      | select(any(.hooks[]?; (.command // "") | test("_shared/bootstrap/check\\.sh")))
      | .hooks) += [
        {type: "command", command: "foreign-sibling-hook", async: false}
      ]
  ' "$TMP/.claude/settings.json" > "$settings_tmp"
  mv "$settings_tmp" "$TMP/.claude/settings.json"
  bash "$REPO/bootstrap/manage.sh" update "$TMP" >/dev/null
  foreign_hook_count="$(jq '[.hooks.SessionStart[].hooks[]? | select((.command // "") == "foreign-sibling-hook")] | length' "$TMP/.claude/settings.json")"
  managed_hook_count="$(jq '[.hooks.SessionStart[].hooks[]? | select((.command // "") | test("_shared/bootstrap/check\\.sh"))] | length' "$TMP/.claude/settings.json")"
  assert_eq "1" "$foreign_hook_count" "update preserves a foreign sibling hook"
  assert_eq "1" "$managed_hook_count" "update replaces only the managed hook"
else
  echo "  (skipped sibling-hook preservation assertion: jq not installed)"
fi

if command -v jq >/dev/null 2>&1; then
  CUSTOM_HOOK_PROJECT="$TMP/custom-hook-path"
  mkdir -p "$CUSTOM_HOOK_PROJECT/.agent"
  printf '%s\n' \
    '## skill-commons bootstrap' \
    '- submodule_path: .vendor/skill commons' \
    '- platforms: claude-code' \
    '- delivery_mode: personal' > "$CUSTOM_HOOK_PROJECT/.agent/project-manifest.md"
  bash "$REPO/bootstrap/onboard.sh" "$CUSTOM_HOOK_PROJECT" >/dev/null
  bash "$REPO/bootstrap/onboard.sh" "$CUSTOM_HOOK_PROJECT" >/dev/null
  custom_hook_count="$(jq '[.hooks.SessionStart[].hooks[]? | select(((.command // "") | contains("/bootstrap/check.sh --platform claude-code --project-root \"$CLAUDE_PROJECT_DIR\"")) and ((.command // "") | endswith("# skill-commons-managed")))] | length' "$CUSTOM_HOOK_PROJECT/.claude/settings.json")"
  assert_eq "1" "$custom_hook_count" "custom submodule hook stays idempotent"
  if bash "$REPO/bootstrap/manage.sh" doctor "$CUSTOM_HOOK_PROJECT" >/dev/null 2>&1; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor accepts the idempotent custom-path hook"
  else
    fail "doctor accepts the idempotent custom-path hook"
  fi
fi

# idempotent: second run leaves AGENTS.md unchanged
before="$(cat "$TMP/AGENTS.md")"
bash "$REPO/bootstrap/onboard.sh" "$TMP"
after="$(cat "$TMP/AGENTS.md")"
assert_eq "$before" "$after" "onboard is idempotent on AGENTS.md"
n=$(grep -c "skill-commons:start" "$TMP/AGENTS.md")
assert_eq "1" "$n" "no duplicate managed block after rerun"

# settings.json hook not duplicated after rerun (requires jq)
if command -v jq >/dev/null 2>&1; then
  cnt=$(jq '[.hooks.SessionStart[] | select(.hooks[]?.command | test("_shared/bootstrap/check.sh"))] | length' "$TMP/.claude/settings.json")
  assert_eq "1" "$cnt" "single skill-commons SessionStart hook after rerun"
else
  echo "  (skipped jq dedup assertion: jq not installed)"
fi

# generation failure must not be reported as a successful onboard
FAIL_SHARED="$TMP/failing-shared"
FAIL_PROJECT="$TMP/failing-project"
mkdir -p "$FAIL_SHARED" "$FAIL_PROJECT/.agent"
cp -R "$REPO/bootstrap" "$FAIL_SHARED/bootstrap"
printf '#!/usr/bin/env bash\nexit 42\n' > "$FAIL_SHARED/bootstrap/generate.sh"
printf '## skill-commons bootstrap\n- platforms: codex\n- delivery_mode: personal\n' > "$FAIL_PROJECT/.agent/project-manifest.md"
printf 'existing guardrails\n' > "$FAIL_PROJECT/.agent/guardrails.md"
fail_guardrail_before="$(shasum -a 256 "$FAIL_PROJECT/.agent/guardrails.md")"
set +e
bash "$FAIL_SHARED/bootstrap/onboard.sh" "$FAIL_PROJECT" >/dev/null 2>&1
generate_rc=$?
set -e
assert_neq "0" "$generate_rc" "onboard fails when skill generation fails"
assert_missing "$FAIL_PROJECT/AGENTS.md" "skill-generation preflight fails before AGENTS publication"
assert_eq "$fail_guardrail_before" "$(shasum -a 256 "$FAIL_PROJECT/.agent/guardrails.md")" "skill-generation preflight preserves an existing guardrail"
assert_missing "$FAIL_PROJECT/.codex/skills" "skill-generation preflight publishes no partial target"

# security regression: a malicious submodule_path from an untrusted manifest must not
# escape into the generated SessionStart hook command. onboard.sh never runs this
# command itself -- Claude Code's hook runner does, on every future session start --
# so the test has to simulate that execution to actually prove the injection is inert,
# not just eyeball the string.
if command -v jq >/dev/null 2>&1; then
  INJ_PROJECT="$TMP/injection-project"
  mkdir -p "$INJ_PROJECT/.agent"
  marker="$TMP/pwned-marker"
  rm -f "$marker"
  printf '## skill-commons bootstrap\n- submodule_path: .agent/skills/_shared; touch %s; true\n- platforms: claude-code\n- delivery_mode: personal\n' "$marker" > "$INJ_PROJECT/.agent/project-manifest.md"
  bash "$REPO/bootstrap/onboard.sh" "$INJ_PROJECT" >/dev/null 2>&1 || true
  hook_cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command // ""' "$INJ_PROJECT/.claude/settings.json" 2>/dev/null || true)"
  assert_not_contains "$hook_cmd" "; touch $marker" "malicious submodule_path is quoted, not spliced as shell syntax"
  bash -c "$hook_cmd" >/dev/null 2>&1 || true
  if [ -f "$marker" ]; then
    fail "injected submodule_path executed when the generated hook command ran"
    rm -f "$marker"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: injected submodule_path does not execute when the hook command runs"
  fi
else
  echo "  (skipped submodule_path injection test: jq not installed)"
fi

# A completely fresh repository must become routable without first hand-writing
# the two files that skill-router requires. Generated skeletons are conservative
# and user-owned: rerunning onboarding must never overwrite them.
FRESH="$TMP/fresh-repo"
mkdir -p "$FRESH"
bash "$REPO/bootstrap/onboard.sh" "$FRESH" >/dev/null

assert_file "$FRESH/.agent/project-manifest.md" "fresh repo gets minimal project manifest"
assert_file "$FRESH/.agent/guardrails.md" "fresh repo gets conservative guardrails"
assert_file "$FRESH/.codex/skills/skill-router/SKILL.md" "fresh repo gets generated skill-router"

fresh_manifest="$(cat "$FRESH/.agent/project-manifest.md")"
assert_contains "$fresh_manifest" "## skill-commons bootstrap" "minimal manifest has bootstrap section"
assert_contains "$fresh_manifest" "## Paths" "minimal manifest has Paths section"
assert_contains "$fresh_manifest" "## Stack" "minimal manifest has Stack section"
assert_contains "$fresh_manifest" "## Git Workflow" "minimal manifest has Git Workflow section"
assert_contains "$fresh_manifest" "<!-- TODO" "minimal manifest marks fields for discovery"
assert_contains "$fresh_manifest" "has_ui: false" "minimal manifest defaults UI capability false"
assert_contains "$fresh_manifest" "has_api: false" "minimal manifest defaults API capability false"
assert_contains "$fresh_manifest" "typed_contracts: false" "minimal manifest defaults typed contracts false"
assert_contains "$fresh_manifest" "has_e2e: false" "minimal manifest defaults E2E capability false"

fresh_guardrails="$(cat "$FRESH/.agent/guardrails.md")"
assert_contains "$fresh_guardrails" "force push" "guardrails forbid force push"
assert_contains "$fresh_guardrails" "遠端 branch" "guardrails forbid remote branch deletion"
assert_contains "$fresh_guardrails" ".env" "guardrails protect environment files"
assert_contains "$fresh_guardrails" "不可逆" "guardrails require confirmation for irreversible operations"

manifest_before="$(shasum -a 256 "$FRESH/.agent/project-manifest.md")"
guardrails_before="$(shasum -a 256 "$FRESH/.agent/guardrails.md")"
bash "$REPO/bootstrap/onboard.sh" "$FRESH" >/dev/null
manifest_after="$(shasum -a 256 "$FRESH/.agent/project-manifest.md")"
guardrails_after="$(shasum -a 256 "$FRESH/.agent/guardrails.md")"
assert_eq "$manifest_before" "$manifest_after" "onboard does not overwrite generated manifest"
assert_eq "$guardrails_before" "$guardrails_after" "onboard does not overwrite generated guardrails"

# Agent skill roots are shared discovery locations, not disposable
# skill-commons-only directories. Rerunning onboarding must preserve entries
# installed by the user or another plugin.
mkdir -p "$FRESH/.codex/skills/foreign-skill"
printf 'foreign\n' > "$FRESH/.codex/skills/foreign-skill/marker"
bash "$REPO/bootstrap/onboard.sh" "$FRESH" >/dev/null
assert_file "$FRESH/.codex/skills/foreign-skill/marker" "onboard preserves foreign skills"

# A project path is one argv item even when it contains spaces. Run from an
# isolated cwd so a regression cannot create relative wrong-target directories
# outside this temporary fixture.
SPACED_PARENT="$TMP/spaced-parent"
SPACED_PROJECT="$SPACED_PARENT/project with spaces"
SPACED_RUN="$SPACED_PARENT/run"
mkdir -p "$SPACED_PROJECT" "$SPACED_RUN"
(
  cd "$SPACED_RUN" || exit 1
  bash "$REPO/bootstrap/onboard.sh" "$SPACED_PROJECT" >/dev/null
)
assert_file "$SPACED_PROJECT/.codex/skills/skill-router/SKILL.md" "onboard handles project paths with spaces"
if [ -e "$SPACED_PARENT/project" ] || [ -e "$SPACED_RUN/with" ] || [ -e "$SPACED_RUN/spaces" ]; then
  fail "onboard generated into split wrong-target paths"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: onboard does not generate into split wrong-target paths"
fi

# A dangling prerequisite symlink is neither a usable file nor safe to replace.
# Onboarding must fail clearly instead of reporting success with router inputs
# still missing.
INVALID="$TMP/invalid-prerequisite"
mkdir -p "$INVALID/.agent"
ln -s "$INVALID/does-not-exist" "$INVALID/.agent/project-manifest.md"
set +e
bash "$REPO/bootstrap/onboard.sh" "$INVALID" >/dev/null 2>&1
invalid_rc=$?
set -e
assert_neq "0" "$invalid_rc" "onboard rejects dangling prerequisite symlink"
if [ -L "$INVALID/.agent/project-manifest.md" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: onboard does not replace dangling prerequisite symlink"
else
  fail "onboard replaced dangling prerequisite symlink"
fi

finish
