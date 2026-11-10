# Generated skill copies stay out of Git (T13, option F). Source this file.
#
# onboard.sh writes a fenced block into the project's .gitignore that names every unit the
# ownership ledgers list, plus the ledgers and a state file. check.sh regenerates the copies
# at session start when a unit is missing or the submodule moved, so a fresh clone or a
# teammate's `git pull` gets current copies without committing them.

FANOUT_STATE=".agent/.skill-commons-fanout"
FANOUT_LEDGER=".skill-commons-ownership-v1"
FANOUT_LEDGER_HEADER="skill-commons-ownership-v1"
# Codex documents `.agents/skills` (repository) for skills; earlier installs wrote `.codex/skills`.
FANOUT_LEGACY_CODEX=".codex/skills"
GI_START="# >>> skill-commons generated skill copies (written by onboard.sh; do not edit)"
GI_END="# <<< skill-commons generated skill copies"

fanout_roots() {
  # $1 = space-separated platforms -> project-relative generation roots, one per line
  case " $1 " in *" claude-code "*) printf '%s\n' ".claude/skills" ;; esac
  case " $1 " in *" codex "*) printf '%s\n' ".agents/skills" ;; esac
}

fanout_signature() {
  # $1 = toolkit root (the submodule), $2 = directive stamp
  # Only the toolkit's own checkout counts: a vendored copy inside the project would
  # otherwise report the project's HEAD and regenerate after every commit.
  local rev="unknown" top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$(cd "$1" && pwd -P)" ]; then
    rev="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || rev="unknown"
  fi
  printf 'submodule=%s\nstamp=%s\n' "$rev" "$2"
}

fanout_unit_files() {
  # Enumerate only source files for a ledger unit; never a whole skill directory.
  local source="$1" kind="$2" unit="$3"
  case "$kind" in
    D) (cd "$source" && find "$unit" ! -type d -print | LC_ALL=C sort) ;;
    F) printf '%s\n' "$unit" ;;
  esac
}

fanout_ignore_lines() {
  local rel kind unit file
  printf '/%s\n' "$FANOUT_STATE"
  while IFS= read -r rel; do
    printf '/%s/%s\n' "$rel" "$FANOUT_LEDGER"
    [ -f "$1/$rel/$FANOUT_LEDGER" ] || continue
    while IFS=$'\t' read -r kind unit; do
      while IFS= read -r file; do
        printf '/%s/%s\n' "$rel" "$file"
      done < <(fanout_unit_files "$HERE/.." "$kind" "$unit")
    done < <(tail -n +2 "$1/$rel/$FANOUT_LEDGER")
  done < <(fanout_roots "$2")
}

render_ignore_block() {
  printf '%s\n' "$GI_START"
  fanout_ignore_lines "$1" "$2" | sed 's/[][?*\\ ]/\\&/g'
  printf '%s\n' "$GI_END"
}

upsert_ignore_block() {
  # $1 = .gitignore, $2 = block file. Reuses the shim fence logic with gitignore markers.
  local AP_START="$GI_START" AP_END="$GI_END"
  upsert_block "$1" "$2"
}

validate_ignore_block() {
  local AP_START="$GI_START" AP_END="$GI_END"
  validate_managed_block "$1"
}

remove_ignore_block() {
  local AP_START="$GI_START" AP_END="$GI_END"
  remove_managed_block "$1"
}

fanout_tracked() {
  # Report exact source files still in the index, even if a tracked copy is missing on disk.
  local rel kind unit file paths=()
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  while IFS= read -r rel; do
    [ -f "$1/$rel/$FANOUT_LEDGER" ] && [ ! -L "$1/$rel/$FANOUT_LEDGER" ] || continue
    paths+=("$rel/$FANOUT_LEDGER")
    while IFS=$'\t' read -r kind unit; do
      valid_owned_record "$kind" "$unit" || continue
      [ "$kind" != D ] || [ -d "$HERE/../$unit" ] || continue
      while IFS= read -r file; do paths+=("$rel/$file"); done < <(fanout_unit_files "$HERE/.." "$kind" "$unit")
    done < <(tail -n +2 "$1/$rel/$FANOUT_LEDGER")
  done < <(fanout_roots "$2")
  [ "${#paths[@]}" -gt 0 ] || return 0
  LC_ALL=C comm -12 \
    <(printf '%s\n' "${paths[@]}" | LC_ALL=C sort -u) \
    <(git -C "$1" --literal-pathspecs ls-files -z -- "${paths[@]}" | tr '\0' '\n' | LC_ALL=C sort -u)
}

validate_fanout_state() {
  local state="$1/$FANOUT_STATE"
  validate_regular_candidate "$state" "skill copy state" || return 1
  [ -e "$state" ] || return 0
  if ! sed -n '1p' "$state" | grep -Eq '^submodule=(unknown|[a-f0-9]{40}|[a-f0-9]{64})$' ||
     ! sed -n '2p' "$state" | grep -Eq '^stamp=[a-f0-9]{12}$' ||
     [ -n "$(sed -n '3p' "$state")" ]; then
    error "refusing to replace or remove an unrecognized skill copy state file: $state"
    return 1
  fi
  if [ -n "$(git -C "$1" ls-files -- "$FANOUT_STATE" 2>/dev/null)" ]; then
    error "the generated state file is tracked; review it, then untrack it with git rm --cached -- $FANOUT_STATE"
    return 1
  fi
}

fanout_recorded_revision() {
  local mount="${2#"$1"/}"
  [ "$mount" != "$2" ] || return 0
  git -C "$1" ls-tree HEAD -- "$mount" 2>/dev/null | awk '$2 == "commit" {print $3}'
}

fanout_previous_revision() {
  local state="$1/$FANOUT_STATE"
  [ -f "$state" ] && [ ! -L "$state" ] || return 0
  sed -n 's/^submodule=\([0-9a-f]\{40,64\}\)$/\1/p' "$state"
}

validate_fanout_payload() {
  # An owned unit may be incomplete after an interrupted copy or migration.
  # Every surviving entry must come from the toolkit. Explicit onboarding can
  # repair drift in a file still present in the current source.
  local target="$1" ledger="$2" source="$3" require_exact="$4"
  shift 4
  local kind unit actual rel revision matched inventory cache_source
  inventory="$(mktemp)" || return 1
  while IFS=$'\t' read -r kind unit || [ -n "${kind:-}${unit:-}" ]; do
    [ -n "$unit" ] || continue
    [ -e "$target/$unit" ] || continue
    if ! find "$target/$unit" -print0 > "$inventory"; then
      rm -f -- "$inventory"
      return 1
    fi
    while IFS= read -r -d '' actual; do
      rel="${actual#"$target"/}"
      if [ ! -L "$actual" ]; then
        if { [ -d "$actual" ] && [ -d "$source/$rel" ]; } ||
           { [ -f "$actual" ] && [ -f "$source/$rel" ] &&
             { [ "$require_exact" = 0 ] || cmp -s "$actual" "$source/$rel"; }; }; then
          continue
        fi
        # Python can write bytecode next to a copied helper. Allow only a cache
        # whose module is in the toolkit. Other files under __pycache__ still fail.
        cache_source=""
        if [ -d "$actual" ] && [[ "$rel" = */__pycache__ ]]; then
          cache_source="${rel%/*}"
          [ ! -d "$source/$cache_source" ] || continue
        elif [ -f "$actual" ] && [[ "$rel" = */__pycache__/* ]] &&
             [[ "${rel##*/}" =~ ^([A-Za-z0-9_.-]+)\.(cpython|pypy)-[0-9]+(\.opt-[0-9]+)?\.pyc$ ]]; then
          cache_source="${rel%/__pycache__/*}/${BASH_REMATCH[1]}.py"
          [ ! -f "$source/$cache_source" ] || continue
        fi
        matched=0
        for revision in "$@"; do
          [ -n "$revision" ] || continue
          if [ -n "$cache_source" ] && git -C "$source" cat-file -e "$revision:$cache_source" 2>/dev/null; then
            matched=1
            break
          fi
          if { [ -d "$actual" ] && [ "$(git -C "$source" cat-file -t "$revision:$rel" 2>/dev/null)" = tree ]; } ||
             { [ -f "$actual" ] && git -C "$source" cat-file blob "$revision:$rel" > "$inventory.blob" 2>/dev/null &&
               cmp -s "$actual" "$inventory.blob"; }; then
            matched=1
            break
          fi
        done
        [ "$matched" -ne 1 ] || continue
      fi
      rm -f -- "$inventory" "$inventory.blob"
      error "locally changed generated path: $actual. Move local files outside the generated path before retrying."
      return 1
    done < "$inventory"
  done < <(tail -n +2 "$ledger")
  rm -f -- "$inventory" "$inventory.blob"
}

fanout_needs_regeneration() {
  # $1 = project root, $2 = platforms, $3 = expected signature. Returns 0 when copies are
  # missing, a ledger unit is gone, or the recorded signature differs.
  local rel kind unit
  [ -f "$1/$FANOUT_STATE" ] && [ ! -L "$1/$FANOUT_STATE" ] &&
    [ "$(cat "$1/$FANOUT_STATE" 2>/dev/null)" = "$3" ] || return 0
  while IFS= read -r rel; do
    [ -f "$1/$rel/$FANOUT_LEDGER" ] && [ ! -L "$1/$rel/$FANOUT_LEDGER" ] &&
      [ "$(head -n 1 "$1/$rel/$FANOUT_LEDGER")" = "$FANOUT_LEDGER_HEADER" ] || return 0
    while IFS=$'\t' read -r kind unit; do
      case "$kind" in
        D) [ -f "$1/$rel/$unit/SKILL.md" ] || return 0 ;;
        F) [ -f "$1/$rel/$unit" ] || return 0 ;;
      esac
    done < <(tail -n +2 "$1/$rel/$FANOUT_LEDGER")
  done < <(fanout_roots "$2")
  return 1
}
