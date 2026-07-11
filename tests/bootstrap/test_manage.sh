#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/ownership.sh"

MANAGE="$REPO/bootstrap/manage.sh"

new_project() {
  local root="$1" platforms="${2:-codex}"
  mkdir -p "$root/.agent"
  printf '%s\n' \
    '## skill-commons bootstrap' \
    "- platforms: $platforms" \
    '- delivery_mode: personal' > "$root/.agent/project-manifest.md"
  bash "$REPO/bootstrap/onboard.sh" "$root" >/dev/null
}

tree_digest() {
  local root="$1"
  find "$root" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
}

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

file_inode() {
  stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1"
}

assert_missing() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $2"
  else
    fail "$2"
  fi
}

# doctor is read-only and validates a healthy explicit installation.
HEALTHY="$TMP/healthy"
new_project "$HEALTHY" "claude-code, cursor, codex"
before_doctor="$(tree_digest "$HEALTHY")"
set +e
doctor_output="$(bash "$MANAGE" doctor "$HEALTHY" 2>&1)"
doctor_rc=$?
set -e
assert_eq "0" "$doctor_rc" "doctor accepts a healthy explicit installation"
assert_contains "$doctor_output" "doctor: healthy" "doctor emits a bounded healthy result"
assert_eq "$before_doctor" "$(tree_digest "$HEALTHY")" "doctor is read-only"

# Shrinking platform selection without first uninstalling would hide active
# adapters from doctor/update/uninstall. Fail closed and give one explicit
# migration sequence instead of leaving residue.
SHRINK="$TMP/platform-shrink"
new_project "$SHRINK" "claude-code, cursor, codex"
perl -0pi -e 's/- platforms: claude-code, cursor, codex/- platforms: codex/' "$SHRINK/.agent/project-manifest.md"
shrink_manifest="$(cat "$SHRINK/.agent/project-manifest.md")"
shrink_before="$(tree_digest "$SHRINK")"
set +e
shrink_update_output="$(bash "$MANAGE" update "$SHRINK" 2>&1)"
shrink_update_rc=$?
shrink_doctor_output="$(bash "$MANAGE" doctor "$SHRINK" 2>&1)"
shrink_doctor_rc=$?
shrink_uninstall_output="$(bash "$MANAGE" uninstall "$SHRINK" 2>&1)"
shrink_uninstall_rc=$?
set -e
assert_neq "0" "$shrink_update_rc" "update rejects an implicit platform shrink"
assert_neq "0" "$shrink_doctor_rc" "doctor rejects deselected managed adapters"
assert_neq "0" "$shrink_uninstall_rc" "uninstall rejects a manifest that hides managed adapters"
assert_contains "$shrink_update_output" "deselected platform" "platform-shrink error names the stale state"
assert_contains "$shrink_update_output" "restore the previous platform selection" "platform-shrink error gives migration guidance"
assert_contains "$shrink_doctor_output" "claude-code" "platform-shrink error names the Claude residue"
assert_contains "$shrink_uninstall_output" "cursor" "platform-shrink error names the Cursor residue"
assert_eq "$shrink_before" "$(tree_digest "$SHRINK")" "failed shrink commands make no project mutation"
assert_file "$SHRINK/.claude/skills/.skill-commons-ownership-v1" "failed shrink preserves the Claude ledger"
assert_file "$SHRINK/.cursor/rules/skill-commons.mdc" "failed shrink preserves the Cursor rule"
assert_contains "$shrink_manifest" "platforms: codex" "failed shrink preserves the user's manifest choice"

# Restoring the previous selection makes explicit uninstall possible; the user
# can then select the smaller set and onboard it from a clean managed state.
perl -0pi -e 's/- platforms: codex/- platforms: claude-code, cursor, codex/' "$SHRINK/.agent/project-manifest.md"
bash "$MANAGE" uninstall "$SHRINK" >/dev/null
perl -0pi -e 's/- platforms: claude-code, cursor, codex/- platforms: codex/' "$SHRINK/.agent/project-manifest.md"
bash "$REPO/bootstrap/onboard.sh" "$SHRINK" >/dev/null
if bash "$MANAGE" doctor "$SHRINK" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: explicit uninstall then smaller re-onboard converges"
else
  fail "explicit uninstall then smaller re-onboard converges"
fi

# Missing selection/platform, malformed ledgers, missing units, and drift all
# fail closed with no implicit guesses.
NO_SELECTION="$TMP/no-selection"
mkdir -p "$NO_SELECTION/.agent"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex' > "$NO_SELECTION/.agent/project-manifest.md"
if bash "$MANAGE" doctor "$NO_SELECTION" >/dev/null 2>&1; then
  fail "doctor rejects missing delivery selection"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor rejects missing delivery selection"
fi

NO_PLATFORM="$TMP/no-platform"
mkdir -p "$NO_PLATFORM/.agent"
printf '%s\n' '## skill-commons bootstrap' '- delivery_mode: personal' > "$NO_PLATFORM/.agent/project-manifest.md"
if bash "$MANAGE" doctor "$NO_PLATFORM" >/dev/null 2>&1; then
  fail "doctor rejects missing platform selection"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor rejects missing platform selection"
fi

MALFORMED="$TMP/malformed"
new_project "$MALFORMED" codex
printf '%s\n' 'skill-commons-ownership-v1' $'D\t../escape' > "$MALFORMED/.codex/skills/.skill-commons-ownership-v1"
if bash "$MANAGE" doctor "$MALFORMED" >/dev/null 2>&1; then
  fail "doctor rejects a malformed ledger"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor rejects a malformed ledger"
fi

MISSING="$TMP/missing-unit"
new_project "$MISSING" codex
rm -rf "$MISSING/.codex/skills/skill-router"
if bash "$MANAGE" doctor "$MISSING" >/dev/null 2>&1; then
  fail "doctor rejects a missing generated unit"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor rejects a missing generated unit"
fi

MISSING_TARGET="$TMP/missing-target"
new_project "$MISSING_TARGET" codex
rm -rf "$MISSING_TARGET/.codex/skills"
if bash "$MANAGE" doctor "$MISSING_TARGET" >/dev/null 2>&1; then
  fail "doctor rejects a missing generated target"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor rejects a missing generated target"
fi

DRIFT="$TMP/drift"
new_project "$DRIFT" codex
printf '\nforeign drift\n' >> "$DRIFT/.codex/skills/skill-router/SKILL.md"
if bash "$MANAGE" doctor "$DRIFT" >/dev/null 2>&1; then
  fail "doctor rejects generated-content drift"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor rejects generated-content drift"
fi
bash "$MANAGE" update "$DRIFT" >/dev/null
if bash "$MANAGE" doctor "$DRIFT" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: update delegates to onboarding and repairs drift"
else
  fail "update delegates to onboarding and repairs drift"
fi

# The ledger is observed ownership state, not the desired inventory. Removing a
# required shared file and its row together must not make doctor false-healthy.
INCOMPLETE_LEDGER="$TMP/incomplete-ledger"
new_project "$INCOMPLETE_LEDGER" codex
incomplete_ledger="$INCOMPLETE_LEDGER/.codex/skills/.skill-commons-ownership-v1"
rm -f "$INCOMPLETE_LEDGER/.codex/skills/protocol-registry.json"
awk -F $'\t' '
  !($1 == "F" && $2 == "protocol-registry.json") { print }
' "$incomplete_ledger" > "$incomplete_ledger.next"
mv "$incomplete_ledger.next" "$incomplete_ledger"
set +e
incomplete_output="$(bash "$MANAGE" doctor "$INCOMPLETE_LEDGER" 2>&1)"
incomplete_rc=$?
set -e
assert_neq "0" "$incomplete_rc" "doctor rejects a ledger missing a required shared record"
assert_contains "$incomplete_output" "ownership ledger does not match expected installation" "incomplete-ledger error names the desired-state mismatch"
bash "$MANAGE" update "$INCOMPLETE_LEDGER" >/dev/null
if bash "$MANAGE" doctor "$INCOMPLETE_LEDGER" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: update repairs an incomplete ownership ledger"
else
  fail "update repairs an incomplete ownership ledger"
fi

# uninstall removes only ledger-owned units and managed shim/rule/hook content.
UNINSTALL="$TMP/uninstall"
mkdir -p "$UNINSTALL"
printf 'KEEP AGENTS\n' > "$UNINSTALL/AGENTS.md"
printf 'KEEP CLAUDE\n' > "$UNINSTALL/CLAUDE.md"
new_project "$UNINSTALL" "claude-code, cursor, codex"
mkdir -p \
  "$UNINSTALL/.claude/skills/foreign-skill" \
  "$UNINSTALL/.codex/skills/foreign-skill" \
  "$UNINSTALL/.cursor/rules" \
  "$UNINSTALL/.agent/skills/_shared"
printf 'foreign\n' > "$UNINSTALL/.claude/skills/foreign-skill/KEEP"
printf 'foreign\n' > "$UNINSTALL/.codex/skills/foreign-skill/KEEP"
printf 'foreign rule\n' > "$UNINSTALL/.cursor/rules/foreign.mdc"
printf 'submodule marker\n' > "$UNINSTALL/.agent/skills/_shared/KEEP"
settings_tmp="$(mktemp)"
jq '.hooks.SessionStart[0].hooks += [{"type":"command","command":"foreign-sibling-hook"}]
    | .hooks.SessionStart += [{"matcher":"foreign","hooks":[{"type":"command","command":"foreign-hook"}]}]' \
  "$UNINSTALL/.claude/settings.json" > "$settings_tmp" && mv "$settings_tmp" "$UNINSTALL/.claude/settings.json"
chmod 0640 "$UNINSTALL/AGENTS.md" "$UNINSTALL/CLAUDE.md" "$UNINSTALL/.claude/settings.json"
agents_mode_before="$(file_mode "$UNINSTALL/AGENTS.md")"
claude_mode_before="$(file_mode "$UNINSTALL/CLAUDE.md")"
settings_mode_before="$(file_mode "$UNINSTALL/.claude/settings.json")"
agents_inode_before="$(file_inode "$UNINSTALL/AGENTS.md")"
claude_inode_before="$(file_inode "$UNINSTALL/CLAUDE.md")"
settings_inode_before="$(file_inode "$UNINSTALL/.claude/settings.json")"
manifest_hash="$(shasum -a 256 "$UNINSTALL/.agent/project-manifest.md")"
guardrails_hash="$(shasum -a 256 "$UNINSTALL/.agent/guardrails.md")"

bash "$MANAGE" uninstall "$UNINSTALL" >/dev/null
assert_missing "$UNINSTALL/.claude/skills/skill-router" "uninstall removes Claude ledger-owned skills"
assert_missing "$UNINSTALL/.codex/skills/skill-router" "uninstall removes Codex ledger-owned skills"
assert_missing "$UNINSTALL/.claude/skills/.skill-commons-ownership-v1" "uninstall removes Claude ownership ledger"
assert_missing "$UNINSTALL/.codex/skills/.skill-commons-ownership-v1" "uninstall removes Codex ownership ledger"
assert_file "$UNINSTALL/.claude/skills/foreign-skill/KEEP" "uninstall preserves foreign Claude skills"
assert_file "$UNINSTALL/.codex/skills/foreign-skill/KEEP" "uninstall preserves foreign Codex skills"
assert_contains "$(cat "$UNINSTALL/AGENTS.md")" "KEEP AGENTS" "uninstall preserves foreign AGENTS content"
assert_not_contains "$(cat "$UNINSTALL/AGENTS.md")" "skill-commons:start" "uninstall removes managed AGENTS block"
assert_contains "$(cat "$UNINSTALL/CLAUDE.md")" "KEEP CLAUDE" "uninstall preserves foreign CLAUDE content"
assert_not_contains "$(cat "$UNINSTALL/CLAUDE.md")" "skill-commons:start" "uninstall removes managed CLAUDE block"
assert_missing "$UNINSTALL/.cursor/rules/skill-commons.mdc" "uninstall removes the managed Cursor rule"
assert_file "$UNINSTALL/.cursor/rules/foreign.mdc" "uninstall preserves foreign Cursor rules"
settings="$(cat "$UNINSTALL/.claude/settings.json")"
assert_contains "$settings" "foreign-hook" "uninstall preserves foreign Claude hooks"
assert_contains "$settings" "foreign-sibling-hook" "uninstall preserves a foreign sibling of the managed Claude hook"
assert_not_contains "$settings" "_shared/bootstrap/check.sh" "uninstall removes the managed Claude hook"
assert_eq "$agents_mode_before" "$(file_mode "$UNINSTALL/AGENTS.md")" "uninstall preserves AGENTS mode"
assert_eq "$claude_mode_before" "$(file_mode "$UNINSTALL/CLAUDE.md")" "uninstall preserves CLAUDE mode"
assert_eq "$settings_mode_before" "$(file_mode "$UNINSTALL/.claude/settings.json")" "uninstall preserves Claude settings mode"
assert_neq "$agents_inode_before" "$(file_inode "$UNINSTALL/AGENTS.md")" "uninstall atomically replaces AGENTS"
assert_neq "$claude_inode_before" "$(file_inode "$UNINSTALL/CLAUDE.md")" "uninstall atomically replaces CLAUDE"
assert_neq "$settings_inode_before" "$(file_inode "$UNINSTALL/.claude/settings.json")" "uninstall atomically replaces Claude settings"
assert_eq "$manifest_hash" "$(shasum -a 256 "$UNINSTALL/.agent/project-manifest.md")" "uninstall preserves project manifest"
assert_eq "$guardrails_hash" "$(shasum -a 256 "$UNINSTALL/.agent/guardrails.md")" "uninstall preserves guardrails"
assert_file "$UNINSTALL/.agent/skills/_shared/KEEP" "uninstall preserves the submodule path"

# Every target and shim is preflighted before the first deletion.
PARTIAL="$TMP/partial"
new_project "$PARTIAL" "claude-code, codex"
printf '%s\n' 'bad-schema' > "$PARTIAL/.codex/skills/.skill-commons-ownership-v1"
if bash "$MANAGE" uninstall "$PARTIAL" >/dev/null 2>&1; then
  fail "uninstall rejects a malformed later target"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: uninstall rejects a malformed later target"
fi
assert_file "$PARTIAL/.claude/skills/skill-router/SKILL.md" "later target failure leaves the first target untouched"
assert_file "$PARTIAL/.claude/skills/.skill-commons-ownership-v1" "later target failure preserves the first ledger"

# Canonical path and symlink validation apply before deletion.
SYMLINK_PROJECT="$TMP/symlink-project"
SYMLINK_OUTSIDE="$TMP/symlink-outside"
mkdir -p "$SYMLINK_PROJECT/.agent" "$SYMLINK_PROJECT/.codex" "$SYMLINK_OUTSIDE"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex' '- delivery_mode: personal' > "$SYMLINK_PROJECT/.agent/project-manifest.md"
printf 'outside\n' > "$SYMLINK_OUTSIDE/KEEP"
ln -s "$SYMLINK_OUTSIDE" "$SYMLINK_PROJECT/.codex/skills"
if bash "$MANAGE" uninstall "$SYMLINK_PROJECT" >/dev/null 2>&1; then
  fail "uninstall rejects a symlinked skill target"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: uninstall rejects a symlinked skill target"
fi
assert_file "$SYMLINK_OUTSIDE/KEEP" "symlink rejection preserves external content"

MANAGE_CURSOR_ESCAPE="$TMP/manage-cursor-ancestor-escape"
MANAGE_CURSOR_OUTSIDE="$TMP/manage-cursor-ancestor-outside"
mkdir -p "$MANAGE_CURSOR_ESCAPE/.agent" "$MANAGE_CURSOR_OUTSIDE"
printf '%s\n' '## skill-commons bootstrap' '- platforms: cursor' '- delivery_mode: personal' > "$MANAGE_CURSOR_ESCAPE/.agent/project-manifest.md"
ln -s "$MANAGE_CURSOR_OUTSIDE" "$MANAGE_CURSOR_ESCAPE/.cursor"
set +e
manage_cursor_output="$(bash "$MANAGE" doctor "$MANAGE_CURSOR_ESCAPE" 2>&1)"
manage_cursor_rc=$?
set -e
assert_neq "0" "$manage_cursor_rc" "manage rejects a symlinked adapter ancestor"
assert_contains "$manage_cursor_output" "ancestor is a symlink" "manage ancestor error is actionable"
assert_missing "$MANAGE_CURSOR_OUTSIDE/rules/skill-commons.mdc" "manage ancestor rejection writes nothing outside"

SPACED="$TMP/project with spaces"
new_project "$SPACED" codex
mkdir -p "$SPACED/.codex/skills/foreign-skill"
printf 'foreign\n' > "$SPACED/.codex/skills/foreign-skill/KEEP"
bash "$MANAGE" uninstall "$SPACED" >/dev/null
assert_file "$SPACED/.codex/skills/foreign-skill/KEEP" "uninstall handles spaces without deleting foreign content"
assert_missing "$SPACED/.codex/skills/.skill-commons-ownership-v1" "spaced-path uninstall removes only its ledger"

# Cursor has managed shims/rules but no generated skill target or ownership
# ledger. Empty target sets must remain valid on the Bash 3.2 shipped by macOS.
CURSOR_ONLY="$TMP/cursor-only"
mkdir -p "$CURSOR_ONLY"
printf 'KEEP CURSOR AGENTS\n' > "$CURSOR_ONLY/AGENTS.md"
new_project "$CURSOR_ONLY" cursor
if bash "$MANAGE" doctor "$CURSOR_ONLY" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor supports Cursor-only installations"
else
  fail "doctor supports Cursor-only installations"
fi
mkdir -p "$CURSOR_ONLY/.cursor/rules"
printf 'foreign cursor rule\n' > "$CURSOR_ONLY/.cursor/rules/foreign.mdc"
bash "$MANAGE" uninstall "$CURSOR_ONLY" >/dev/null
assert_contains "$(cat "$CURSOR_ONLY/AGENTS.md")" "KEEP CURSOR AGENTS" "Cursor-only uninstall preserves foreign AGENTS content"
assert_not_contains "$(cat "$CURSOR_ONLY/AGENTS.md")" "skill-commons:start" "Cursor-only uninstall removes its managed AGENTS block"
assert_file "$CURSOR_ONLY/.cursor/rules/foreign.mdc" "Cursor-only uninstall preserves foreign rules"
assert_missing "$CURSOR_ONLY/.cursor/rules/skill-commons.mdc" "Cursor-only uninstall removes its managed rule"

CUSTOM_SUBMODULE="$TMP/custom-submodule"
mkdir -p "$CUSTOM_SUBMODULE/.agent"
printf '%s\n' \
  '## skill-commons bootstrap' \
  '- platforms: claude-code' \
  '- delivery_mode: personal' \
  '- submodule_path: .vendor/skill commons' > "$CUSTOM_SUBMODULE/.agent/project-manifest.md"
bash "$REPO/bootstrap/onboard.sh" "$CUSTOM_SUBMODULE" >/dev/null
if bash "$MANAGE" doctor "$CUSTOM_SUBMODULE" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: doctor recognizes a custom submodule hook path"
else
  fail "doctor recognizes a custom submodule hook path"
fi
bash "$MANAGE" uninstall "$CUSTOM_SUBMODULE" >/dev/null
assert_not_contains "$(cat "$CUSTOM_SUBMODULE/.claude/settings.json")" "bootstrap/check.sh" "uninstall removes the custom-path managed hook"

# A project-wide install lock serializes shim and skill publication together.
# Pause update deterministically inside jq after it owns the lock, then prove a
# competing uninstall loses without changing one byte of the project.
CONTENTION="$TMP/contention"
new_project "$CONTENTION" claude-code

# Lock identity must not depend on each caller's TMPDIR; desktop agents and
# terminal processes can legitimately have different temp environments.
mkdir -p "$TMP/lock-root-a" "$TMP/lock-root-b"
lock_path_a="$(TMPDIR="$TMP/lock-root-a" project_install_lock_path "$CONTENTION")"
lock_path_b="$(TMPDIR="$TMP/lock-root-b" project_install_lock_path "$CONTENTION")"
assert_eq "$lock_path_a" "$lock_path_b" "project install lock identity is independent of TMPDIR"

FAKE_BIN="$TMP/fake-bin"
READY="$TMP/update-lock-ready"
RELEASE_FIFO="$TMP/update-lock-release"
UPDATE_OUT="$TMP/update.out"
mkdir -p "$FAKE_BIN"
mkfifo "$RELEASE_FIFO"
REAL_JQ="$(command -v jq)"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -eu' \
  'if [ ! -e "$LOCK_TEST_READY" ]; then' \
  '  : > "$LOCK_TEST_READY"' \
  '  IFS= read -r release < "$LOCK_TEST_RELEASE_FIFO"' \
  'fi' \
  'exec "$LOCK_TEST_REAL_JQ" "$@"' > "$FAKE_BIN/jq"
chmod +x "$FAKE_BIN/jq"
env \
  PATH="$FAKE_BIN:$PATH" \
  LOCK_TEST_READY="$READY" \
  LOCK_TEST_RELEASE_FIFO="$RELEASE_FIFO" \
  LOCK_TEST_REAL_JQ="$REAL_JQ" \
  bash "$MANAGE" update "$CONTENTION" > "$UPDATE_OUT" 2>&1 &
update_pid=$!
for wait_step in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$READY" ] && break
  kill -0 "$update_pid" 2>/dev/null || break
  sleep 0.1
done
if [ -f "$READY" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: background update reaches the deterministic lock hold point"
  before_loser="$(tree_digest "$CONTENTION")"
  set +e
  loser_output="$(bash "$MANAGE" uninstall "$CONTENTION" 2>&1)"
  loser_rc=$?
  set -e
  assert_neq "0" "$loser_rc" "uninstall loses update-vs-uninstall lock contention"
  assert_contains "$loser_output" "installation is locked" "contention loser reports the project install lock"
  assert_eq "$before_loser" "$(tree_digest "$CONTENTION")" "contention loser makes no project mutation"

  # A failed contender must not remove the winner's lock from its EXIT trap.
  # A third mutator must still lose while the original update is paused.
  before_third="$(tree_digest "$CONTENTION")"
  set +e
  third_output="$(bash "$MANAGE" uninstall "$CONTENTION" 2>&1)"
  third_rc=$?
  set -e
  assert_neq "0" "$third_rc" "third mutator still loses after a contention loser exits"
  assert_contains "$third_output" "installation is locked" "third mutator still observes the winner lock"
  assert_eq "$before_third" "$(tree_digest "$CONTENTION")" "third mutator makes no project mutation"
  printf 'continue\n' > "$RELEASE_FIFO"
else
  fail "background update reaches the deterministic lock hold point"
fi
set +e
wait "$update_pid"
update_rc=$?
set -e
assert_eq "0" "$update_rc" "background update completes after lock release"
if bash "$MANAGE" doctor "$CONTENTION" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: contended installation remains healthy"
else
  fail "contended installation remains healthy"
fi

finish
