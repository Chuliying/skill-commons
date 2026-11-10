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

derive_scope_roots() {
  # $1 = project root. Prints "<source_roots>|<tests_root>" from tracked top-level
  # directories with conventional names; an empty side means no candidate was found.
  local root="$1" dirs name src="" tst=""
  dirs="$(git -C "$root" ls-files 2>/dev/null | awk -F/ 'NF > 1 { print $1 }' | sort -u)"
  [ -n "$dirs" ] || dirs="$(cd "$root" && find . -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sed 's#^\./##' | sort)"
  for name in src app lib api server client packages cmd internal pages components; do
    printf '%s\n' "$dirs" | grep -qx "$name" && src="${src:+$src,}$name"
  done
  for name in tests test __tests__ spec e2e; do
    printf '%s\n' "$dirs" | grep -qx "$name" && tst="${tst:+$tst,}$name"
  done
  printf '%s|%s' "$src" "$tst"
}

scope_coverage() {
  # $1 = project root, $2 = comma-separated roots. Prints "<code files under roots> <all code files>".
  local root="$1" roots="$2" files
  files="$(git -C "$root" ls-files 2>/dev/null | grep -E '\.(py|js|jsx|ts|tsx|mjs|cjs|go|rs|rb|java|kt|swift|c|cc|cpp|h|hpp|cs|php|vue|svelte|ex|exs|scala|sh)$')"
  ROOTS="$roots" python3 -c '
import os, sys
roots = [r for r in os.environ["ROOTS"].split(",") if r]
files = [f for f in sys.stdin.read().splitlines() if f]
inside = sum(1 for f in files if any(f == r or f.startswith(r + "/") for r in roots))
print(inside, len(files))' <<< "$files"
}

derive_test_cmd() {
  # $1 = project root. Prints a test command from conventional project files, or nothing.
  # Order: a real package.json test script, Go, Rust, pytest configuration, unittest-style
  # test files, then a Makefile test target.
  local root="$1" files script runner
  files="$(git -C "$root" ls-files 2>/dev/null)"
  [ -n "$files" ] || files="$(cd "$root" && find . -type f ! -path './.git/*' ! -path '*/node_modules/*' | sed 's#^\./##')"
  if [ -f "$root/package.json" ]; then
    script="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("scripts",{}).get("test",""))' "$root/package.json" 2>/dev/null)"
    if [ -n "$script" ] && ! printf '%s' "$script" | grep -q 'no test specified'; then
      runner=npm
      [ -f "$root/pnpm-lock.yaml" ] && runner=pnpm
      [ -f "$root/yarn.lock" ] && runner=yarn
      [ -f "$root/bun.lockb" ] || [ -f "$root/bun.lock" ] && runner=bun
      printf '%s test' "$runner"; return 0
    fi
  fi
  [ -f "$root/go.mod" ] && { printf 'go test ./...'; return 0; }
  [ -f "$root/Cargo.toml" ] && { printf 'cargo test'; return 0; }
  if [ -f "$root/pytest.ini" ] || [ -f "$root/conftest.py" ] \
     || grep -qs '^\[tool\.pytest' "$root/pyproject.toml" || grep -qs '^\[tool:pytest\]' "$root/setup.cfg"; then
    printf 'python3 -m pytest'; return 0
  fi
  if printf '%s\n' "$files" | grep -Eq '^test_[^/]*\.py$'; then
    printf 'python3 -m unittest'; return 0
  fi
  if printf '%s\n' "$files" | grep -Eq '^tests/(.*/)?test_[^/]*\.py$'; then
    printf 'python3 -m unittest discover -s tests'; return 0
  fi
  if [ -f "$root/Makefile" ] && grep -Eq '^test:' "$root/Makefile"; then
    printf 'make test'; return 0
  fi
  return 0
}

report_missing_selection() {
  # An existing manifest that predates skill-commons lacks the selection keys. Name every
  # missing key at once, with lines to paste, instead of failing on one key per run.
  local manifest="$1" platforms="$2" legacy="$3" mode="$4" missing=()
  [ -n "$platforms" ] || { echo "platform selection is required" >&2; missing+=("- platforms: codex"); }
  if [ -z "$legacy" ] && [ -z "$mode" ]; then
    echo "delivery mode is required" >&2
    missing+=("- delivery_mode: personal")
  fi
  [ "${#missing[@]}" -eq 0 ] && return 0
  echo "add these lines to $manifest, then run the same command again:" >&2
  printf '%s\n' "${missing[@]}" "- capability_packs: optional" >&2
  echo "platforms: any of claude-code, cursor, codex. delivery_mode: personal or team-sprint." >&2
  echo "capability_packs is recommended: optional adds to-prd and the onboarder." >&2
  return 2
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
