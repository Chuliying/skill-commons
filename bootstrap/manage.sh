#!/usr/bin/env bash
# Small management surface for an existing consuming installation.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd -P)"
OWNERSHIP_FILE=".skill-commons-ownership-v1"
OWNERSHIP_HEADER="skill-commons-ownership-v1"
PROJECT_ROOT_GUARD=""

error() {
  echo "ERROR: $*" >&2
  return 1
}

. "$HERE/lib/manifest.sh"
. "$HERE/lib/ownership.sh"
. "$HERE/lib/render.sh"
. "$HERE/lib/stamp.sh"

usage() {
  echo "usage: bootstrap/manage.sh doctor|update|uninstall [project-root]" >&2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage; exit 2; }
COMMAND="$1"
case "$COMMAND" in doctor|update|uninstall) ;; *) usage; exit 2 ;; esac
PROJECT_ROOT="${2:-$(pwd)}"
[ -d "$PROJECT_ROOT" ] && [ ! -L "$PROJECT_ROOT" ] || { error "project root is missing or a symlink: $PROJECT_ROOT"; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
PROJECT_ROOT_GUARD="$PROJECT_ROOT"
validate_project_managed_ancestors "$PROJECT_ROOT" || exit 1
MANIFEST="$PROJECT_ROOT/.agent/project-manifest.md"
[ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || { error "project manifest is missing or unsafe: $MANIFEST"; exit 1; }
validate_bootstrap_manifest_keys "$MANIFEST" || exit 1

PLATFORMS="$(get_explicit_platforms "$MANIFEST")"
LEGACY_PROFILE="$(get_profile "$MANIFEST")"
DELIVERY_MODE_VALUE="$(get_delivery_mode "$MANIFEST")"
CAPABILITY_PACKS_VALUE="$(get_capability_packs "$MANIFEST")"
SUBMODULE_PATH="$(get_submodule_path "$MANIFEST")"
validate_platform_selection "$PLATFORMS" || exit 1
validate_profile_selection "$LEGACY_PROFILE" "$DELIVERY_MODE_VALUE" "$CAPABILITY_PACKS_VALUE" || exit 1
validate_submodule_path "$SUBMODULE_PATH" "$PROJECT_ROOT" || exit 1
validate_project_managed_ancestors "$PROJECT_ROOT" "$PLATFORMS" || exit 1
reject_deselected_managed_adapters "$PROJECT_ROOT" "$PLATFORMS" || exit 1

printf -v SAFE_SUBMODULE_PATH '%q' "$SUBMODULE_PATH"
LEGACY_CLAUDE_HOOK="bash ${SAFE_SUBMODULE_PATH}/bootstrap/check.sh --platform claude-code --project-root \"\$CLAUDE_PROJECT_DIR\""
MANAGED_CLAUDE_HOOK="$LEGACY_CLAUDE_HOOK # skill-commons-managed"

if [ "$COMMAND" = update ]; then
  # onboard.sh owns the project lock for update. exec avoids a parent-held lock
  # deadlocking its delegated child while still covering every mutation.
  exec bash "$HERE/onboard.sh" "$PROJECT_ROOT"
fi

TEMP_ROOT="$(mktemp -d)"
LOCK_DIRS=()
PROJECT_LOCK_DIR=""
PROJECT_LOCK_HELD=0
cleanup() {
  local lock
  for lock in ${LOCK_DIRS[@]+"${LOCK_DIRS[@]}"}; do rm -rf -- "$lock" || true; done
  [ "$PROJECT_LOCK_HELD" = 0 ] || rm -rf -- "$PROJECT_LOCK_DIR" || true
  rm -rf -- "$TEMP_ROOT" || true
}
trap cleanup EXIT

# doctor stays read-only and lock-free. uninstall owns the project-wide lock
# before taking target-local generate locks, matching onboard's lock order.
if [ "$COMMAND" = uninstall ]; then
  PROJECT_LOCK_DIR="$(project_install_lock_path "$PROJECT_ROOT")"
  if ! mkdir "$PROJECT_LOCK_DIR" 2>/dev/null; then
    error "project installation is locked: $PROJECT_ROOT ($PROJECT_LOCK_DIR)"
    exit 1
  fi
  PROJECT_LOCK_HELD=1
  printf '%s\n' "$$" > "$PROJECT_LOCK_DIR/pid"
fi

has_platform() {
  case " $PLATFORMS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

TARGETS=()
if has_platform claude-code; then TARGETS+=("$PROJECT_ROOT/.claude/skills"); fi
if has_platform codex; then TARGETS+=("$PROJECT_ROOT/.codex/skills"); fi

if [ "${#TARGETS[@]}" -gt 0 ]; then
  for i in "${!TARGETS[@]}"; do
    TARGETS[$i]="$(canonical_candidate_path "${TARGETS[$i]}")" || exit 1
    validate_target_base "${TARGETS[$i]}" || exit 1
  done
fi

resolve_profile() {
  local name="$1" depth="${2:-0}" file="$ROOT/profiles/$1" line
  [ "$depth" -le 3 ] || { error "profile include depth exceeded: $name"; return 1; }
  [ -f "$file" ] || { error "profile file is missing: $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -z "$line" ] && continue
    case "$line" in @*) resolve_profile "${line#@}" $((depth + 1)) ;; *) printf '%s\n' "$line" ;; esac
  done < "$file"
}

if [ -n "$LEGACY_PROFILE" ]; then
  PROFILE_NAMES="$LEGACY_PROFILE"
else
  PROFILE_NAMES="$DELIVERY_MODE_VALUE${CAPABILITY_PACKS_VALUE:+ $CAPABILITY_PACKS_VALUE}"
fi
EXPECTED_SKILLS="$(
  for profile_name in $PROFILE_NAMES; do resolve_profile "$profile_name"; done |
    LC_ALL=C sort -u
)"
EXPECTED_LEDGER="$TEMP_ROOT/expected-ownership-ledger"
write_expected_ownership_ledger "$ROOT" "$EXPECTED_SKILLS" "$EXPECTED_LEDGER" || exit 1

expected_skill() {
  printf '%s\n' "$EXPECTED_SKILLS" | grep -Fqx "$1"
}

preflight_targets() {
  local index=0 target ledger seen normalized kind relative extra source
  for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
    ledger="$target/$OWNERSHIP_FILE"
    seen="$TEMP_ROOT/seen-$index"
    preflight_owned_ledger "$target" "$ledger" "$seen" || return 1
    normalized="$TEMP_ROOT/normalized-ledger-$index"
    {
      printf '%s\n' "$OWNERSHIP_HEADER"
      tail -n +2 "$ledger" | LC_ALL=C sort
    } > "$normalized"
    cmp -s "$EXPECTED_LEDGER" "$normalized" || {
      error "ownership ledger does not match expected installation: $ledger"
      return 1
    }
    while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
      [ -n "${kind:-}${relative:-}" ] || continue
      source="$ROOT/$relative"
      [ -e "$source" ] || { error "owned source no longer exists: $source"; return 1; }
      same_payload "$kind" "$source" "$target/$relative" || {
        error "generated content drift: $target/$relative"
        return 1
      }
      if [ "$kind" = D ] && ! expected_skill "$relative"; then
        error "generated skill does not match manifest selection: $relative"
        return 1
      fi
    done < <(tail -n +2 "$ledger")
    while IFS= read -r relative || [ -n "$relative" ]; do
      [ -n "$relative" ] || continue
      ledger_owns "$ledger" D "$relative" || {
        error "selected skill is missing from ownership ledger: $target/$relative"
        return 1
      }
    done <<< "$EXPECTED_SKILLS"
    index=$((index + 1))
  done
}

current_block() {
  local file="$1" stamp="$2"
  validate_managed_block "$file" || { error "managed shim block is missing or malformed: $file"; return 1; }
  awk -v start="$AP_START" -v end="$AP_END" -v stamp="skill-commons-stamp: $stamp" '
    $0 == start { inside=1 }
    inside && index($0, stamp) { found=1 }
    $0 == end { inside=0 }
    END { exit(found ? 0 : 1) }
  ' "$file" || { error "managed shim drift: $file"; return 1; }
}

validate_cursor_rule() {
  local file="$PROJECT_ROOT/.cursor/rules/skill-commons.mdc" require_current="$1" stamp="$2"
  [ -f "$file" ] && [ ! -L "$file" ] || { error "managed Cursor rule is missing or unsafe: $file"; return 1; }
  cursor_rule_is_managed "$file" || { error "managed Cursor rule marker is missing or malformed: $file"; return 1; }
  if [ "$require_current" = 1 ]; then
    grep -Fq "skill-commons-stamp: $stamp" "$file" || { error "managed Cursor rule drift: $file"; return 1; }
  else
    grep -Eq 'skill-commons-stamp: [a-f0-9]{12}' "$file" || { error "managed Cursor rule ownership marker is missing: $file"; return 1; }
  fi
}

validate_claude_settings() {
  local file="$PROJECT_ROOT/.claude/settings.json"
  command -v jq >/dev/null 2>&1 || { error "jq is required to inspect Claude settings"; return 1; }
  [ -f "$file" ] && [ ! -L "$file" ] || { error "Claude settings are missing or unsafe: $file"; return 1; }
  jq -e --arg command "$MANAGED_CLAUDE_HOOK" --arg legacy "$LEGACY_CLAUDE_HOOK" \
    '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") == $command or (.command // "") == $legacy)] | length == 1' \
    "$file" >/dev/null || { error "managed Claude hook is missing or duplicated: $file"; return 1; }
}

STAMP="$(compute_stamp "$HERE/directive.md")"
preflight_shims() {
  local require_current="$1"
  if has_platform codex || has_platform cursor; then
    if [ "$require_current" = 1 ]; then current_block "$PROJECT_ROOT/AGENTS.md" "$STAMP"
    else validate_managed_block "$PROJECT_ROOT/AGENTS.md" || { error "managed AGENTS block is missing or malformed"; return 1; }
    fi
  fi
  if has_platform claude-code; then
    if [ "$require_current" = 1 ]; then current_block "$PROJECT_ROOT/CLAUDE.md" "$STAMP"
    else validate_managed_block "$PROJECT_ROOT/CLAUDE.md" || { error "managed CLAUDE block is missing or malformed"; return 1; }
    fi
    validate_claude_settings || return 1
  fi
  if has_platform cursor; then validate_cursor_rule "$require_current" "$STAMP" || return 1; fi
}

if [ "$COMMAND" = doctor ]; then
  preflight_targets || exit 1
  preflight_shims 1 || exit 1
  echo "doctor: healthy (platforms=$PLATFORMS; selection=$PROFILE_NAMES)"
  exit 0
fi

# Uninstall is destructive but scoped. Acquire the same locks as generation,
# then preflight every target, ledger, path, shim, rule, and hook before deleting
# the first owned unit.
for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
  lock_dir="$(ownership_lock_path "$target")"
  mkdir "$lock_dir" 2>/dev/null || { error "generation target is locked: $target"; exit 1; }
  printf '%s\n' "$$" > "$lock_dir/pid"
  LOCK_DIRS+=("$lock_dir")
done
preflight_targets || exit 1
preflight_shims 0 || exit 1

for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
  remove_preflighted_owned_units "$target" "$target/$OWNERSHIP_FILE"
done
if has_platform codex || has_platform cursor; then remove_managed_block "$PROJECT_ROOT/AGENTS.md"; fi
if has_platform claude-code; then
  remove_managed_block "$PROJECT_ROOT/CLAUDE.md"
  settings="$PROJECT_ROOT/.claude/settings.json"
  settings_tmp="$(mktemp "$settings.skill-commons.XXXXXX")"
  jq --arg command "$MANAGED_CLAUDE_HOOK" --arg legacy "$LEGACY_CLAUDE_HOOK" '
    .hooks.SessionStart = [
      (.hooks.SessionStart // [])[]
      | .hooks = [(.hooks // [])[] | select((.command // "") != $command and (.command // "") != $legacy)]
      | select((.hooks | length) > 0)
    ]
  ' "$settings" > "$settings_tmp"
  jq -e . "$settings_tmp" >/dev/null
  atomic_publish_file "$settings_tmp" "$settings"
fi
if has_platform cursor; then rm -f -- "$PROJECT_ROOT/.cursor/rules/skill-commons.mdc"; fi

echo "uninstall: removed owned skills and managed platform content; manifest, guardrails, submodule, and foreign content preserved"
