#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/stamp.sh"
. "$HERE/lib/render.sh"
. "$HERE/lib/manifest.sh"

PROJECT_ROOT="${1:-$(pwd)}"
DIRECTIVE="$HERE/directive.md"
MANIFEST="$PROJECT_ROOT/.agent/project-manifest.md"
SKELETONS="$HERE/../shared-skill-onboarder/templates"

_ensure_router_prerequisite() {
  local source="$1" target="$2"
  # A regular file (including a symlink that resolves to one) is user-owned.
  # Other existing objects are unsafe to replace and cannot satisfy router.
  if [ -f "$target" ]; then
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
  mkdir -p "$(dirname "$target")"
  cp "$source" "$target"
}

_ensure_router_prerequisite \
  "$SKELETONS/project-manifest.md" \
  "$MANIFEST"
_ensure_router_prerequisite \
  "$SKELETONS/guardrails.md" \
  "$PROJECT_ROOT/.agent/guardrails.md"

stamp="$(compute_stamp "$DIRECTIVE")"
platforms="$(get_platforms "$MANIFEST")"
subpath="$(get_submodule_path "$MANIFEST")"
profile="$(get_profile "$MANIFEST")"

blockfile="$(mktemp)"
trap 'rm -f "$blockfile"' EXIT
render_block "$DIRECTIVE" "$stamp" > "$blockfile"

_merge_cc_hook() {
  local settings="$1"
  mkdir -p "$(dirname "$settings")"
  [ -f "$settings" ] || printf '{}\n' > "$settings"
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to manage $settings (install jq, then rerun onboard.sh)" >&2
    return 1
  fi
  # subpath comes from project-manifest.md's `submodule_path:` (untrusted config, not
  # code) but is spliced into a command string persisted as a SessionStart hook -- %q
  # it so injected shell metacharacters (`; rm -rf ~` etc.) can't escape the argument.
  local safe_subpath cmd
  printf -v safe_subpath '%q' "$subpath"
  cmd="bash ${safe_subpath}/bootstrap/check.sh --platform claude-code --project-root \"\$CLAUDE_PROJECT_DIR\""
  local tmp; tmp="$(mktemp)"
  jq --arg cmd "$cmd" '
    .hooks = (.hooks // {})
    | .hooks.SessionStart = (
        [ (.hooks.SessionStart // [])[]
          | select( any(.hooks[]?; (.command // "") | test("_shared/bootstrap/check\\.sh")) | not ) ]
        + [ { matcher: "startup|clear|compact",
              hooks: [ { type: "command", command: $cmd, async: false } ] } ]
      )
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

for p in $platforms; do
  case "$p" in
    codex)
      upsert_block "$PROJECT_ROOT/AGENTS.md" "$blockfile"
      ;;
    cursor)
      upsert_block "$PROJECT_ROOT/AGENTS.md" "$blockfile"
      mkdir -p "$PROJECT_ROOT/.cursor/rules"
      render_cursor_rule "$DIRECTIVE" "$stamp" > "$PROJECT_ROOT/.cursor/rules/skill-commons.mdc"
      ;;
    claude-code)
      upsert_block "$PROJECT_ROOT/CLAUDE.md" "$blockfile"
      _merge_cc_hook "$PROJECT_ROOT/.claude/settings.json"
      ;;
    *)
      echo "WARN: unknown platform '$p' (skipped)" >&2
      ;;
  esac
done

# Fan _shared skills into the consuming repo's agent dirs so they are /-triggerable.
gen_targets=""
case " $platforms " in *" claude-code "*) gen_targets="$gen_targets $PROJECT_ROOT/.claude/skills";; esac
case " $platforms " in *" codex "*) gen_targets="$gen_targets $PROJECT_ROOT/.codex/skills";; esac
if [ -n "$gen_targets" ] && [ -f "$HERE/generate.sh" ]; then
  # A shim without generated skills gives users a false-successful onboarding:
  # the agent loads instructions, but `/skill-name` cannot resolve.
  SKILLS_SRC="$(cd "$HERE/.." && pwd)" PROFILE="$profile" bash "$HERE/generate.sh" $gen_targets
fi

echo "onboard complete (stamp=$stamp; platforms=$platforms; submodule=$subpath; profile=${profile:-all})"
