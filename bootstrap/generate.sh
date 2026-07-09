#!/usr/bin/env bash
# generate.sh — fan out top-level skill folders (single source of truth, ADR-001)
# into per-agent skill dirs so they are `/`-triggerable in Claude Code, Codex, etc.
#
# Usage:
#   bash bootstrap/generate.sh                 # default agent dirs under repo root
#   bash bootstrap/generate.sh <dir> [<dir>..] # explicit agent skill roots
#   SKILLS_SRC=/path bash bootstrap/generate.sh # override source root (e.g. _shared mount)
#   PROFILE=team-sprint bash bootstrap/generate.sh # fan only skills in profiles/<name>
#   PROFILE="personal optional" bash bootstrap/generate.sh # compose bundles
#
# Generated dirs are .gitignored (ADR-001). Re-run after adding/removing skills.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SKILLS_SRC:-$(cd "$HERE/.." && pwd)}"
PROFILE="$(printf '%s' "${PROFILE:-}" | tr ',' ' ' | xargs)"

# Default fan-out targets: Claude Code + Codex + generic agents root.
if [ "$#" -gt 0 ]; then
  AGENTS=("$@")
else
  AGENTS=("$ROOT/.claude/skills" "$ROOT/.codex/skills" "$ROOT/.agents/skills")
fi

# Non-skill top-level dirs to skip.
skip() {
  case "$1" in
    _archive|_shared|docs|bootstrap|scripts|tests|profiles|node_modules) return 0;;
    *) return 1;;
  esac
}

# Resolve profiles/<name> into skill names. Lines: skill name, '#' comment,
# blank, or '@<profile>' include (e.g. team-sprint = '@core' + overlay).
resolve_profile() {
  local name="$1" depth="${2:-0}" file="$ROOT/profiles/$1" line
  [ "$depth" -le 3 ] || { echo "ERROR: profile include depth > 3 (cycle in '$name'?)" >&2; exit 1; }
  [ -f "$file" ] || { echo "ERROR: profile '$name' not found at $file" >&2; exit 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -z "$line" ] && continue
    case "$line" in
      @*) resolve_profile "${line#@}" $((depth + 1));;
      *) printf '%s\n' "$line";;
    esac
  done < "$file"
}

# With PROFILE set, only fan skills in the list; a listed name without a real
# skill folder is a hard error (stale list / typo must not pass silently).
PROFILE_SKILLS=""
if [ -n "$PROFILE" ]; then
  PROFILE_SKILLS="$(
    for profile_name in $PROFILE; do
      resolve_profile "$profile_name"
    done | sort -u | tr '\n' ' '
  )"
  for name in $PROFILE_SKILLS; do
    [ -f "$ROOT/$name/SKILL.md" ] || {
      echo "ERROR: profile set '$PROFILE' lists '$name' but $ROOT/$name/SKILL.md does not exist" >&2
      exit 1
    }
  done
fi

in_profile() {
  [ -z "$PROFILE" ] && return 0
  case " $PROFILE_SKILLS " in *" $1 "*) return 0;; *) return 1;; esac
}

# Clear + recreate each target so archived/renamed skills don't linger (these dirs are gitignored, fully generated).
for agent in "${AGENTS[@]}"; do rm -rf "${agent:?}"; mkdir -p "$agent"; done

count=0
for d in "$ROOT"/*/; do
  name="$(basename "$d")"
  skip "$name" && continue
  [ -f "$d/SKILL.md" ] || continue
  # skill-creator is a repository-maintainer tool, not a consuming workflow skill.
  [ "$name" = "skill-creator" ] && continue
  in_profile "$name" || continue
  for agent in "${AGENTS[@]}"; do
    rm -rf "${agent:?}/${name}"
    cp -R "$ROOT/$name" "$agent/$name"
  done
  count=$((count + 1))
done

# Shared top-level .md fragments that skills link via ../<file>.md (not skill folders,
# so the loop above skips them). Copy into each agent root so those links resolve.
SHARED_FRAGMENTS="ARTIFACTS.md GATE-PACKAGE.md graph-context-check.md SOURCES.md CHECKLIST-CONVENTION.md prd-template.md"
for agent in "${AGENTS[@]}"; do
  for frag in $SHARED_FRAGMENTS; do
    [ -f "$ROOT/$frag" ] && cp "$ROOT/$frag" "$agent/$frag"
  done
done

# Runtime helpers referenced by generated skills and shared artifact docs.
SHARED_SCRIPTS="manifest-stack.sh run-gate.sh work-items.sh work_items.py check-prd.py"
for agent in "${AGENTS[@]}"; do
  mkdir -p "$agent/scripts"
  for script in $SHARED_SCRIPTS; do
    cp "$ROOT/scripts/$script" "$agent/scripts/$script"
  done
done

echo "generate.sh: fanned $count skills (profile=${PROFILE:-all}) -> ${#AGENTS[@]} agent dir(s):"
for agent in "${AGENTS[@]}"; do echo "  - $agent"; done
