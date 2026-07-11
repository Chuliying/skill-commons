#!/usr/bin/env bash
# generate.sh — fan out top-level skill folders (single source of truth, ADR-001)
# into per-agent skill dirs so they are `/`-triggerable in Claude Code, Codex, etc.
#
# Usage:
#   DELIVERY_MODE=personal bash bootstrap/generate.sh # one delivery mode
#   DELIVERY_MODE=personal CAPABILITY_PACKS="frontend optional" bash bootstrap/generate.sh
#   PROFILE="personal optional" bash bootstrap/generate.sh # legacy compatibility
#   PROFILE=all bash bootstrap/generate.sh      # explicit maintainer full fan-out
#   SKILLS_SRC=/path ... bash bootstrap/generate.sh # override source root
#   SKILL_COMMONS_ADOPT_LEGACY=1 bash bootstrap/generate.sh # one-time pre-ledger migration
#
# Generated units are recorded in a target-local ownership ledger. Re-running
# updates only those units and preserves unrelated entries in shared skill roots.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SKILLS_SRC:-$(cd "$HERE/.." && pwd)}"
ROOT="$(cd "$ROOT" && pwd -P)"
LEGACY_PROFILE="$(printf '%s' "${PROFILE:-}" | tr ',' ' ' | xargs)"
DELIVERY_MODE_INPUT="$(printf '%s' "${DELIVERY_MODE:-}" | tr ',' ' ' | xargs)"
CAPABILITY_PACKS_INPUT="$(printf '%s' "${CAPABILITY_PACKS:-}" | tr ',' ' ' | xargs)"
PROFILE=""
PROFILE_ALL=0
PROFILE_LABEL=""
PROJECT_ROOT_GUARD="${SKILL_COMMONS_PROJECT_ROOT:-}"
ADOPT_LEGACY="${SKILL_COMMONS_ADOPT_LEGACY:-0}"
PREFLIGHT_ONLY="${SKILL_COMMONS_PREFLIGHT_ONLY:-0}"
OWNERSHIP_FILE=".skill-commons-ownership-v1"
OWNERSHIP_HEADER="skill-commons-ownership-v1"

case "$ADOPT_LEGACY" in
  0|1) ;;
  *) echo "ERROR: SKILL_COMMONS_ADOPT_LEGACY must be 0 or 1" >&2; exit 1 ;;
esac
case "$PREFLIGHT_ONLY" in
  0|1) ;;
  *) echo "ERROR: SKILL_COMMONS_PREFLIGHT_ONLY must be 0 or 1" >&2; exit 1 ;;
esac

# Default fan-out targets: Claude Code + Codex + generic agents root.
if [ "$#" -gt 0 ]; then
  AGENTS=("$@")
else
  AGENTS=("$ROOT/.claude/skills" "$ROOT/.codex/skills" "$ROOT/.agents/skills")
fi

error() {
  echo "ERROR: $*" >&2
  return 1
}

. "$HERE/lib/ownership.sh"

if [ -n "$PROJECT_ROOT_GUARD" ]; then
  [ -d "$PROJECT_ROOT_GUARD" ] || { error "project root does not exist: $PROJECT_ROOT_GUARD"; exit 1; }
  PROJECT_ROOT_GUARD="$(cd "$PROJECT_ROOT_GUARD" && pwd -P)"
fi

TARGETS=()
for agent in "${AGENTS[@]}"; do
  target="$(canonical_candidate_path "$agent")" || exit 1
  TARGETS+=("$target")
done

# A nested target can be overwritten by an outer target later in the same run
# while every individual target still looks valid. Reject duplicates and
# ancestor/descendant pairs as one invalid target set.
for i in "${!TARGETS[@]}"; do
  for j in "${!TARGETS[@]}"; do
    [ "$j" -gt "$i" ] || continue
    left="${TARGETS[$i]}"
    right="${TARGETS[$j]}"
    if [ "$left" = "$right" ] || [[ "$left" == "$right/"* ]] || [[ "$right" == "$left/"* ]]; then
      error "generation targets overlap: $left <> $right"
      exit 1
    fi
  done
done

# Validate every base target before profile/source discovery or any mutation.
for target in "${TARGETS[@]}"; do validate_target_base "$target" || exit 1; done

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

# Resolve the public model into the existing flat profile lists. The preferred
# interface requires exactly one delivery mode and accepts zero-or-more packs.
# Non-empty PROFILE remains a migration path; `core` and `all` are explicit
# maintainer compatibility tokens, never implicit consuming defaults.
append_profile() {
  local name="$1"
  case " $PROFILE " in
    *" $name "*) error "duplicate profile selection: $name"; return 1 ;;
    *) PROFILE="${PROFILE:+$PROFILE }$name" ;;
  esac
}

valid_profile_token() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]]
}

configure_profile_selection() {
  local token mode_count=0 base_count=0
  local tokens=()

  if [ -n "$LEGACY_PROFILE" ] && { [ -n "$DELIVERY_MODE_INPUT" ] || [ -n "$CAPABILITY_PACKS_INPUT" ]; }; then
    error "PROFILE cannot be combined with DELIVERY_MODE or CAPABILITY_PACKS"
    return 1
  fi

  if [ -n "$LEGACY_PROFILE" ]; then
    if [ "$LEGACY_PROFILE" = "all" ]; then
      PROFILE_ALL=1
      PROFILE_LABEL="maintainer-all"
      return 0
    fi
    read -r -a tokens <<< "$LEGACY_PROFILE"
    for token in "${tokens[@]}"; do
      valid_profile_token "$token" || { error "invalid profile token: $token"; return 1; }
      case "$token" in
        personal|team-sprint)
          mode_count=$((mode_count + 1))
          append_profile "$token" || return 1
          ;;
        core)
          base_count=$((base_count + 1))
          append_profile "$token" || return 1
          ;;
        frontend|optional)
          append_profile "$token" || return 1
          ;;
        all)
          error "PROFILE=all cannot be composed with other profiles"
          return 1
          ;;
        *)
          error "unknown legacy profile token: $token"
          return 1
          ;;
      esac
    done
    [ "$mode_count" -le 1 ] || { error "select exactly one delivery mode"; return 1; }
    [ "$base_count" -le 1 ] || { error "core may be selected only once"; return 1; }
    if [ "$mode_count" -eq 0 ] && [ "$base_count" -eq 0 ]; then
      error "legacy PROFILE requires personal, team-sprint, or maintainer core"
      return 1
    fi
    if [ "$mode_count" -eq 1 ] && [ "$base_count" -eq 1 ]; then
      error "delivery modes already include core"
      return 1
    fi
    PROFILE_LABEL="legacy:$PROFILE"
    return 0
  fi

  [ -n "$DELIVERY_MODE_INPUT" ] || {
    error "delivery mode is required; set DELIVERY_MODE=personal|team-sprint (PROFILE=all is maintainer-only)"
    return 1
  }
  valid_profile_token "$DELIVERY_MODE_INPUT" || { error "invalid delivery mode: $DELIVERY_MODE_INPUT"; return 1; }
  case "$DELIVERY_MODE_INPUT" in
    personal|team-sprint) append_profile "$DELIVERY_MODE_INPUT" || return 1 ;;
    *) error "unknown delivery mode: $DELIVERY_MODE_INPUT"; return 1 ;;
  esac

  if [ -n "$CAPABILITY_PACKS_INPUT" ]; then
    read -r -a tokens <<< "$CAPABILITY_PACKS_INPUT"
    for token in "${tokens[@]}"; do
      valid_profile_token "$token" || { error "invalid capability pack: $token"; return 1; }
      case "$token" in
        frontend|optional) append_profile "$token" || return 1 ;;
        *) error "unknown capability pack: $token"; return 1 ;;
      esac
    done
  fi
  PROFILE_LABEL="delivery:$DELIVERY_MODE_INPUT packs:${CAPABILITY_PACKS_INPUT:-none}"
}

configure_profile_selection || exit 1

# A selected name without a real skill folder is a hard error (stale list / typo
# must not pass silently). `all` skips filtering but still excludes maintainer-only
# skill-creator in the source discovery loop below.
PROFILE_SKILLS=""
if [ "$PROFILE_ALL" -eq 0 ]; then
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
  [ "$PROFILE_ALL" -eq 1 ] && return 0
  case " $PROFILE_SKILLS " in *" $1 "*) return 0;; *) return 1;; esac
}

# Build one deterministic desired ownership set and a temporary payload before
# touching any target. A managed directory is one whole skill; shared scripts
# are owned file-by-file so foreign helpers in scripts/ survive.
DESIRED_KINDS=()
DESIRED_PATHS=()
DESIRED_SOURCES=()
MANAGEABLE_KINDS=()
MANAGEABLE_PATHS=()
MANAGEABLE_SOURCES=()

add_desired() {
  DESIRED_KINDS+=("$1")
  DESIRED_PATHS+=("$2")
  DESIRED_SOURCES+=("$3")
}

add_manageable() {
  MANAGEABLE_KINDS+=("$1")
  MANAGEABLE_PATHS+=("$2")
  MANAGEABLE_SOURCES+=("$3")
}

count=0
for d in "$ROOT"/*/; do
  name="$(basename "$d")"
  skip "$name" && continue
  [ -f "$d/SKILL.md" ] || continue
  # skill-creator is a repository-maintainer tool, not a consuming workflow skill.
  [ "$name" = "skill-creator" ] && continue
  add_manageable D "$name" "$ROOT/$name"
  in_profile "$name" || continue
  add_desired D "$name" "$ROOT/$name"
  count=$((count + 1))
done

# Shared top-level fragments that skills link via ../<file> (not skill folders,
# so the loop above skips them). Copy into each agent root so those links resolve.
while IFS= read -r frag || [ -n "$frag" ]; do
  [ -n "$frag" ] || continue
  if [ -f "$ROOT/$frag" ]; then
    add_manageable F "$frag" "$ROOT/$frag"
    add_desired F "$frag" "$ROOT/$frag"
  fi
done < <(skill_commons_shared_fragments)

# Runtime helpers referenced by generated skills and shared artifact docs.
while IFS= read -r script || [ -n "$script" ]; do
  [ -n "$script" ] || continue
  [ -f "$ROOT/scripts/$script" ] || { error "missing shared runtime helper: $ROOT/scripts/$script"; exit 1; }
  add_manageable F "scripts/$script" "$ROOT/scripts/$script"
  add_desired F "scripts/$script" "$ROOT/scripts/$script"
done < <(skill_commons_shared_scripts)

# Frozen ownership inventory from every tagged pre-ledger release
# (v0.1.0-v0.4.1). Current manageable paths are duplicated intentionally;
# retired names remain here so explicit migration cannot strand them as
# discoverable, unowned skills.
LEGACY_PRE_LEDGER_DIRS=(
  brainstorming caveman-review codebase-understanding design-taste-frontend
  dev-kickoff domain-modeling finishing-a-development-branch grill-me
  grill-with-docs grilling implement markdown plan-sync ponytail prd-interview
  prototype qa reducing-entropy requesting-code-review rollback security
  shared-skill-onboarder skill-creator skill-router spec
  subagent-driven-development sync-work systematic-debugging tdd to-prd
  verification-before-completion
)
LEGACY_PRE_LEDGER_FILES=(
  ARTIFACTS.md graph-context-check.md SOURCES.md CHECKLIST-CONVENTION.md
)

current_manageable_has() {
  local kind="$1" relative="$2" i
  for i in "${!MANAGEABLE_PATHS[@]}"; do
    if [ "${MANAGEABLE_KINDS[$i]}" = "$kind" ] && [ "${MANAGEABLE_PATHS[$i]}" = "$relative" ]; then
      return 0
    fi
  done
  return 1
}

TEMP_ROOT="$(mktemp -d)"
LOCK_DIRS=()
cleanup() {
  local lock
  for lock in ${LOCK_DIRS[@]+"${LOCK_DIRS[@]}"}; do rm -rf -- "$lock"; done
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
PAYLOAD="$TEMP_ROOT/payload"
DESIRED_LEDGER="$TEMP_ROOT/desired-ledger"
mkdir -p "$PAYLOAD"

for i in "${!DESIRED_PATHS[@]}"; do
  relative="${DESIRED_PATHS[$i]}"
  source_path="${DESIRED_SOURCES[$i]}"
  destination="$PAYLOAD/$relative"
  mkdir -p "$(dirname "$destination")"
  if [ "${DESIRED_KINDS[$i]}" = D ]; then
    cp -R "$source_path" "$destination"
  else
    cp "$source_path" "$destination"
  fi
done

printf '%s\n' "$OWNERSHIP_HEADER" > "$DESIRED_LEDGER"
for i in "${!DESIRED_PATHS[@]}"; do
  printf '%s\t%s\n' "${DESIRED_KINDS[$i]}" "${DESIRED_PATHS[$i]}"
done | LC_ALL=C sort >> "$DESIRED_LEDGER"

# Serialize each canonical target from preflight through ledger publication.
# The lock lives in the system temp root so a not-yet-created target stays
# untouched until every target is locked and validated.
for target in "${TARGETS[@]}"; do
  lock_dir="$(ownership_lock_path "$target")"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    error "generation target is locked: $target ($lock_dir)"
    exit 1
  fi
  printf '%s\n' "$$" > "$lock_dir/pid"
  LOCK_DIRS+=("$lock_dir")
done

is_legacy_generated_root() {
  local target="$1"
  [ ! -L "$target/skill-router" ] &&
    [ -f "$target/skill-router/SKILL.md" ] &&
    [ ! -L "$target/ARTIFACTS.md" ] && [ -f "$target/ARTIFACTS.md" ] &&
    grep -Eq '^name:[[:space:]]*skill-router[[:space:]]*$' "$target/skill-router/SKILL.md"
}


# Preflight every ledger, owned path, symlink boundary, and unowned collision
# before changing the first target.
TARGET_MODES=()
target_index=0
for target in "${TARGETS[@]}"; do
  ledger="$target/$OWNERSHIP_FILE"
  seen="$TEMP_ROOT/seen-$target_index"
  validate_ledger "$ledger" "$seen" || exit 1
  target_mode=unowned

  if [ -f "$ledger" ]; then
    target_mode=ledger
    while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
      [ -n "${kind:-}${relative:-}" ] || continue
      validate_managed_path "$target" "$kind" "$relative" || exit 1
    done < <(tail -n +2 "$ledger")
  elif is_legacy_generated_root "$target"; then
    if [ "$ADOPT_LEGACY" = 1 ]; then
      target_mode=legacy_explicit
    else
      target_mode=legacy_identical
    fi
    for i in "${!MANAGEABLE_PATHS[@]}"; do
      kind="${MANAGEABLE_KINDS[$i]}"
      relative="${MANAGEABLE_PATHS[$i]}"
      if [ -e "$target/$relative" ] || [ -L "$target/$relative" ]; then
        validate_managed_path "$target" "$kind" "$relative" || exit 1
        if [ "$target_mode" = legacy_identical ] &&
          ! same_payload "$kind" "${MANAGEABLE_SOURCES[$i]}" "$target/$relative"; then
          error "changed pre-ledger generated root requires explicit adoption: SKILL_COMMONS_ADOPT_LEGACY=1 ($target)"
          exit 1
        fi
      fi
    done
    for relative in "${LEGACY_PRE_LEDGER_DIRS[@]}"; do
      if [ -e "$target/$relative" ] || [ -L "$target/$relative" ]; then
        validate_managed_path "$target" D "$relative" || exit 1
        if [ "$target_mode" = legacy_identical ] && ! current_manageable_has D "$relative"; then
          error "historical pre-ledger output requires explicit adoption: SKILL_COMMONS_ADOPT_LEGACY=1 ($target/$relative)"
          exit 1
        fi
      fi
    done
    for relative in "${LEGACY_PRE_LEDGER_FILES[@]}"; do
      if [ -e "$target/$relative" ] || [ -L "$target/$relative" ]; then
        validate_managed_path "$target" F "$relative" || exit 1
        if [ "$target_mode" = legacy_identical ] && ! current_manageable_has F "$relative"; then
          error "historical pre-ledger output requires explicit adoption: SKILL_COMMONS_ADOPT_LEGACY=1 ($target/$relative)"
          exit 1
        fi
      fi
    done
  fi

  for i in "${!DESIRED_PATHS[@]}"; do
    kind="${DESIRED_KINDS[$i]}"
    relative="${DESIRED_PATHS[$i]}"
    destination="$target/$relative"
    validate_managed_path "$target" "$kind" "$relative" || exit 1
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      if [ -f "$ledger" ] && ledger_owns "$ledger" "$kind" "$relative"; then
        :
      elif same_payload "$kind" "$PAYLOAD/$relative" "$destination"; then
        :
      elif [ "$target_mode" = legacy_explicit ]; then
        :
      else
        error "unowned path conflicts with generated content: $destination"
        exit 1
      fi
    fi
  done
  preflight_writable_directory "$target" "generation target" || exit 1
  TARGET_MODES+=("$target_mode")
  target_index=$((target_index + 1))
done

# The caller can exercise the complete discovery, lock, ledger, symlink, and
# collision preflight without publishing one byte to a target. Onboarding uses
# this before it publishes any platform adapter, then normal generation repeats
# the checks immediately before its own target publication.
if [ "$PREFLIGHT_ONLY" = 1 ]; then
  echo "generate.sh: preflight complete (selection=$PROFILE_LABEL) -> ${#TARGETS[@]} agent dir(s)"
  exit 0
fi

# All targets are safe. Replace only recorded units (or identical legacy units),
# install the staged payload, then atomically publish the new ledger.
target_index=0
for target in "${TARGETS[@]}"; do
  mkdir -p "$target"
  ledger="$target/$OWNERSHIP_FILE"
  target_mode="${TARGET_MODES[$target_index]}"
  if [ "$target_mode" = ledger ]; then
    while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
      [ -n "${kind:-}${relative:-}" ] || continue
      rm -rf -- "$target/$relative"
    done < <(tail -n +2 "$ledger")
  elif [ "$target_mode" = legacy_explicit ] || [ "$target_mode" = legacy_identical ]; then
    for relative in "${MANAGEABLE_PATHS[@]}"; do
      [ ! -e "$target/$relative" ] && [ ! -L "$target/$relative" ] || rm -rf -- "$target/$relative"
    done
    for relative in "${LEGACY_PRE_LEDGER_DIRS[@]}" "${LEGACY_PRE_LEDGER_FILES[@]}"; do
      [ ! -e "$target/$relative" ] && [ ! -L "$target/$relative" ] || rm -rf -- "$target/$relative"
    done
  fi

  # Preflight proved every remaining desired collision was either owned or
  # byte-identical. Remove it before copying so cp never nests a directory.
  for relative in "${DESIRED_PATHS[@]}"; do
    [ ! -e "$target/$relative" ] && [ ! -L "$target/$relative" ] || rm -rf -- "$target/$relative"
  done

  for i in "${!DESIRED_PATHS[@]}"; do
    relative="${DESIRED_PATHS[$i]}"
    destination="$target/$relative"
    mkdir -p "$(dirname "$destination")"
    if [ "${DESIRED_KINDS[$i]}" = D ]; then
      cp -R "$PAYLOAD/$relative" "$destination"
    else
      cp "$PAYLOAD/$relative" "$destination"
    fi
  done
  ledger_tmp="$(mktemp "$target/$OWNERSHIP_FILE.tmp.XXXXXX")"
  [ -f "$ledger_tmp" ] && [ ! -L "$ledger_tmp" ] || { error "failed to create a regular ledger temp file: $ledger_tmp"; exit 1; }
  cp "$DESIRED_LEDGER" "$ledger_tmp"
  chmod 0644 "$ledger_tmp"
  mv -f "$ledger_tmp" "$ledger"
  target_index=$((target_index + 1))
done

echo "generate.sh: fanned $count skills (selection=$PROFILE_LABEL) -> ${#TARGETS[@]} agent dir(s):"
for target in "${TARGETS[@]}"; do echo "  - $target"; done
