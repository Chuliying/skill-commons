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

get_platforms() {
  local v; v="$(_manifest_value "$1" platforms)"
  [ -z "$v" ] && v="claude-code cursor codex"
  printf '%s' "$(echo "$v" | tr ',' ' ' | xargs)"
}

get_profile() {
  # Empty (key absent) = all skills, fully backward compatible.
  local v; v="$(_manifest_value "$1" profile)"
  printf '%s' "$(echo "$v" | xargs)"
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
