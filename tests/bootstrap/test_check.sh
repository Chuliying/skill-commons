#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"

CHECK="$REPO/bootstrap/check.sh"

tree_digest() {
  python3 - "$1" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted((p for p in root.rglob("*") if p.is_file() and not p.is_symlink()), key=lambda p: p.as_posix()):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"{path.relative_to(root).as_posix()}\t{digest}")
PY
}

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

# A hand-written shim without the managed stamp is not an onboarded consumer.
mkdir -p "$TMP/stampless"
printf '# unrelated project instructions\n' > "$TMP/stampless/AGENTS.md"
out=$(bash "$CHECK" --platform text --project-root "$TMP/stampless")
assert_contains "$out" "managed stamp" "stamp-less consuming shim warns that onboarding is missing"

# The toolkit source owns bootstrap and does not onboard against itself.
out=$(bash "$CHECK" --platform text --project-root "$REPO")
assert_not_contains "$out" "managed stamp" "skill-commons source repo is exempt from missing-stamp warnings"
assert_not_contains "$out" ".agent/skills/_shared" "source directive does not point at a consuming mount"
out=$(bash "$CHECK" --platform cursor --project-root "$REPO")
assert_not_contains "$out" "onboard.sh" "skill-commons source repo is exempt when a platform shim is absent"

# The source repository is also the maintainer's three-root installation. Build
# an isolated source fixture so the advisory can be tested against each drift
# class without mutating the checkout's generated roots.
SOURCE_HEALTH="$TMP/source-health"
mkdir -p "$SOURCE_HEALTH"
cp -R "$REPO/bootstrap" "$SOURCE_HEALTH/bootstrap"
cp -R "$REPO/profiles" "$SOURCE_HEALTH/profiles"
cp -R "$REPO/scripts" "$SOURCE_HEALTH/scripts"
for source_dir in "$REPO"/*; do
  [ -f "$source_dir/SKILL.md" ] || continue
  cp -R "$source_dir" "$SOURCE_HEALTH/$(basename "$source_dir")"
done
for source_file in \
  ARTIFACTS.md GATE-PACKAGE.md graph-context-check.md SOURCES.md \
  CHECKLIST-CONVENTION.md prd-template.md protocol-registry.json profiles.json; do
  cp "$REPO/$source_file" "$SOURCE_HEALTH/$source_file"
done
mkdir -p "$SOURCE_HEALTH/.claude/skills" "$SOURCE_HEALTH/.codex/skills" "$SOURCE_HEALTH/.agents/skills"
PROFILE=all bash "$SOURCE_HEALTH/bootstrap/generate.sh" \
  "$SOURCE_HEALTH/.claude/skills" \
  "$SOURCE_HEALTH/.codex/skills" \
  "$SOURCE_HEALTH/.agents/skills" >/dev/null

health_tree_before="$(tree_digest "$SOURCE_HEALTH")"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check exits zero when clean"
assert_not_contains "$out" "maintainer generated" "clean source health check emits no drift warning"
assert_eq "$health_tree_before" "$(tree_digest "$SOURCE_HEALTH")" \
  "clean source health check is read-only"

# Build artifacts in generated skill directories are outside the managed
# payload, matching the inventory check's __pycache__/pyc exclusions.
mkdir -p "$SOURCE_HEALTH/.codex/skills/skill-router/__pycache__"
printf 'synthetic bytecode\n' > "$SOURCE_HEALTH/.codex/skills/skill-router/__pycache__/fixture.pyc"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check remains clean with generated bytecode"
assert_not_contains "$out" "stale" "source health ignores generated bytecode"

out=$(DELIVERY_MODE=personal CAPABILITY_PACKS=optional \
  SKILL_COMMONS_PROJECT_ROOT="$SOURCE_HEALTH" \
  bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH")
assert_not_contains "$out" "could not build an expected payload" \
  "source health confines inherited generator selection and guard settings"

mv "$SOURCE_HEALTH/bootstrap/generate.sh" "$TMP/source-health-generate.sh"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check remains advisory when its generator is unavailable"
assert_contains "$out" "could not build an expected payload" "source health surfaces generator failure"
mv "$TMP/source-health-generate.sh" "$SOURCE_HEALTH/bootstrap/generate.sh"

health_ledger="$SOURCE_HEALTH/.codex/skills/.skill-commons-ownership-v1"
health_ledger_backup="$TMP/source-health-ledger"
mv "$health_ledger" "$health_ledger_backup"
missing_ledger_retired="$SOURCE_HEALTH/.codex/skills/ponytail"
mkdir -p "$missing_ledger_retired"
printf '%s\n' 'foreign retired fixture' > "$missing_ledger_retired/SKILL.md"
missing_ledger_tree_before="$(tree_digest "$SOURCE_HEALTH")"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check remains advisory with a missing ledger"
assert_contains "$out" "missing ownership ledger" "source health reports a missing ledger"
assert_contains "$out" "SKILL_COMMONS_ADOPT_LEGACY=1" "missing-ledger warning gives the adoption command"
assert_contains "$out" "unowned retired-name collision" "missing ledger classifies retired output as an unowned collision"
assert_contains "$out" "inspect the frozen legacy namespace first" \
  "missing-ledger collision requires legacy namespace inspection"
assert_contains "$out" "consider: SKILL_COMMONS_ADOPT_LEGACY=1" \
  "missing-ledger adoption is conditional"
assert_not_contains "$out" "run: SKILL_COMMONS_ADOPT_LEGACY=1" \
  "missing-ledger collision is not given a direct adoption command"
assert_not_contains "$out" "generate.sh preserves unowned content" \
  "missing-ledger collision does not claim normal generation preserves it"
assert_eq "$missing_ledger_tree_before" "$(tree_digest "$SOURCE_HEALTH")" \
  "missing-ledger collision warning path is read-only"
rm -rf -- "$missing_ledger_retired"
mv "$health_ledger_backup" "$health_ledger"

printf '\nT01 fixture drift\n' >> "$SOURCE_HEALTH/.codex/skills/skill-router/SKILL.md"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check remains advisory with stale content"
assert_contains "$out" "stale" "source health reports stale generated content"
assert_contains "$out" "bootstrap/generate.sh" "stale-content warning gives a repair command"
PROFILE=all bash "$SOURCE_HEALTH/bootstrap/generate.sh" "$SOURCE_HEALTH/.codex/skills" >/dev/null

# A retired path explicitly claimed by the target ledger is an owned residue,
# so it gets the migration warning rather than the foreign-content collision
# warning. The advisory must not mutate either the path or the ledger.
owned_retired="$SOURCE_HEALTH/.codex/skills/ponytail"
mkdir -p "$owned_retired"
printf '%s\n' 'owned retired fixture' > "$owned_retired/SKILL.md"
printf 'D\tponytail\n' >> "$health_ledger"
owned_tree_before="$(tree_digest "$SOURCE_HEALTH")"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check remains advisory with ledger-owned retired output"
assert_contains "$out" "retired owner output" "source health reports ledger-owned retired output"
assert_contains "$out" "ponytail" "owned retired warning names the retired path"
assert_not_contains "$out" "unowned retired-name collision" "owned retired output is not classified as foreign collision"
assert_contains "$out" "run: PROFILE=all bash" "owned retired warning gives a normal repair command"
assert_not_contains "$out" "SKILL_COMMONS_ADOPT_LEGACY=1" \
  "owned retired output does not require legacy adoption"
assert_eq "$owned_tree_before" "$(tree_digest "$SOURCE_HEALTH")" \
  "owned retired warning path is read-only"
rm -rf -- "$owned_retired"
PROFILE=all bash "$SOURCE_HEALTH/bootstrap/generate.sh" "$SOURCE_HEALTH/.codex/skills" >/dev/null

mkdir -p "$SOURCE_HEALTH/.agents/skills/ponytail"
printf '%s\n' 'retired fixture' > "$SOURCE_HEALTH/.agents/skills/ponytail/SKILL.md"
out=$(bash "$SOURCE_HEALTH/bootstrap/check.sh" --platform text --project-root "$SOURCE_HEALTH"); rc=$?
assert_eq "0" "$rc" "source health check remains advisory with retired output"
assert_contains "$out" "retired-name collision" "source health reports an unowned retired-name collision"
assert_contains "$out" "unowned" "source health distinguishes an unowned retired collision"
assert_contains "$out" "preserves unowned content" "retired collision warning preserves foreign-content safety"
assert_contains "$out" "inspect the source first" "valid-ledger collision requires source inspection"
assert_contains "$out" "remove only confirmed obsolete output" \
  "valid-ledger collision limits cleanup to confirmed obsolete output"
assert_contains "$out" "run: PROFILE=all bash" "valid-ledger collision gives a normal repair command"
assert_not_contains "$out" "SKILL_COMMONS_ADOPT_LEGACY=1" \
  "valid-ledger collision does not require legacy adoption"
assert_not_contains "$out" "retired owner output" \
  "foreign collision fixture is isolated from owned retired output"

finish
