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
. "$HERE/lib/fanout.sh"

usage() {
  cat <<'EOF'
usage: bootstrap/onboard.sh [PROJECT_ROOT]

Install the shared skill bundle into a consuming repository. PROJECT_ROOT defaults
to the current directory.

  -h, --help    print this message and exit without touching the filesystem

Environment:
  DELIVERY_MODE      personal (default) | team-sprint
  CAPABILITY_PACKS   space-separated: frontend, optional
EOF
}

# Options are handled BEFORE anything is resolved or created. `--help` was previously
# taken as a positional target: onboard created a directory literally named `--help`,
# fanned skills into it, wrote root files, and reported success. Typing --help at an
# unfamiliar script is the most likely first thing a new consumer does, so answering it
# with a silent real installation is the worst available behavior.
refresh_only=0
if [ "${1:-}" = --refresh-ignored ]; then
  refresh_only=1
  shift
fi
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  -*)
    # Mirrors security/scripts/scan-secrets.sh, which already refuses option-shaped
    # targets. Creating a directory out of a mistyped flag is never the intent.
    echo "ERROR: unsafe target: $1 looks like an option, not a project root" >&2
    echo "       run 'bootstrap/onboard.sh --help' for usage" >&2
    exit 1
    ;;
esac

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
  error "project installation is locked: $PROJECT_ROOT ($INSTALL_LOCK_DIR). If the process in its pid file has exited, remove the stale lock directory and rerun onboarding."
  exit 1
fi
printf '%s\n' "$$" > "$INSTALL_LOCK_DIR/pid"
blockfile=""
pointerfile=""
legacy_lock=""
cleanup() {
  [ -z "$blockfile" ] || rm -f -- "$blockfile" || true
  [ -z "$pointerfile" ] || rm -f -- "$pointerfile" || true
  [ -z "$legacy_lock" ] || rm -rf -- "$legacy_lock" || true
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

if [ "$refresh_only" -eq 1 ]; then
  manifest_rel="${MANIFEST#"$PROJECT_ROOT"/}"
  [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] &&
    git -C "$PROJECT_ROOT" cat-file -e "HEAD:$manifest_rel" 2>/dev/null &&
    git -C "$PROJECT_ROOT" diff --quiet HEAD -- "$manifest_rel" &&
    git -C "$PROJECT_ROOT" diff --cached --quiet HEAD -- "$manifest_rel" || {
      error "project manifest has local changes or is not committed"
      exit 1
    }
fi

manifest_existed=0
[ -e "$MANIFEST" ] && manifest_existed=1
_ensure_router_prerequisite \
  "$SKELETONS/project-manifest.md" \
  "$MANIFEST"
validate_bootstrap_manifest_keys "$MANIFEST" || exit 1

# A new manifest names the agents this repository already uses; the template default
# (Claude Code and Codex) applies only when none is found. An existing manifest is kept.
if [ "$manifest_existed" -eq 0 ]; then
  detected_platforms=""
  { [ -d "$PROJECT_ROOT/.claude" ] || [ -f "$PROJECT_ROOT/CLAUDE.md" ]; } && detected_platforms="claude-code"
  # AGENTS.md alone is a vendor-neutral convention, so it does not mean Codex.
  # `.agents/skills` is a cross-tool convention, so only our own ledger there means Codex.
  { [ -d "$PROJECT_ROOT/.codex" ] || [ -f "$PROJECT_ROOT/.agents/skills/$OWNERSHIP_FILE" ]; } \
    && detected_platforms="${detected_platforms:+$detected_platforms, }codex"
  { [ -d "$PROJECT_ROOT/.cursor" ] || [ -f "$PROJECT_ROOT/.cursorrules" ]; } && detected_platforms="${detected_platforms:+$detected_platforms, }cursor"
  if [ -n "$detected_platforms" ]; then
    platforms_tmp="$(mktemp "$MANIFEST.skill-commons.XXXXXX")" || exit 1
    DETECTED="$detected_platforms" awk '
      /^- platforms: / && !done { print "- platforms: " ENVIRON["DETECTED"]; done = 1; next }
      { print }
    ' "$MANIFEST" > "$platforms_tmp" && atomic_publish_file "$platforms_tmp" "$MANIFEST" || { rm -f -- "$platforms_tmp"; exit 1; }
    echo "platforms found in this repository: $detected_platforms"
  fi
  case " $detected_platforms " in
    *codex*) ;;
    *) [ -n "$detected_platforms" ] && [ -f "$PROJECT_ROOT/AGENTS.md" ] && \
         echo "note: AGENTS.md alone does not select Codex; add codex to '- platforms:' in $MANIFEST and run onboard.sh again if you use it." ;;
  esac
  # The template's note about this replacement has served its purpose.
  note_tmp="$(mktemp "$MANIFEST.skill-commons.XXXXXX")" || exit 1
  grep -v '^<!-- onboard.sh replaces this with the agents it finds' "$MANIFEST" > "$note_tmp"
  atomic_publish_file "$note_tmp" "$MANIFEST" || { rm -f -- "$note_tmp"; exit 1; }
fi

# Verification evidence fingerprints source_roots and tests_root; without them every
# file in the repository counts, so a README edit makes finished work stale. A manifest
# onboarding just created gets derived roots; an existing one stays user-owned.
if [ "$refresh_only" -eq 0 ]; then
  derived_roots="$(derive_scope_roots "$PROJECT_ROOT")"
  derived_src="${derived_roots%%|*}"; derived_tst="${derived_roots#*|}"
  if [ -z "$(_manifest_value "$MANIFEST" source_roots)$(_manifest_value "$MANIFEST" tests_root)" ] \
     && [ -n "$derived_src$derived_tst" ]; then
    derived_lines=""
    [ -n "$derived_src" ] && derived_lines="- source_roots: $derived_src"
    [ -n "$derived_tst" ] && derived_lines="${derived_lines:+$derived_lines
}- tests_root: $derived_tst"
    # Narrowing the scope must not drop code: write roots only when a source root was found
    # and the roots hold at least 90% of tracked code files (a Python package at the root
    # plus tests/ would otherwise verify tests only).
    read -r covered_code all_code <<< "$(scope_coverage "$PROJECT_ROOT" "$derived_src,$derived_tst")"
    roots_complete=0
    if [ -n "$derived_src" ] && [ "${all_code:-0}" -gt 0 ] && [ $((covered_code * 10)) -ge $((all_code * 9)) ]; then
      roots_complete=1
    fi
    if [ "$manifest_existed" -eq 0 ] && [ "$roots_complete" -eq 1 ]; then
      paths_tmp="$(mktemp "$MANIFEST.skill-commons.XXXXXX")" || exit 1
      DERIVED_LINES="$derived_lines" awk '
        /^<!-- TODO: discover and record project document, source, test, and work-item paths\. -->$/ && !done {
          print "<!-- source_roots and tests_root were derived by onboard.sh from top-level directories; check them. -->"
          print ENVIRON["DERIVED_LINES"]; done = 1; next
        }
        { print }
      ' "$MANIFEST" > "$paths_tmp" && atomic_publish_file "$paths_tmp" "$MANIFEST" || { rm -f -- "$paths_tmp"; exit 1; }
      echo "derived from top-level directories and written to $MANIFEST (check them):"
    else
      echo "note: $MANIFEST has no source_roots or tests_root, so verification covers every file."
      [ "$roots_complete" -eq 1 ] || echo "these roots hold ${covered_code:-0} of ${all_code:-0} tracked code files; add the missing directories before using them."
      echo "suggested lines from top-level directories (check them, then add under ## Paths):"
    fi
    printf '%s\n' "$derived_lines"
  fi

  # verify.sh needs a test command; a fresh install had none, so the first verification
  # stopped (competitor test round 2, criterion C). Same ownership rule as the roots.
  derived_test="$(derive_test_cmd "$PROJECT_ROOT")"
  if [ -z "$(_manifest_value "$MANIFEST" test_cmd)" ] && [ -n "$derived_test" ]; then
    if [ "$manifest_existed" -eq 0 ]; then
      stack_tmp="$(mktemp "$MANIFEST.skill-commons.XXXXXX")" || exit 1
      DERIVED_TEST="$derived_test" awk '
        /^<!-- TODO: discover the project.s typecheck, lint, and test commands\. -->$/ && !done {
          print "<!-- test_cmd was derived by onboard.sh from project files; check it. TODO: typecheck and lint commands. -->"
          print "- test_cmd: " ENVIRON["DERIVED_TEST"]; done = 1; next
        }
        { print }
      ' "$MANIFEST" > "$stack_tmp" && atomic_publish_file "$stack_tmp" "$MANIFEST" || { rm -f -- "$stack_tmp"; exit 1; }
      echo "derived test command written to $MANIFEST (check it):"
    else
      echo "note: $MANIFEST has no test_cmd, so verify.sh cannot run tests."
      echo "suggested line from project files (check it, then add under ## Stack):"
    fi
    echo "- test_cmd: $derived_test"
  fi
fi

stamp="$(compute_stamp "$DIRECTIVE")"
platforms="$(get_explicit_platforms "$MANIFEST")"
subpath="$(get_submodule_path "$MANIFEST")"
legacy_profile="$(get_profile "$MANIFEST")"
delivery_mode="$(get_delivery_mode "$MANIFEST")"
capability_packs="$(get_capability_packs "$MANIFEST")"

# Refuse ambiguous or implicit consuming selections before guardrail, shim, or
# generated-skill publication. The fresh skeleton already has explicit values.
report_missing_selection "$MANIFEST" "$platforms" "$legacy_profile" "$delivery_mode" || exit 1
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
  render_cursor_rule "$DIRECTIVE" "$stamp" "$subpath" > "$rendered" || { rm -f -- "$rendered"; return 1; }
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
  render_cursor_rule "$DIRECTIVE" "$stamp" "$subpath" > "$tmp" || { rm -f -- "$tmp"; return 1; }
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
case " $platforms " in *" codex "*) gen_targets+=("$PROJECT_ROOT/.agents/skills");; esac
# Earlier installs wrote Codex copies to .codex/skills. They move to .agents/skills: the
# legacy ledger is preflighted with the rest, and its units are removed only after the new
# copies are published.
legacy_codex=""
legacy_ledger="$PROJECT_ROOT/$FANOUT_LEGACY_CODEX/$OWNERSHIP_FILE"
if platform_is_selected "$platforms" codex && { [ -e "$legacy_ledger" ] || [ -L "$legacy_ledger" ]; }; then
  legacy_codex="$PROJECT_ROOT/$FANOUT_LEGACY_CODEX"
fi

_run_generation() {
  local preflight_only="$1"
  SKILLS_SRC="$ROOT" \
    SKILL_COMMONS_PROJECT_ROOT="$PROJECT_ROOT" \
    SKILL_COMMONS_REFRESH_IGNORED="$refresh_only" \
    SKILL_COMMONS_PREFLIGHT_ONLY="$preflight_only" \
    PROFILE="$legacy_profile" \
    DELIVERY_MODE="$delivery_mode" \
    CAPABILITY_PACKS="$capability_packs" \
    bash "$HERE/generate.sh" "${gen_targets[@]}"
}

publish_fanout_state() {
  local statefile
  statefile="$(mktemp "$PROJECT_ROOT/$FANOUT_STATE.XXXXXX")" || return 1
  fanout_signature "$ROOT" "$stamp" > "$statefile" &&
    atomic_publish_file "$statefile" "$PROJECT_ROOT/$FANOUT_STATE" || {
      rm -f -- "$statefile"
      return 1
    }
}

if [ "$refresh_only" -eq 1 ]; then
  [ "${#gen_targets[@]}" -gt 0 ] || exit 0
  [ -z "$legacy_codex" ] || { error "earlier Codex copies need an explicit migration"; exit 1; }
  validate_ignore_block "$PROJECT_ROOT/.gitignore" || { error "the managed .gitignore block is missing or malformed"; exit 1; }
  validate_fanout_state "$PROJECT_ROOT" || exit 1
  preflight_writable_file_parent "$PROJECT_ROOT/$FANOUT_STATE" "skill copy state destination" || exit 1
  [ "$(cd "$PROJECT_ROOT/$subpath" 2>/dev/null && pwd -P)" = "$ROOT" ] || {
    error "project manifest points to another toolkit mount"
    exit 1
  }
  _run_generation 0
  publish_fanout_state
  exit 0
fi

# Validate every selected adapter and dependency before publishing guardrails,
# shims, rules, hooks, or generated skills. Publication repeats local checks so
# a non-cooperating external edit still fails closed.
blockfile="$(mktemp)"
render_block "$DIRECTIVE" "$stamp" "$subpath" > "$blockfile"
# With AGENTS.md also managed, CLAUDE.md imports it instead of repeating the directive.
pointerfile="$(mktemp)"
render_block "$HERE/directive-pointer.md" "$stamp" > "$pointerfile"
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
  # The generated copies are ignored, not committed (T13): the .gitignore block must be
  # writable and well formed before anything is published.
  if [ -e "$PROJECT_ROOT/.gitignore" ] || [ -L "$PROJECT_ROOT/.gitignore" ]; then
    [ -f "$PROJECT_ROOT/.gitignore" ] && [ ! -L "$PROJECT_ROOT/.gitignore" ] || { error ".gitignore is not a regular file"; exit 1; }
    if grep -qF "$GI_START" "$PROJECT_ROOT/.gitignore" || grep -qF "$GI_END" "$PROJECT_ROOT/.gitignore"; then
      validate_ignore_block "$PROJECT_ROOT/.gitignore" || { error "the skill-commons block in .gitignore is malformed"; exit 1; }
    fi
  fi
  preflight_writable_file_parent "$PROJECT_ROOT/.gitignore" ".gitignore destination" || exit 1
  validate_fanout_state "$PROJECT_ROOT" || exit 1
  preflight_writable_file_parent "$PROJECT_ROOT/$FANOUT_STATE" "skill copy state destination" || exit 1
  if [ -n "$legacy_codex" ]; then
    legacy_lock_candidate="$(ownership_lock_path "$legacy_codex")"
    mkdir "$legacy_lock_candidate" 2>/dev/null || { error "generation target is locked: $legacy_codex"; exit 1; }
    legacy_lock="$legacy_lock_candidate"
    printf '%s\n' "$$" > "$legacy_lock/pid"
    legacy_seen="$(mktemp)"
    preflight_owned_ledger "$legacy_codex" "$legacy_ledger" "$legacy_seen" 1 || { rm -f -- "$legacy_seen"; exit 1; }
    rm -f -- "$legacy_seen"
    validate_fanout_payload "$legacy_codex" "$legacy_ledger" "$ROOT" 1 \
      "$(fanout_previous_revision "$PROJECT_ROOT")" "$(fanout_recorded_revision "$PROJECT_ROOT" "$ROOT")" || exit 1
  fi
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
      case " $platforms " in
        *" codex "*|*" cursor "*) upsert_block "$PROJECT_ROOT/CLAUDE.md" "$pointerfile" ;;
        *) upsert_block "$PROJECT_ROOT/CLAUDE.md" "$blockfile" ;;
      esac
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
  ignorefile="$(mktemp)"
  render_ignore_block "$PROJECT_ROOT" "$platforms" > "$ignorefile"
  upsert_ignore_block "$PROJECT_ROOT/.gitignore" "$ignorefile"
  rm -f -- "$ignorefile"
  if git -C "$PROJECT_ROOT" check-ignore -q .gitignore 2>/dev/null; then
    echo "note: .gitignore is itself ignored (for example by a global excludes file), so teammates would"
    echo "      not get the skill-commons block. Commit it with: git add -f .gitignore"
  fi
  if [ -n "$legacy_codex" ]; then
    legacy_tracked="$(git -C "$PROJECT_ROOT" ls-files -- "$FANOUT_LEGACY_CODEX" 2>/dev/null || true)"
    validate_fanout_payload "$legacy_codex" "$legacy_ledger" "$ROOT" 1 \
      "$(fanout_previous_revision "$PROJECT_ROOT")" "$(fanout_recorded_revision "$PROJECT_ROOT" "$ROOT")" || exit 1
    remove_preflighted_owned_units "$legacy_codex" "$legacy_ledger"
    rmdir "$legacy_codex/scripts" "$legacy_codex" 2>/dev/null || true
    rmdir "$PROJECT_ROOT/.codex" 2>/dev/null || true
    echo "moved the Codex skill copies from $FANOUT_LEGACY_CODEX to .agents/skills (the location Codex documents)"
    [ -z "$legacy_tracked" ] || echo "note: Git tracked the earlier Codex copies; commit their deletion from $FANOUT_LEGACY_CODEX"
  fi
  publish_fanout_state
  tracked="$(fanout_tracked "$PROJECT_ROOT" "$platforms")"
  if [ -n "$tracked" ]; then
    echo "note: the generated skill copies are now ignored, but Git still tracks earlier copies."
    echo "      They are regenerated at session start, so you can stop tracking them (files stay on disk):"
    printf '      git rm -r --cached --'
    while IFS= read -r file; do printf ' %q' "$file"; done <<< "$tracked"
    printf '\n'
  fi
fi

if [ -n "$legacy_profile" ]; then
  selection="legacy-profile=$legacy_profile"
else
  selection="delivery-mode=${delivery_mode:-missing}; capability-packs=${capability_packs:-none}"
fi
echo "onboard complete (stamp=$stamp; platforms=$platforms; submodule=$subpath; $selection)"
