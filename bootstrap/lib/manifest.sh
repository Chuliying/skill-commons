# Parse bootstrap settings from .agent/project-manifest.md. Source this file.

_manifest_value() {
  # $1 = manifest file, $2 = key -> prints value (empty if absent)
  [ -f "$1" ] || return 0
  grep -E "^- *$2 *:" "$1" 2>/dev/null | head -1 | sed -E "s/^- *$2 *: *//" | tr -d '\r'
}

get_submodule_path() {
  local v; v="$(_manifest_value "$1" submodule_path)"
  [ -z "$v" ] && v=".agent/skills/_shared"
  printf '%s' "$v"
}

validate_bootstrap_manifest_keys() {
  local manifest="$1" key count
  [ -f "$manifest" ] && [ ! -L "$manifest" ] || {
    echo "bootstrap manifest is missing or unsafe: $manifest" >&2
    return 2
  }
  for key in submodule_path platforms profile delivery_mode capability_packs; do
    count="$(grep -Ec "^- *$key *:" "$manifest" 2>/dev/null || true)"
    if [ "$count" -gt 1 ]; then
      echo "duplicate bootstrap key: $key" >&2
      return 2
    fi
  done
}

validate_submodule_path() {
  local value="$1" project_root="${2:-}" current part old_ifs
  [ -n "$value" ] || { echo "submodule_path is required" >&2; return 2; }
  case "$value" in
    /*) echo "submodule_path must be project-relative: $value" >&2; return 2 ;;
    *$'\n'*|*$'\r'*|*$'\t'*) echo "submodule_path contains control characters" >&2; return 2 ;;
  esac
  case "/$value/" in
    *"/../"*|*"/./"*) echo "submodule_path contains an unsafe path component: $value" >&2; return 2 ;;
  esac
  if [ -n "$project_root" ]; then
    current="$project_root"
    old_ifs="$IFS"
    IFS='/'
    read -r -a parts <<< "$value"
    IFS="$old_ifs"
    for part in "${parts[@]}"; do
      current="$current/$part"
      if [ -L "$current" ]; then
        echo "submodule_path component is a symlink: $current" >&2
        return 2
      fi
      if [ -e "$current" ] && [ ! -d "$current" ]; then
        echo "submodule_path component is not a directory: $current" >&2
        return 2
      fi
    done
  fi
}

get_platforms() {
  local v; v="$(_manifest_value "$1" platforms)"
  [ -z "$v" ] && v="claude-code cursor codex"
  printf '%s' "$(echo "$v" | tr ',' ' ' | xargs)"
}

get_explicit_platforms() {
  local v; v="$(_manifest_value "$1" platforms)"
  printf '%s' "$(printf '%s' "$v" | tr ',' ' ' | xargs)"
}

get_profile() {
  # Legacy compatibility only. An empty value never means all skills.
  local v; v="$(_manifest_value "$1" profile)"
  printf '%s' "$(printf '%s' "$v" | tr ',' ' ' | xargs)"
}

get_delivery_mode() {
  local v; v="$(_manifest_value "$1" delivery_mode)"
  printf '%s' "$(printf '%s' "$v" | tr ',' ' ' | xargs)"
}

get_capability_packs() {
  local v; v="$(_manifest_value "$1" capability_packs)"
  printf '%s' "$(printf '%s' "$v" | tr ',' ' ' | xargs)"
}

validate_platform_selection() {
  local value="$1" token seen="" tokens=()
  [ -n "$value" ] || { echo "platform selection is required" >&2; return 2; }
  read -r -a tokens <<< "$value"
  for token in "${tokens[@]}"; do
    case "$token" in claude-code|cursor|codex) ;; *) echo "unknown platform: $token" >&2; return 2 ;; esac
    case " $seen " in *" $token "*) echo "duplicate platform: $token" >&2; return 2 ;; esac
    seen="${seen:+$seen }$token"
  done
}

validate_profile_selection() {
  local legacy="$1" mode="$2" packs="$3" token mode_count=0 tokens=() seen=""
  if [ -n "$legacy" ] && { [ -n "$mode" ] || [ -n "$packs" ]; }; then
    echo "legacy profile cannot be combined with delivery_mode or capability_packs" >&2
    return 2
  fi
  if [ -n "$legacy" ]; then
    read -r -a tokens <<< "$legacy"
    for token in "${tokens[@]}"; do
      case "$token" in
        personal|team-sprint) mode_count=$((mode_count + 1)) ;;
        frontend|optional) ;;
        *) echo "invalid consuming profile token: $token" >&2; return 2 ;;
      esac
      case " $seen " in *" $token "*) echo "duplicate profile token: $token" >&2; return 2 ;; esac
      seen="${seen:+$seen }$token"
    done
    [ "$mode_count" -eq 1 ] || { echo "legacy profile requires exactly one delivery mode" >&2; return 2; }
    return 0
  fi
  case "$mode" in
    personal|team-sprint) ;;
    "") echo "delivery mode is required" >&2; return 2 ;;
    *) echo "unknown delivery mode: $mode" >&2; return 2 ;;
  esac
  [ -z "$packs" ] && return 0
  read -r -a tokens <<< "$packs"
  for token in "${tokens[@]}"; do
    case "$token" in frontend|optional) ;; *) echo "unknown capability pack: $token" >&2; return 2 ;; esac
    case " $seen " in *" $token "*) echo "duplicate capability pack: $token" >&2; return 2 ;; esac
    seen="${seen:+$seen }$token"
  done
}

get_stack_capability() {
  # Missing capability = false. Invalid values fail closed with exit 2.
  local v
  v="$(_manifest_value "$1" "$2")"
  v="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$v" in
    true) printf 'true' ;;
    false|"") printf 'false' ;;
    *)
      echo "invalid boolean capability $2=$v in $1" >&2
      return 2
      ;;
  esac
}
