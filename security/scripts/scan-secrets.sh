#!/usr/bin/env bash
# Manifest-aware secret scanner. Execute from the consuming repo root.

set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_HELPER="$SCRIPT_DIR/../../scripts/manifest-stack.sh"
if [[ ! -r "$STACK_HELPER" ]]; then
  echo "manifest stack helper not found: $STACK_HELPER" >&2
  exit 1
fi
# shellcheck source=../../scripts/manifest-stack.sh
source "$STACK_HELPER"

manifest_list() {
  local value
  value="$(manifest_stack_value "$1")"
  [[ -z "$value" ]] && value="$2"
  printf '%s' "$value" | tr ',' ' '
}

if [[ $# -gt 0 ]]; then
  targets=("$1")
else
  read -r -a targets <<< "$(manifest_list source_roots src)"
fi
read -r -a extensions <<< "$(manifest_list source_extensions 'ts tsx js jsx json py')"
package_manager="$(manifest_stack_value package_manager)"
[[ -z "$package_manager" ]] && package_manager="not-declared"
framework="$(manifest_stack_value framework)"
[[ -z "$framework" ]] && framework="not-declared"

client_env_prefixes() {
  local configured framework_lc
  configured="$(manifest_stack_value client_env_prefixes)"
  if [[ -n "$configured" ]]; then
    printf '%s' "$configured" | tr ',' ' '
    return 0
  fi

  framework_lc="$(printf '%s' "$framework" | tr '[:upper:]' '[:lower:]')"
  case "$framework_lc" in
    next|nextjs|next.js) printf 'NEXT_PUBLIC_' ;;
    vite|vite-react|react-vite) printf 'VITE_' ;;
    *) printf 'NEXT_PUBLIC_ VITE_' ;;
  esac
}

escape_ere_literal() {
  printf '%s' "$1" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g'
}

filter_hardcoded_secret_candidates() {
  awk '
    {
      content = $0
      sub(/^[^:]*:[0-9]+:/, "", content)
      lowered = tolower(content)
      if (lowered ~ /process\.env|os\.environ|your-/) next
      if (lowered ~ /(^|[^[:alnum:]_])(type|interface|placeholder|example|test|mock|fake)([^[:alnum:]_]|$)/) next
      if (lowered ~ /fixture_project/) next
      print
    }
  '
}

include_args=()
for extension in "${extensions[@]}"; do
  extension="${extension#.}"
  include_args+=(--include="*.$extension")
done

exclude_args=(
  --exclude-dir=.git
  --exclude-dir=.agents
  --exclude-dir=.claude
  --exclude-dir=.codex
  --exclude-dir=.cursor
  --exclude-dir=_archive
  --exclude-dir=node_modules
  --exclude-dir=__pycache__
  --exclude=scan-secrets.sh
  --exclude=nextjs-security-patterns.md
)

issues=0
echo "Secret scan targets: ${targets[*]}"
echo "Secret scan extensions: ${extensions[*]}"
echo "Manifest package manager: $package_manager"
echo "Manifest framework: $framework"

secrets=$(grep -rEn "${exclude_args[@]}" "${include_args[@]}" \
  "(api_key|apikey|api-key|secret_key|secret-key|private_key|password|passwd|bearer|access_token|refresh_token)[[:space:]]*[:=][[:space:]]*['\"][^'\"]{6,}['\"]" \
  "${targets[@]}" 2>/dev/null \
  | filter_hardcoded_secret_candidates || true)
if [[ -n "$secrets" ]]; then
  echo "FAIL: hard-coded secrets found"
  echo "$secrets"
  issues=$((issues + 1))
else
  echo "PASS: no hard-coded secrets"
fi

ui_capability="$(manifest_stack_capability has_ui 2>/dev/null || printf invalid)"
if [[ "$ui_capability" = "true" ]]; then
  read -r -a prefixes <<< "$(client_env_prefixes)"
  prefix_regex=""
  invalid_prefixes=()
  for prefix in "${prefixes[@]}"; do
    prefix="$(printf '%s' "$prefix" | xargs)"
    [[ -z "$prefix" ]] && continue
    if [[ ! "$prefix" =~ ^[A-Za-z_][A-Za-z0-9_]*_$ ]]; then
      invalid_prefixes+=("$prefix")
      continue
    fi
    escaped_prefix="$(escape_ere_literal "$prefix")"
    if [[ -z "$prefix_regex" ]]; then
      prefix_regex="$escaped_prefix"
    else
      prefix_regex="$prefix_regex|$escaped_prefix"
    fi
  done
  if [[ "${#invalid_prefixes[@]}" -gt 0 ]]; then
    echo "FAIL: invalid client_env_prefixes value(s): ${invalid_prefixes[*]}"
    issues=$((issues + 1))
  fi
  if [[ -z "$prefix_regex" ]]; then
    echo "FAIL: no valid client env prefixes configured for has_ui=true"
    issues=$((issues + 1))
    prefix_regex='a^'
  fi
  echo "Client env prefixes: ${prefixes[*]}"
  client_secrets=$(grep -rEn "${exclude_args[@]}" "${include_args[@]}" \
    "($prefix_regex).*(KEY|SECRET|TOKEN|PASSWORD|AUTH)" "${targets[@]}" 2>/dev/null || true)
  if [[ -n "$client_secrets" ]]; then
    echo "FAIL: sensitive client-exposed variables found"
    echo "$client_secrets"
    issues=$((issues + 1))
  else
    echo "PASS: no sensitive client-exposed variables"
  fi
elif [[ "$ui_capability" = "false" ]]; then
  echo "N/A: client-prefix scan N/A (has_ui=false)"
else
  echo "FAIL: has_ui must be true or false"
  issues=$((issues + 1))
fi

log_secrets=$(grep -rEn "${exclude_args[@]}" "${include_args[@]}" \
  "(console\.(log|info|warn|error)|print\(|logging\.).*(token|key|secret|password|auth)" \
  "${targets[@]}" 2>/dev/null || true)
if [[ -n "$log_secrets" ]]; then
  echo "WARN: review possible secrets in logs"
  echo "$log_secrets"
else
  echo "PASS: no obvious secrets in logs"
fi

if grep -q "\.env" .gitignore 2>/dev/null; then
  echo "PASS: .env is excluded from git"
else
  echo "FAIL: .env is not excluded from git"
  issues=$((issues + 1))
fi

staged_secrets=$(git diff --cached 2>/dev/null \
  | grep "^+" \
  | grep -iE "(api_key|secret|password|token)[[:space:]]*=[[:space:]]*['\"][^'\"]{6,}['\"]" \
  | grep -iv "process\.env\|os\.environ\|placeholder\|your-\|example" || true)
if [[ -n "$staged_secrets" ]]; then
  echo "FAIL: secret found in staged changes"
  echo "$staged_secrets"
  issues=$((issues + 1))
else
  echo "PASS: no secrets in staged changes"
fi

if [[ "$issues" -eq 0 ]]; then
  echo "PASS: secret scan passed"
else
  echo "FAIL: secret scan found $issues issue(s)"
fi
exit "$issues"
