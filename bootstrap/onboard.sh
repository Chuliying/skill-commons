#!/usr/bin/env bash
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

. "$HERE/lib/stamp.sh"
. "$HERE/lib/render.sh"
. "$HERE/lib/manifest.sh"
. "$HERE/lib/ownership.sh"

PROJECT_ROOT="${1:-$(pwd)}"
if [ -e "$PROJECT_ROOT" ] && [ ! -d "$PROJECT_ROOT" ]; then
  echo "ERROR: project root is not a directory: $PROJECT_ROOT" >&2
  exit 1
fi
if [ -d "$PROJECT_ROOT" ]; then
  [ ! -L "$PROJECT_ROOT" ] || { error "project root is a symlink: $PROJECT_ROOT"; exit 1; }
  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
else
  PROJECT_ROOT="$(canonical_candidate_path "$PROJECT_ROOT")" || exit 1
fi
PROJECT_ROOT_GUARD="$PROJECT_ROOT"
validate_project_managed_ancestors "$PROJECT_ROOT" || exit 1

# One installation lock spans skeleton validation, shim/hook/rule publication,
# and generated-skill ledger publication. manage.sh update execs this process
# without taking the lock itself, so delegation cannot self-deadlock.
INSTALL_LOCK_DIR="$(project_install_lock_path "$PROJECT_ROOT")"
if ! mkdir "$INSTALL_LOCK_DIR" 2>/dev/null; then
  error "project installation is locked: $PROJECT_ROOT ($INSTALL_LOCK_DIR)"
  exit 1
fi
printf '%s\n' "$$" > "$INSTALL_LOCK_DIR/pid"
blockfile=""
cleanup() {
  [ -z "$blockfile" ] || rm -f -- "$blockfile" || true
  rm -rf -- "$INSTALL_LOCK_DIR" || true
}
trap cleanup EXIT

mkdir -p "$PROJECT_ROOT"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
DIRECTIVE="$HERE/directive.md"
MANIFEST="$PROJECT_ROOT/.agent/project-manifest.md"
SKELETONS="$HERE/../shared-skill-onboarder/templates"

_ensure_router_prerequisite() {
  local source="$1" target="$2"
  # Existing regular files are user-owned. Symlinks and other objects are not
  # safe prerequisite targets because reads/writes could escape the project.
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "ERROR: router prerequisite is not a readable file: $target" >&2
    return 1
  fi
  if [ ! -f "$source" ]; then
    echo "ERROR: onboarding skeleton missing: $source" >&2
    return 1
  fi
  local tmp
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "$target.skill-commons.XXXXXX")" || return 1
  cp "$source" "$tmp" || { rm -f -- "$tmp"; return 1; }
  atomic_publish_file "$tmp" "$target" || { rm -f -- "$tmp"; return 1; }
}

_ensure_router_prerequisite \
  "$SKELETONS/project-manifest.md" \
  "$MANIFEST"
validate_bootstrap_manifest_keys "$MANIFEST" || exit 1

stamp="$(compute_stamp "$DIRECTIVE")"
platforms="$(get_explicit_platforms "$MANIFEST")"
subpath="$(get_submodule_path "$MANIFEST")"
legacy_profile="$(get_profile "$MANIFEST")"
delivery_mode="$(get_delivery_mode "$MANIFEST")"
capability_packs="$(get_capability_packs "$MANIFEST")"

# Refuse ambiguous or implicit consuming selections before guardrail, shim, or
# generated-skill publication. The fresh skeleton already has explicit values.
validate_platform_selection "$platforms" || exit 1
validate_profile_selection "$legacy_profile" "$delivery_mode" "$capability_packs" || exit 1
validate_submodule_path "$subpath" "$PROJECT_ROOT" || exit 1
validate_project_managed_ancestors "$PROJECT_ROOT" "$platforms" || exit 1
reject_deselected_managed_adapters "$PROJECT_ROOT" "$platforms" || exit 1

_render_cc_hook_settings() {
  # $1 = existing settings candidate, $2 = rendered output outside the project
  local settings="$1" output="$2"
  if [ -e "$settings" ] || [ -L "$settings" ]; then
    [ -f "$settings" ] && [ ! -L "$settings" ] || {
      echo "ERROR: Claude settings are not a regular file: $settings" >&2
      return 1
    }
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to manage $settings (install jq, then rerun onboard.sh)" >&2
    return 1
  fi
  # subpath comes from project-manifest.md's `submodule_path:` (untrusted config, not
  # code) but is spliced into a command string persisted as a SessionStart hook -- %q
  # it so injected shell metacharacters (`; rm -rf ~` etc.) can't escape the argument.
  local safe_subpath legacy_cmd cmd hook_suffix marker ambiguous_count
  printf -v safe_subpath '%q' "$subpath"
  legacy_cmd="bash ${safe_subpath}/bootstrap/check.sh --platform claude-code --project-root \"\$CLAUDE_PROJECT_DIR\""
  marker=' # skill-commons-managed'
  cmd="$legacy_cmd$marker"
  hook_suffix='/bootstrap/check.sh --platform claude-code --project-root "$CLAUDE_PROJECT_DIR"'
  if [ -f "$settings" ]; then
    ambiguous_count="$(jq --arg cmd "$cmd" --arg legacy_cmd "$legacy_cmd" --arg hook_suffix "$hook_suffix" --arg marker "$marker" '
      [ .hooks.SessionStart[]?.hooks[]?
        | (.command // "")
        | select(startswith("bash ") and endswith($hook_suffix))
        | select(. != $legacy_cmd and . != $cmd and (endswith($marker) | not))
      ] | length
    ' "$settings")" || return 1
    if [ "$ambiguous_count" != 0 ]; then
      echo "ERROR: ambiguous unmarked bootstrap/check.sh hook; review it before onboarding: $settings" >&2
      return 1
    fi
    jq --arg cmd "$cmd" --arg legacy_cmd "$legacy_cmd" --arg hook_suffix "$hook_suffix" --arg marker "$marker" '
    def is_skill_commons_hook:
      ((.command // "") == $cmd)
      or ((.command // "") == $legacy_cmd)
      or (
        ((.command // "") | startswith("bash "))
        and ((.command // "") | endswith($marker))
        and ((.command // "") | contains($hook_suffix))
      );
    .hooks = (.hooks // {})
    | .hooks.SessionStart = (
        [ (.hooks.SessionStart // [])[]
          | .hooks = [
              (.hooks // [])[]
              | select(is_skill_commons_hook | not)
            ]
          | select((.hooks | length) > 0)
        ]
        + [ { matcher: "startup|clear|compact",
              hooks: [ { type: "command", command: $cmd, async: false } ] } ]
      )
  ' "$settings" > "$output" || return 1
  else
    printf '{}\n' | jq --arg cmd "$cmd" '
      .hooks = (.hooks // {})
      | .hooks.SessionStart = [
          { matcher: "startup|clear|compact",
            hooks: [ { type: "command", command: $cmd, async: false } ] }
        ]
    ' > "$output" || return 1
  fi
  jq -e . "$output" >/dev/null
}

_preflight_cc_hook() {
  local settings="$1" rendered
  rendered="$(mktemp)" || return 1
  _render_cc_hook_settings "$settings" "$rendered" || { rm -f -- "$rendered"; return 1; }
  rm -f -- "$rendered"
}

_merge_cc_hook() {
  local settings="$1" tmp
  mkdir -p "$(dirname "$settings")"
  tmp="$(mktemp "$settings.skill-commons.XXXXXX")" || return 1
  _render_cc_hook_settings "$settings" "$tmp" || { rm -f -- "$tmp"; return 1; }
  atomic_publish_file "$tmp" "$settings" || { rm -f -- "$tmp"; return 1; }
}

_preflight_shim_candidate() {
  local file="$1"
  if [ -e "$file" ] || [ -L "$file" ]; then
    [ -f "$file" ] && [ ! -L "$file" ] || {
      error "managed shim is not a regular file: $file"
      return 1
    }
  fi
  if [ -f "$file" ] && { grep -qF "$AP_START" "$file" || grep -qF "$AP_END" "$file"; }; then
    validate_managed_block "$file" || {
      error "managed shim block is malformed: $file"
      return 1
    }
  fi
}

_preflight_router_prerequisite() {
  local source="$1" target="$2"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    error "router prerequisite is not a readable file: $target"
    return 1
  fi
  [ -f "$source" ] || {
    error "onboarding skeleton missing: $source"
    return 1
  }
}

_validate_cursor_rule_candidate() {
  local rule="$1"
  if [ -e "$rule" ] || [ -L "$rule" ]; then
    [ -f "$rule" ] && [ ! -L "$rule" ] || {
      error "Cursor rule is not a regular file: $rule"
      return 1
    }
    cursor_rule_is_managed "$rule" || {
      error "refusing to replace an unowned Cursor rule: $rule"
      return 1
    }
  fi
}

_preflight_cursor_rule() {
  local rule="$PROJECT_ROOT/.cursor/rules/skill-commons.mdc" rendered
  _validate_cursor_rule_candidate "$rule" || return 1
  rendered="$(mktemp)" || return 1
  render_cursor_rule "$DIRECTIVE" "$stamp" > "$rendered" || { rm -f -- "$rendered"; return 1; }
  grep -Fq 'alwaysApply: true' "$rendered" && grep -Fq "skill-commons-stamp: $stamp" "$rendered" || {
    error "staged Cursor rule is malformed: $rule"
    rm -f -- "$rendered"
    return 1
  }
  rm -f -- "$rendered"
}

_publish_cursor_rule() {
  local rule="$PROJECT_ROOT/.cursor/rules/skill-commons.mdc" tmp
  mkdir -p "$(dirname "$rule")"
  _validate_cursor_rule_candidate "$rule" || return 1
  tmp="$(mktemp "$rule.skill-commons.XXXXXX")" || return 1
  render_cursor_rule "$DIRECTIVE" "$stamp" > "$tmp" || { rm -f -- "$tmp"; return 1; }
  grep -Fq 'alwaysApply: true' "$tmp" && grep -Fq "skill-commons-stamp: $stamp" "$tmp" || {
    echo "ERROR: staged Cursor rule is malformed: $rule" >&2
    rm -f -- "$tmp"
    return 1
  }
  atomic_publish_file "$tmp" "$rule" || { rm -f -- "$tmp"; return 1; }
}

# Build generation targets before project publication so the generator can run
# its real discovery/ledger/collision preflight as part of this installation.
gen_targets=()
case " $platforms " in *" claude-code "*) gen_targets+=("$PROJECT_ROOT/.claude/skills");; esac
case " $platforms " in *" codex "*) gen_targets+=("$PROJECT_ROOT/.codex/skills");; esac

_run_generation() {
  local preflight_only="$1"
  SKILLS_SRC="$(cd "$HERE/.." && pwd)" \
    SKILL_COMMONS_PROJECT_ROOT="$PROJECT_ROOT" \
    SKILL_COMMONS_PREFLIGHT_ONLY="$preflight_only" \
    PROFILE="$legacy_profile" \
    DELIVERY_MODE="$delivery_mode" \
    CAPABILITY_PACKS="$capability_packs" \
    bash "$HERE/generate.sh" "${gen_targets[@]}"
}

# Validate every selected adapter and dependency before publishing guardrails,
# shims, rules, hooks, or generated skills. Publication repeats local checks so
# a non-cooperating external edit still fails closed.
blockfile="$(mktemp)"
render_block "$DIRECTIVE" "$stamp" > "$blockfile"
if platform_is_selected "$platforms" codex || platform_is_selected "$platforms" cursor; then
  _preflight_shim_candidate "$PROJECT_ROOT/AGENTS.md" || exit 1
fi
if platform_is_selected "$platforms" claude-code; then
  _preflight_shim_candidate "$PROJECT_ROOT/CLAUDE.md" || exit 1
  _preflight_cc_hook "$PROJECT_ROOT/.claude/settings.json" || exit 1
fi
if platform_is_selected "$platforms" cursor; then
  _preflight_cursor_rule || exit 1
fi
_preflight_router_prerequisite \
  "$SKELETONS/guardrails.md" \
  "$PROJECT_ROOT/.agent/guardrails.md" || exit 1
# Content safety is insufficient when a later atomic publication cannot create
# its temp file. Probe every selected adapter destination before the first shim,
# guardrail, rule, hook, or generated skill is published.
preflight_writable_file_parent "$PROJECT_ROOT/.agent/guardrails.md" "guardrail destination" || exit 1
if platform_is_selected "$platforms" codex || platform_is_selected "$platforms" cursor; then
  preflight_writable_file_parent "$PROJECT_ROOT/AGENTS.md" "AGENTS shim destination" || exit 1
fi
if platform_is_selected "$platforms" claude-code; then
  preflight_writable_file_parent "$PROJECT_ROOT/CLAUDE.md" "CLAUDE shim destination" || exit 1
  preflight_writable_file_parent "$PROJECT_ROOT/.claude/settings.json" "Claude settings destination" || exit 1
fi
if platform_is_selected "$platforms" cursor; then
  preflight_writable_file_parent "$PROJECT_ROOT/.cursor/rules/skill-commons.mdc" "Cursor rule destination" || exit 1
fi
if [ "${#gen_targets[@]}" -gt 0 ]; then
  [ -f "$HERE/generate.sh" ] || { error "skill generator is missing: $HERE/generate.sh"; exit 1; }
  _run_generation 1 >/dev/null || exit 1
fi

_ensure_router_prerequisite \
  "$SKELETONS/guardrails.md" \
  "$PROJECT_ROOT/.agent/guardrails.md"

for p in $platforms; do
  case "$p" in
    codex)
      upsert_block "$PROJECT_ROOT/AGENTS.md" "$blockfile"
      ;;
    cursor)
      upsert_block "$PROJECT_ROOT/AGENTS.md" "$blockfile"
      _publish_cursor_rule
      ;;
    claude-code)
      upsert_block "$PROJECT_ROOT/CLAUDE.md" "$blockfile"
      _merge_cc_hook "$PROJECT_ROOT/.claude/settings.json"
      ;;
    *)
      error "validated platform dispatch is incomplete: $p"
      exit 1
      ;;
  esac
done

# Fan _shared skills into enabled agent dirs after every selected adapter and
# the same generator path have passed preflight.
if [ "${#gen_targets[@]}" -gt 0 ]; then
  # A shim without generated skills gives users a false-successful onboarding:
  # the agent loads instructions, but `/skill-name` cannot resolve.
  _run_generation 0
fi

if [ -n "$legacy_profile" ]; then
  selection="legacy-profile=$legacy_profile"
else
  selection="delivery-mode=${delivery_mode:-missing}; capability-packs=${capability_packs:-none}"
fi
echo "onboard complete (stamp=$stamp; platforms=$platforms; submodule=$subpath; $selection)"
