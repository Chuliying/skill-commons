#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/stamp.sh"
stamp=$(compute_stamp "$REPO/bootstrap/directive.md")

# manifest enabling all three platforms; pre-existing AGENTS.md user content
mkdir -p "$TMP/.agent"
printf '## skill-commons bootstrap\n- platforms: claude-code, cursor, codex\n' > "$TMP/.agent/project-manifest.md"
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
printf '## skill-commons bootstrap\n- platforms: codex\n' > "$FAIL_PROJECT/.agent/project-manifest.md"
set +e
bash "$FAIL_SHARED/bootstrap/onboard.sh" "$FAIL_PROJECT" >/dev/null 2>&1
generate_rc=$?
set -e
assert_neq "0" "$generate_rc" "onboard fails when skill generation fails"

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
  printf '## skill-commons bootstrap\n- submodule_path: .agent/skills/_shared; touch %s; true\n- platforms: claude-code\n' "$marker" > "$INJ_PROJECT/.agent/project-manifest.md"
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
