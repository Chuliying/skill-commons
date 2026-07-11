# Canonical target and ownership-ledger safety helpers. Source this file after
# defining error(), ROOT, PROJECT_ROOT_GUARD, OWNERSHIP_FILE, and
# OWNERSHIP_HEADER. Callers must preflight every target before removing any unit.

absolute_lexical_path() {
  local path="$1"
  [ -n "$path" ] || { error "empty generation target"; return 1; }
  case "$path" in
    /*) ;;
    *) path="$PWD/$path" ;;
  esac
  while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do path="${path%/}"; done
  case "$path" in
    *$'\n'*|*$'\r'*|*$'\t'*) error "target contains control characters: $path"; return 1 ;;
  esac
  case "/$path/" in
    *"/../"*|*"/./"*) error "target contains an unsafe path component: $path"; return 1 ;;
  esac
  printf '%s' "$path"
}

canonical_candidate_path() {
  local path cursor base part suffix=""
  path="$(absolute_lexical_path "$1")" || return 1
  [ ! -L "$path" ] || { error "generation target is a symlink: $path"; return 1; }

  cursor="$path"
  while [ ! -e "$cursor" ] && [ ! -L "$cursor" ]; do
    part="${cursor##*/}"
    if [ -n "$suffix" ]; then suffix="$part
$suffix"; else suffix="$part"; fi
    cursor="${cursor%/*}"
    [ -n "$cursor" ] || cursor="/"
  done
  [ -d "$cursor" ] || { error "target ancestor is not a directory: $cursor"; return 1; }
  base="$(cd "$cursor" && pwd -P)"
  if [ -n "$suffix" ]; then
    while IFS= read -r part; do base="${base%/}/$part"; done <<< "$suffix"
  fi
  printf '%s' "$base"
}

# Bootstrap reserves these adapter directories for managed writes. Reject a
# symlink or non-directory component before any project mutation so a shim,
# settings file, rule, or ledger cannot escape the project root.
validate_project_managed_ancestors() {
  local project_root="$1" platforms="${2:-}" relatives=".agent" relative current part old_ifs
  if platform_is_selected "$platforms" claude-code; then
    relatives="$relatives .claude .claude/skills"
  fi
  if platform_is_selected "$platforms" codex; then
    relatives="$relatives .codex .codex/skills"
  fi
  if platform_is_selected "$platforms" cursor; then
    relatives="$relatives .cursor .cursor/rules"
  fi
  for relative in $relatives; do
    current="$project_root"
    old_ifs="$IFS"
    IFS='/'
    read -r -a parts <<< "$relative"
    IFS="$old_ifs"
    for part in "${parts[@]}"; do
      current="$current/$part"
      if [ -L "$current" ]; then
        error "managed adapter ancestor is a symlink: $current"
        return 1
      fi
      if [ -e "$current" ] && [ ! -d "$current" ]; then
        error "managed adapter ancestor is not a directory: $current"
        return 1
      fi
    done
  done
}

platform_is_selected() {
  case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

validate_regular_candidate() {
  local path="$1" label="$2"
  if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
    error "$label is not a regular file: $path"
    return 1
  fi
}

# Probe the exact directory that must accept an atomic publication, or its
# nearest existing ancestor when the directory has not been created yet. The
# probe is removed immediately and runs before any managed artifact is changed.
preflight_writable_directory() {
  local directory="$1" label="$2" cursor next probe
  cursor="$directory"
  while [ ! -e "$cursor" ] && [ ! -L "$cursor" ]; do
    [ "$cursor" != "/" ] || break
    next="${cursor%/*}"
    if [ "$next" = "$cursor" ]; then
      cursor="."
    else
      cursor="${next:-/}"
    fi
  done
  [ -d "$cursor" ] && [ ! -L "$cursor" ] || {
    error "$label has no safe writable directory ancestor: $directory"
    return 1
  }
  probe="$(mktemp -d "$cursor/.skill-commons-write-probe.XXXXXX" 2>/dev/null)" || {
    error "$label is not writable: $cursor"
    return 1
  }
  rmdir "$probe" || {
    error "$label write probe could not be removed: $probe"
    return 1
  }
}

preflight_writable_file_parent() {
  local file="$1" label="$2"
  preflight_writable_directory "${file%/*}" "$label"
}

cursor_rule_is_managed() {
  local file="$1" marker_count always_count
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  marker_count="$(grep -Ec '^<!-- skill-commons-stamp: [a-f0-9]{12} -->$' "$file" 2>/dev/null || true)"
  always_count="$(grep -Fxc 'alwaysApply: true' "$file" 2>/dev/null || true)"
  [ "$marker_count" = 1 ] && [ "$always_count" = 1 ]
}

# Platform selection is convergent only when no previously managed adapter is
# hidden by a shrunk manifest. Fail before mutation and require an explicit
# uninstall/re-onboard migration instead of silently leaving active residue.
reject_deselected_managed_adapters() {
  local project_root="$1" platforms="$2" stale="" claude_safe=0 codex_safe=0 cursor_safe=0

  if platform_is_selected "$platforms" codex || platform_is_selected "$platforms" cursor; then
    validate_regular_candidate "$project_root/AGENTS.md" "managed adapter candidate" || return 1
  fi
  if platform_is_selected "$platforms" claude-code; then
    validate_regular_candidate "$project_root/CLAUDE.md" "managed adapter candidate" || return 1
  fi

  if [ -d "$project_root/.claude" ] && [ ! -L "$project_root/.claude" ]; then
    claude_safe=1
    if platform_is_selected "$platforms" claude-code; then
      validate_regular_candidate "$project_root/.claude/settings.json" "managed adapter candidate" || return 1
    fi
    if [ -d "$project_root/.claude/skills" ] && [ ! -L "$project_root/.claude/skills" ]; then
      if platform_is_selected "$platforms" claude-code; then
        validate_regular_candidate "$project_root/.claude/skills/$OWNERSHIP_FILE" "managed adapter candidate" || return 1
      fi
    fi
  fi
  if [ -d "$project_root/.codex" ] && [ ! -L "$project_root/.codex" ]; then
    codex_safe=1
    if [ -d "$project_root/.codex/skills" ] && [ ! -L "$project_root/.codex/skills" ]; then
      if platform_is_selected "$platforms" codex; then
        validate_regular_candidate "$project_root/.codex/skills/$OWNERSHIP_FILE" "managed adapter candidate" || return 1
      fi
    fi
  fi
  if [ -d "$project_root/.cursor" ] && [ ! -L "$project_root/.cursor" ] && \
     [ -d "$project_root/.cursor/rules" ] && [ ! -L "$project_root/.cursor/rules" ]; then
    cursor_safe=1
    if platform_is_selected "$platforms" cursor; then
      validate_regular_candidate "$project_root/.cursor/rules/skill-commons.mdc" "managed adapter candidate" || return 1
    fi
  fi

  if ! platform_is_selected "$platforms" claude-code; then
    if { [ "$claude_safe" = 1 ] && [ -f "$project_root/.claude/skills/$OWNERSHIP_FILE" ] && [ ! -L "$project_root/.claude/skills/$OWNERSHIP_FILE" ]; } || \
       { [ -f "$project_root/CLAUDE.md" ] && [ ! -L "$project_root/CLAUDE.md" ] && grep -Fq '<!-- skill-commons:start ' "$project_root/CLAUDE.md"; } || \
       { [ "$claude_safe" = 1 ] && [ -f "$project_root/.claude/settings.json" ] && [ ! -L "$project_root/.claude/settings.json" ] && grep -Fq '# skill-commons-managed' "$project_root/.claude/settings.json"; }; then
      stale="${stale:+$stale }claude-code"
    fi
  fi
  if ! platform_is_selected "$platforms" codex && \
     [ "$codex_safe" = 1 ] && [ -f "$project_root/.codex/skills/$OWNERSHIP_FILE" ] && [ ! -L "$project_root/.codex/skills/$OWNERSHIP_FILE" ]; then
    stale="${stale:+$stale }codex"
  fi
  if ! platform_is_selected "$platforms" cursor && \
     [ "$cursor_safe" = 1 ] && cursor_rule_is_managed "$project_root/.cursor/rules/skill-commons.mdc"; then
    stale="${stale:+$stale }cursor"
  fi
  if ! platform_is_selected "$platforms" codex && \
     ! platform_is_selected "$platforms" cursor && \
     [ -f "$project_root/AGENTS.md" ] && [ ! -L "$project_root/AGENTS.md" ] && \
     grep -Fq '<!-- skill-commons:start ' "$project_root/AGENTS.md"; then
    stale="${stale:+$stale }agents-adapter"
  fi

  if [ -n "$stale" ]; then
    error "managed artifacts exist for deselected platform(s): $stale; restore the previous platform selection, run manage.sh uninstall, then select and onboard the desired platforms"
    return 1
  fi
}

validate_project_components() {
  local target="$1" relative current part
  [ -n "${PROJECT_ROOT_GUARD:-}" ] || return 0
  case "$target" in
    "$PROJECT_ROOT_GUARD/.claude/skills"|"$PROJECT_ROOT_GUARD/.codex/skills"|"$PROJECT_ROOT_GUARD/.agents/skills") ;;
    *) error "target is not a recognized skill root for $PROJECT_ROOT_GUARD: $target"; return 1 ;;
  esac
  relative="${target#"$PROJECT_ROOT_GUARD"/}"
  current="$PROJECT_ROOT_GUARD"
  local old_ifs="$IFS"
  IFS='/'
  read -r -a parts <<< "$relative"
  IFS="$old_ifs"
  for part in "${parts[@]}"; do
    current="$current/$part"
    if [ -L "$current" ]; then
      error "project skill-root component is a symlink: $current"
      return 1
    fi
  done
}

validate_target_base() {
  local target="$1"
  [ "$target" != "/" ] || { error "refusing generation target /"; return 1; }
  if [ "$target" = "$ROOT" ] || [[ "$ROOT" == "$target/"* ]]; then
    error "generation target would contain the source root: $target"
    return 1
  fi
  if [[ "$target" == "$ROOT/"* ]]; then
    case "$target" in
      "$ROOT/.claude/skills"|"$ROOT/.codex/skills"|"$ROOT/.agents/skills") ;;
      *) error "target inside source root is not a generated skill root: $target"; return 1 ;;
    esac
  fi
  [ ! -L "$target" ] || { error "generation target is a symlink: $target"; return 1; }
  if [ -e "$target" ] && [ ! -d "$target" ]; then
    error "generation target is not a directory: $target"
    return 1
  fi
  validate_project_components "$target"
}

valid_owned_record() {
  local kind="$1" relative="$2"
  case "$kind" in
    D) [[ "$relative" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ;;
    F) [[ "$relative" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$|^scripts/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ;;
    *) return 1 ;;
  esac
}

validate_ledger() {
  local ledger="$1" seen="$2" header kind relative extra
  if [ -L "$ledger" ] || { [ -e "$ledger" ] && [ ! -f "$ledger" ]; }; then
    error "ownership ledger is not a regular file: $ledger"
    return 1
  fi
  [ -f "$ledger" ] || return 0
  : > "$seen"
  IFS= read -r header < "$ledger" || { error "empty ownership ledger: $ledger"; return 1; }
  [ "$header" = "$OWNERSHIP_HEADER" ] || { error "unsupported ownership ledger schema: $ledger"; return 1; }
  while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
    [ -n "${kind:-}${relative:-}${extra:-}" ] || continue
    [ -z "${extra:-}" ] || { error "malformed ownership record in $ledger"; return 1; }
    valid_owned_record "$kind" "$relative" || { error "unsafe ownership record in $ledger: $kind $relative"; return 1; }
    if grep -Fqx "$relative" "$seen"; then
      error "duplicate ownership path in $ledger: $relative"
      return 1
    fi
    printf '%s\n' "$relative" >> "$seen"
  done < <(tail -n +2 "$ledger")
}

ledger_owns() {
  local ledger="$1" kind="$2" relative="$3"
  [ -f "$ledger" ] || return 1
  grep -Fqx "$(printf '%s\t%s' "$kind" "$relative")" "$ledger"
}

validate_managed_path() {
  local target="$1" kind="$2" relative="$3" current="$target" part old_ifs="$IFS" index=0
  IFS='/'
  read -r -a components <<< "$relative"
  IFS="$old_ifs"
  for part in "${components[@]}"; do
    index=$((index + 1))
    current="$current/$part"
    if [ -L "$current" ]; then
      error "managed path is a symlink: $current"
      return 1
    fi
    if [ "$index" -lt "${#components[@]}" ] && [ -e "$current" ] && [ ! -d "$current" ]; then
      error "managed path parent is not a directory: $current"
      return 1
    fi
  done
  if [ -e "$current" ]; then
    case "$kind" in
      D) [ -d "$current" ] || { error "managed directory changed type: $current"; return 1; } ;;
      F) [ -f "$current" ] || { error "managed file changed type: $current"; return 1; } ;;
    esac
  fi
}

preflight_owned_ledger() {
  local target="$1" ledger="$2" seen="$3" kind relative extra
  [ -d "$target" ] && [ ! -L "$target" ] || { error "generated target is missing or unsafe: $target"; return 1; }
  [ -f "$ledger" ] || { error "ownership ledger is missing: $ledger"; return 1; }
  validate_ledger "$ledger" "$seen" || return 1
  while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
    [ -n "${kind:-}${relative:-}" ] || continue
    validate_managed_path "$target" "$kind" "$relative" || return 1
    [ -e "$target/$relative" ] || { error "owned generated unit is missing: $target/$relative"; return 1; }
  done < <(tail -n +2 "$ledger")
}

same_payload() {
  local kind="$1" expected="$2" actual="$3"
  if [ "$kind" = D ]; then
    [ -d "$actual" ] && [ ! -L "$actual" ] && diff -qr "$expected" "$actual" >/dev/null
  else
    [ -f "$actual" ] && [ ! -L "$actual" ] && cmp -s "$expected" "$actual"
  fi
}

# Shared files are generated for every delivery mode. Keep their inventory in
# this library so generation and management cannot silently disagree about the
# exact D/F ownership set.
skill_commons_shared_fragments() {
  printf '%s\n' \
    ARTIFACTS.md \
    GATE-PACKAGE.md \
    graph-context-check.md \
    SOURCES.md \
    CHECKLIST-CONVENTION.md \
    prd-template.md \
    protocol-registry.json \
    profiles.json
}

skill_commons_shared_scripts() {
  printf '%s\n' \
    manifest-stack.sh \
    run-gate.sh \
    work-items.sh \
    work_items.py \
    check-prd.py \
    check_protocol_registry.py
}

write_expected_ownership_ledger() {
  # $1 = source root, $2 = newline-delimited selected skills, $3 = output
  local root="$1" selected_skills="$2" output="$3" body="$3.body" name relative
  : > "$body"
  while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    [ -f "$root/$name/SKILL.md" ] || {
      error "selected skill source is missing: $root/$name/SKILL.md"
      rm -f -- "$body"
      return 1
    }
    printf 'D\t%s\n' "$name" >> "$body"
  done <<< "$selected_skills"
  while IFS= read -r relative || [ -n "$relative" ]; do
    [ -n "$relative" ] || continue
    [ ! -f "$root/$relative" ] || printf 'F\t%s\n' "$relative" >> "$body"
  done < <(skill_commons_shared_fragments)
  while IFS= read -r relative || [ -n "$relative" ]; do
    [ -n "$relative" ] || continue
    [ -f "$root/scripts/$relative" ] || {
      error "missing shared runtime helper: $root/scripts/$relative"
      rm -f -- "$body"
      return 1
    }
    printf 'F\tscripts/%s\n' "$relative" >> "$body"
  done < <(skill_commons_shared_scripts)
  {
    printf '%s\n' "$OWNERSHIP_HEADER"
    LC_ALL=C sort "$body"
  } > "$output"
  rm -f -- "$body"
}

ownership_lock_path() {
  local target="$1" lock_key
  lock_key="$(printf '%s' "$target" | cksum | awk '{print $1}')"
  # Target mutation must serialize across terminals, desktop agents, and hooks
  # even when their process-local TMPDIR values differ.
  printf '/tmp/skill-commons-generate-%s-%s.lock' "$(id -u)" "$lock_key"
}

# Serialize the installation as one unit: shims, hooks/rules, generated roots,
# and their ledgers must never be published or removed by overlapping commands.
# Direct generate.sh calls intentionally keep using only target-local locks.
project_install_lock_path() {
  local project_root="$1" lock_key
  lock_key="$(printf '%s' "$project_root" | cksum | awk '{print $1}')"
  # This namespace must be identical for terminal, desktop-agent, and hook
  # processes even when their TMPDIR values differ.
  printf '/tmp/skill-commons-install-%s-%s.lock' "$(id -u)" "$lock_key"
}

# Only call after every target and ledger has passed preflight_owned_ledger().
remove_preflighted_owned_units() {
  local target="$1" ledger="$2" kind relative extra
  while IFS=$'\t' read -r kind relative extra || [ -n "${kind:-}${relative:-}${extra:-}" ]; do
    [ -n "${kind:-}${relative:-}" ] || continue
    rm -rf -- "$target/$relative"
  done < <(tail -n +2 "$ledger")
  rm -f -- "$ledger"
}
