#!/usr/bin/env bash
# Never abort the host session: no -e. Always exit 0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/stamp.sh"
. "$HERE/lib/platform.sh"

OWNERSHIP_FILE=".skill-commons-ownership-v1"
OWNERSHIP_HEADER="skill-commons-ownership-v1"

PLATFORM=""
PROJECT_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --project-root) PROJECT_ROOT="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) shift ;;
  esac
done
[ -z "$PLATFORM" ] && PLATFORM="$(detect_platform)"
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(pwd)"
# Canonicalize: a trailing slash (or symlink/relative form) would otherwise break the
# submodule-path prefix match that substitutes the real mount into the emitted context.
[ -d "$PROJECT_ROOT" ] && PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

DIRECTIVE="${AGENT_DIRECTIVE:-$HERE/directive.md}"

warnings=""
add_warn() { warnings="${warnings}⚠️ $1
"; }

# Check 1: submodule initialized (directive present & non-empty)
if [ ! -s "$DIRECTIVE" ]; then
  add_warn "skill-commons submodule is not initialized; run: git submodule update --init"
  emit "$PLATFORM" "" "$warnings"
  exit 0
fi

stamp="$(compute_stamp "$DIRECTIVE")"

# Shim file inspected for this platform (unknown -> AGENTS.md, the cross-tool file)
case "$PLATFORM" in
  claude-code) shim="$PROJECT_ROOT/CLAUDE.md" ;;
  cursor)      shim="$PROJECT_ROOT/.cursor/rules/skill-commons.mdc" ;;
  *)           shim="$PROJECT_ROOT/AGENTS.md" ;;
esac

toolkit_root="$(cd "$HERE/.." && pwd -P)"
proj_root_abs="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P || printf '%s' "$PROJECT_ROOT")"
is_toolkit_source=0
[ "$proj_root_abs" = "$toolkit_root" ] && is_toolkit_source=1

# The source checkout is the maintainer's own three-root installation. Keep
# this check advisory like the consumer session check, but compare each root to
# a fresh generator payload so missing ledgers, stale bytes, and retired output
# are visible before an agent relies on an old installed copy. The payload is
# built under /tmp and removed before returning; no source or generated file is
# published by this health check.
source_health_action() {
  printf 'PROFILE=all bash %q' "$HERE/generate.sh"
}

source_health_adoption_action() {
  printf 'SKILL_COMMONS_ADOPT_LEGACY=1 PROFILE=all bash %q' "$HERE/generate.sh"
}

source_health_legacy_guidance() {
  printf 'inspect the frozen legacy namespace first; preserve or relocate foreign retired-name collisions outside frozen legacy paths or handle them separately, then consider: %s' "$(source_health_adoption_action)"
}

source_health_check() {
  local health_tmp expected expected_ledger target label kind relative extra
  local stale_count stale_paths retired_count retired_paths retired suffix action
  local ledger_file ledger_safe ledger_warning repair

  action="$(source_health_action)"
  health_tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-commons-health.XXXXXX" 2>/dev/null)" || {
    add_warn "maintainer source health check could not create a temporary payload; run: $action"
    return 0
  }
  expected="$health_tmp/generated"
  if ! SKILLS_SRC="$toolkit_root" PROFILE=all DELIVERY_MODE= CAPABILITY_PACKS= \
    SKILL_COMMONS_PROJECT_ROOT= SKILL_COMMONS_ADOPT_LEGACY=0 SKILL_COMMONS_PREFLIGHT_ONLY=0 \
    bash "$HERE/generate.sh" "$expected" >/dev/null 2>&1; then
    add_warn "maintainer source health check could not build an expected payload; run: $action"
    rm -rf -- "$health_tmp"
    return 0
  fi
  expected_ledger="$expected/$OWNERSHIP_FILE"

  # These are the historical generated names that the current source no
  # longer owns. Keep the list bounded to retired units; unknown foreign
  # entries remain valid shared-root content and are intentionally ignored.
  for target in \
    "$toolkit_root/.claude/skills" \
    "$toolkit_root/.codex/skills" \
    "$toolkit_root/.agents/skills"; do
    label="${target#"$toolkit_root/"}"
    if [ -L "$target" ] || [ ! -d "$target" ]; then
      add_warn "maintainer generated root is missing or unsafe: $label; run: $action"
      continue
    fi

    ledger_file="$target/$OWNERSHIP_FILE"
    ledger_safe=0
    ledger_warning=""
    if [ -L "$ledger_file" ] || { [ -e "$ledger_file" ] && [ ! -f "$ledger_file" ]; }; then
      ledger_warning="maintainer generated ownership ledger is unsafe: $label/$OWNERSHIP_FILE"
    elif [ ! -f "$ledger_file" ]; then
      ledger_warning="maintainer generated root missing ownership ledger: $label/$OWNERSHIP_FILE"
    elif [ "$(head -n 1 "$ledger_file" 2>/dev/null)" != "$OWNERSHIP_HEADER" ]; then
      ledger_warning="maintainer generated ownership ledger is unsafe: $label/$OWNERSHIP_FILE"
    else
      ledger_safe=1
      if ! cmp -s "$expected_ledger" "$ledger_file"; then
        ledger_warning="maintainer generated ownership ledger is stale: $label/$OWNERSHIP_FILE"
      fi
    fi
    if [ "$ledger_safe" -eq 1 ]; then
      repair="run: $action"
    else
      repair="$(source_health_legacy_guidance)"
    fi
    [ -z "$ledger_warning" ] || add_warn "$ledger_warning; $repair"

    stale_count=0
    stale_paths=""
    while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
      [ -n "${kind:-}${relative:-}" ] || continue
      if [ ! -e "$target/$relative" ] && [ ! -L "$target/$relative" ]; then
        stale_count=$((stale_count + 1))
        [ "$stale_count" -le 4 ] && stale_paths="${stale_paths}${stale_paths:+, }$relative"
        continue
      fi
      case "$kind" in
        D)
          if [ -L "$target/$relative" ] || [ ! -d "$target/$relative" ] || \
             ! diff -qr -x '__pycache__' -x '*.pyc' -x '.DS_Store' \
               "$expected/$relative" "$target/$relative" >/dev/null 2>&1; then
            stale_count=$((stale_count + 1))
            [ "$stale_count" -le 4 ] && stale_paths="${stale_paths}${stale_paths:+, }$relative"
          fi
          ;;
        F)
          if [ -L "$target/$relative" ] || [ ! -f "$target/$relative" ] || \
             ! cmp -s "$expected/$relative" "$target/$relative"; then
            stale_count=$((stale_count + 1))
            [ "$stale_count" -le 4 ] && stale_paths="${stale_paths}${stale_paths:+, }$relative"
          fi
          ;;
      esac
    done < <(tail -n +2 "$expected_ledger")
    if [ "$stale_count" -gt 0 ]; then
      suffix="$stale_paths"
      [ "$stale_count" -gt 4 ] && suffix="$suffix (+$((stale_count - 4)) more)"
      add_warn "maintainer generated content is stale in $label: $suffix; $repair"
    fi

    retired_count=0
    retired_paths=""
    retired_unowned_count=0
    retired_unowned_paths=""
    legacy_names="$(awk '
      /^LEGACY_PRE_LEDGER_DIRS=\(/ { inside=1; next }
      inside && /^\)/ { exit }
      inside { print }
    ' "$HERE/generate.sh")"
    for retired in $legacy_names; do
      # A name still present in the source is active, except skill-creator,
      # which is a maintainer-only source tool intentionally excluded by the
      # generator.
      if [ "$retired" != "skill-creator" ] && [ -f "$toolkit_root/$retired/SKILL.md" ]; then
        continue
      fi
      if [ -e "$target/$retired" ] || [ -L "$target/$retired" ]; then
        retired_count=$((retired_count + 1))
        [ "$retired_count" -le 4 ] && retired_paths="${retired_paths}${retired_paths:+, }$retired"
        if [ "$ledger_safe" -ne 1 ] || \
           ! grep -Fqx "D	$retired" "$ledger_file"; then
          retired_unowned_count=$((retired_unowned_count + 1))
          [ "$retired_unowned_count" -le 4 ] && \
            retired_unowned_paths="${retired_unowned_paths}${retired_unowned_paths:+, }$retired"
        fi
      fi
    done
    if [ "$retired_count" -gt 0 ]; then
      if [ "$retired_unowned_count" -gt 0 ]; then
        suffix="$retired_unowned_paths"
        [ "$retired_unowned_count" -gt 4 ] && suffix="$suffix (+$((retired_unowned_count - 4)) more)"
        if [ "$ledger_safe" -eq 1 ]; then
          add_warn "maintainer generated root contains an unowned retired-name collision in $label: $suffix; generate.sh preserves unowned content. inspect the source first, retain foreign content or handle it separately, and remove only confirmed obsolete output before rerunning: $repair"
        else
          add_warn "maintainer generated root contains an unowned retired-name collision in $label: $suffix; the missing or unsafe ledger cannot establish ownership; $repair"
        fi
      fi
      retired_owned_count=$((retired_count - retired_unowned_count))
      if [ "$retired_owned_count" -gt 0 ]; then
        suffix="$retired_paths"
        [ "$retired_count" -gt 4 ] && suffix="$suffix (+$((retired_count - 4)) more)"
        add_warn "maintainer generated root contains retired owner output in $label: $suffix; $repair"
      fi
    fi
  done
  rm -rf -- "$health_tmp"
}

# Consumer refresh writes only ignored copies and local state. If the pinned toolkit
# is not checked out, warn before consulting its fan-out state or generating anything.
if [ "$is_toolkit_source" -ne 1 ]; then
  . "$HERE/lib/fanout.sh"
  recorded="$(fanout_recorded_revision "$proj_root_abs" "$toolkit_root")"
  current="$(git -C "$toolkit_root" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
    add_warn "the skill-commons submodule is not at the commit this repository records; run: git submodule update --init (or commit the submodule update if you made it)"
  elif [ -f "$shim" ] && grep -qF "skill-commons-stamp: $stamp" "$shim"; then
    . "$HERE/lib/manifest.sh"
    fanout_platforms="$(get_explicit_platforms "$PROJECT_ROOT/.agent/project-manifest.md" 2>/dev/null | tr ',' ' ')"
    if [ -n "$(fanout_roots "$fanout_platforms")" ] &&
        fanout_needs_regeneration "$PROJECT_ROOT" "$fanout_platforms" "$(fanout_signature "$toolkit_root" "$stamp")"; then
      if fanout_log="$(mktemp 2>/dev/null)"; then
        if ! bash "$HERE/onboard.sh" --refresh-ignored "$proj_root_abs" </dev/null >/dev/null 2>"$fanout_log"; then
          add_warn "could not regenerate the skill copies ($(head -n 2 "$fanout_log" | tr '\n' ' ')); run: bash <submodule>/bootstrap/onboard.sh"
        fi
        rm -f -- "$fanout_log"
      else
        add_warn "could not create a temporary log for skill regeneration; run: bash <submodule>/bootstrap/onboard.sh"
      fi
    fi
  fi
fi

# Check 3: platform coverage
if [ ! -f "$shim" ]; then
  if [ "$is_toolkit_source" -ne 1 ]; then
    add_warn "$shim is missing; run: bash <submodule>/bootstrap/onboard.sh"
  fi
else
  # Check 2: drift or not-onboarded
  embedded="$(grep -oE 'skill-commons-stamp: [a-f0-9]{12}' "$shim" | head -1 | awk '{print $2}')"
  if [ -z "$embedded" ]; then
    # A shim without the ownership stamp was never onboarded by skill-commons.
    # Exempt the toolkit source repo: it owns bootstrap and does not consume
    # itself, so its own sessions must not be nagged.
    if [ "$is_toolkit_source" -ne 1 ]; then
      add_warn "$shim has no skill-commons managed stamp (not onboarded); run: bash <submodule>/bootstrap/onboard.sh"
    fi
  elif [ "$embedded" != "$stamp" ]; then
    add_warn "configuration is out of date (stamp ${embedded} ≠ ${stamp}); run: bash <submodule>/bootstrap/onboard.sh"
  fi
fi

if [ "$is_toolkit_source" -eq 1 ]; then
  source_health_check
fi

# A source checkout is not a consuming repository and has no submodule mount.
# Point its emitted context at source paths that actually exist, then return
# before the consumer-only substitution below.
if [ "$is_toolkit_source" -eq 1 ]; then
  directive_body=$'本專案是 skill-commons maintainer source checkout。\n\n任何開發任務(PRD、技術 spec、QA 方案、功能實作、除錯、code review),必須先讀取 `./skill-router/SKILL.md`,並依其「Task routing table」載入對應 skill,再開始動作。\n\nsession 開始時請先執行 `bash ./bootstrap/check.sh --project-root .` 確認 source health;若出現警告,依指示修正後再繼續。'
  emit "$PLATFORM" "$directive_body" "$warnings"
  exit 0
fi

# Emit the directive with the ACTUAL submodule mount substituted for the hardcoded
# default, so a custom mount (e.g. vendor/skills) shows real, resolvable paths in the
# SessionStart context. check.sh lives at <subpath>/bootstrap/check.sh, so the mount
# is its own grandparent relative to the project root.
directive_body="$(cat "$DIRECTIVE")"
submodule_root="$(cd "$HERE/.." && pwd)"
case "$submodule_root" in
  "$PROJECT_ROOT"/*)
    subpath="${submodule_root#"$PROJECT_ROOT"/}"
    if [ -n "$subpath" ] && [ "$subpath" != ".agent/skills/_shared" ]; then
      directive_body="${directive_body//.agent\/skills\/_shared/$subpath}"
    fi
    ;;
esac
emit "$PLATFORM" "$directive_body" "$warnings"
exit 0
