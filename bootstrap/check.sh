#!/usr/bin/env bash
# Never abort the host session: no -e. Always exit 0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/stamp.sh"
. "$HERE/lib/platform.sh"

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
  add_warn "skill-commons submodule 未初始化,請執行: git submodule update --init"
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

# Check 3: platform coverage
if [ ! -f "$shim" ]; then
  if [ "$is_toolkit_source" -ne 1 ]; then
    add_warn "缺少 $shim,請執行: bash <submodule>/bootstrap/onboard.sh"
  fi
else
  # Check 2: drift or not-onboarded
  embedded="$(grep -oE 'skill-commons-stamp: [a-f0-9]{12}' "$shim" | head -1 | awk '{print $2}')"
  if [ -z "$embedded" ]; then
    # A shim without the ownership stamp was never onboarded by skill-commons.
    # Exempt the toolkit source repo: it owns bootstrap and does not consume
    # itself, so its own sessions must not be nagged.
    if [ "$is_toolkit_source" -ne 1 ]; then
      add_warn "$shim 缺少 skill-commons managed stamp(未 onboard),請執行: bash <submodule>/bootstrap/onboard.sh"
    fi
  elif [ "$embedded" != "$stamp" ]; then
    add_warn "設定已過期 (stamp ${embedded} ≠ ${stamp}),請執行: bash <submodule>/bootstrap/onboard.sh"
  fi
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
