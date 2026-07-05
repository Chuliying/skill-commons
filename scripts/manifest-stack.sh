#!/usr/bin/env bash
# Read and execute ## Stack commands from the consuming repo manifest.

manifest_stack_file() {
  printf '%s' "${PROJECT_MANIFEST:-$PWD/.agent/project-manifest.md}"
}

manifest_stack_value() {
  local manifest key
  manifest="$(manifest_stack_file)"
  key="$1"
  [ -f "$manifest" ] || return 0
  sed -nE "s/^- *\`?${key}\`? *: *//p" "$manifest" | head -1 | tr -d '\r'
}

manifest_stack_capability() {
  local key value
  key="$1"
  value="$(manifest_stack_value "$key")"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$value" in
    true) printf 'true' ;;
    false|"") printf 'false' ;;
    *)
      echo "❌ manifest Stack.$key must be true or false (got: $value)" >&2
      return 2
      ;;
  esac
}

run_manifest_stack_command() {
  local key label required command
  MANIFEST_STACK_STATUS="configured"
  key="$1"
  label="$2"
  required="${3:-optional}"
  command="$(manifest_stack_value "$key")"

  if [ -z "$command" ]; then
    if [ "$required" = "required" ]; then
      MANIFEST_STACK_STATUS="missing-required"
      echo "❌ manifest Stack.$key is missing; ask the user or update .agent/project-manifest.md"
      return 1
    fi
    MANIFEST_STACK_STATUS="missing-optional"
    echo "⏩ $label skipped (manifest Stack.$key is not configured)"
    return 0
  fi

  echo "▶ Running $label: $command"
  bash -c "$command"
}
