#!/usr/bin/env bash
# Manifest-aware heuristic secret preflight. Execute from the consuming repo root.

set -u -o pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: bash scan-secrets.sh [target-dir]" >&2
  echo "FAIL: expected at most one target directory" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_HELPER="$SCRIPT_DIR/../../scripts/manifest-stack.sh"
if [[ ! -r "$STACK_HELPER" ]]; then
  echo "FAIL: manifest stack helper not found: $STACK_HELPER" >&2
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

if [[ $# -eq 1 ]]; then
  targets=("$1")
else
  read -r -a targets <<< "$(manifest_list source_roots src)"
fi
read -r -a extensions <<< "$(manifest_list source_extensions 'ts tsx js jsx json py')"
package_manager="$(manifest_stack_value package_manager)"
[[ -z "$package_manager" ]] && package_manager="not-declared"
framework="$(manifest_stack_value framework)"
[[ -z "$framework" ]] && framework="not-declared"

git_workspace="$(git rev-parse --is-inside-work-tree 2>/dev/null)"
git_workspace_rc=$?
if [[ "$git_workspace_rc" -ne 0 || "$git_workspace" != "true" ]]; then
  echo "FAIL: secret preflight requires a Git worktree" >&2
  exit 1
fi
git_root_raw="$(git rev-parse --show-toplevel 2>/dev/null)"
git_root_rc=$?
if [[ "$git_root_rc" -ne 0 || -z "$git_root_raw" ]]; then
  echo "FAIL: cannot resolve the Git worktree root" >&2
  exit 1
fi
git_root="$(cd "$git_root_raw" 2>/dev/null && pwd -P)"
if [[ -z "$git_root" ]]; then
  echo "FAIL: cannot canonicalize the Git worktree root" >&2
  exit 1
fi

target_errors=0
if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "FAIL: no scan target was configured" >&2
  target_errors=$((target_errors + 1))
fi
for target_index in "${!targets[@]}"; do
  target="${targets[$target_index]}"
  while [[ "$target" != "/" && "$target" == */ ]]; do
    target="${target%/}"
  done
  targets[$target_index]="$target"
  target_canonical=""
  if [[ -z "$target" ]]; then
    echo "FAIL: scan target does not exist: ${target:-<empty>}" >&2
    target_errors=$((target_errors + 1))
  elif [[ -L "$target" ]]; then
    echo "FAIL: scan target must not be a symlink: $target" >&2
    target_errors=$((target_errors + 1))
  elif [[ ! -e "$target" ]]; then
    echo "FAIL: scan target does not exist: $target" >&2
    target_errors=$((target_errors + 1))
  elif [[ ! -d "$target" ]]; then
    echo "FAIL: scan target is not a directory: $target" >&2
    target_errors=$((target_errors + 1))
  elif [[ ! -r "$target" || ! -x "$target" ]]; then
    echo "FAIL: scan target is not readable and traversable: $target" >&2
    target_errors=$((target_errors + 1))
  else
    target_canonical="$(cd "$target" 2>/dev/null && pwd -P)"
    if [[ -z "$target_canonical" ]]; then
      echo "FAIL: cannot canonicalize scan target: $target" >&2
      target_errors=$((target_errors + 1))
    elif [[ "$git_root" != "/" && "$target_canonical" != "$git_root" && "$target_canonical" != "$git_root/"* ]]; then
      echo "FAIL: scan target resolves outside the Git worktree: $target" >&2
      target_errors=$((target_errors + 1))
    fi
  fi
done
if [[ "$target_errors" -gt 0 ]]; then
  exit "$target_errors"
fi

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
      value = lowered
      fallback = lowered
      sub(/^.*([|][|]|[[:space:]]or[[:space:]])[[:space:]]*["\047]/, "", fallback)
      if (fallback != lowered) {
        value = fallback
      } else {
        sub(/^.*(api_key|apikey|api-key|secret_key|secret-key|private_key|password|passwd|bearer|access_token|refresh_token|secret|token)[[:space:]]*[:=][[:space:]]*["\047]/, "", value)
      }
      sub(/["\047].*$/, "", value)
      if (value ~ /process\.env|os\.environ/) next
      if (value ~ /^(your-|placeholder([._-]|$)|example([._-]|$)|test([._-]|$)|mock([._-]|$)|fake([._-]|$)|changeme([._-]|$))/) next
      print
    }
  '
}

filter_staged_secret_candidates() {
  filter_hardcoded_secret_candidates
}

redact_file_matches() {
  local category="$1"
  awk -v category="$category" '
    {
      if (match($0, /:[0-9]+:/)) {
        print substr($0, 1, RSTART + RLENGTH - 1) "[" category " candidate redacted]"
      } else {
        print "[" category " candidate redacted]"
      }
    }
  '
}

annotate_staged_additions() {
  awk '
    /^diff --git / {
      in_hunk = 0
      next
    }
    /^\+\+\+ b\// && !in_hunk {
      path = substr($0, 7)
      next
    }
    /^@@ / {
      in_hunk = 1
      split($0, header, " ")
      new_range = header[3]
      sub(/^\+/, "", new_range)
      split(new_range, range_parts, ",")
      new_line = range_parts[1] + 0
      next
    }
    /^\+/ && in_hunk {
      print path ":" new_line ":" substr($0, 2)
      new_line++
    }
  '
}

include_args=()
for extension in "${extensions[@]}"; do
  extension="${extension#.}"
  include_args+=(--include="*.$extension")
done

secret_name_re='(api_key|apikey|api-key|secret_key|secret-key|private_key|password|passwd|bearer|access_token|refresh_token)'
direct_secret_re="${secret_name_re}[[:space:]]*[:=][[:space:]]*['\"][^'\"]{6,}['\"]"
fallback_secret_re="${secret_name_re}[[:space:]]*[:=][^[:cntrl:]]{0,160}(process\\.env|os\\.environ)[^[:cntrl:]]{0,160}([|][|]|[[:space:]]or[[:space:]])[[:space:]]*['\"][^'\"]{6,}['\"]"
hardcoded_secret_re="(${direct_secret_re}|${fallback_secret_re})"
staged_secret_name_re='(api_key|secret|password|token)'
staged_direct_secret_re="${staged_secret_name_re}[[:space:]]*[:=][[:space:]]*['\"][^'\"]{6,}['\"]"
staged_fallback_secret_re="${staged_secret_name_re}[[:space:]]*[:=][^[:cntrl:]]{0,160}(process\\.env|os\\.environ)[^[:cntrl:]]{0,160}([|][|]|[[:space:]]or[[:space:]])[[:space:]]*['\"][^'\"]{6,}['\"]"
staged_hardcoded_secret_re="(${staged_direct_secret_re}|${staged_fallback_secret_re})"

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
echo "Secret preflight targets: ${targets[*]}"
echo "Secret scan extensions: ${extensions[*]}"
echo "Manifest package manager: $package_manager"
echo "Manifest framework: $framework"

secrets="$(grep -riEn "${include_args[@]}" "${exclude_args[@]}" \
  "$hardcoded_secret_re" \
  -- "${targets[@]}" 2>&1 \
  | filter_hardcoded_secret_candidates)"
secrets_rc=$?
case "$secrets_rc" in
  0)
    if [[ -n "$secrets" ]]; then
      echo "FAIL: hard-coded secrets found"
      printf '%s\n' "$secrets" | redact_file_matches "hard-coded secret"
      issues=$((issues + 1))
    else
      echo "CLEAR: no hard-coded secret candidates"
    fi
    ;;
  1)
    echo "CLEAR: no hard-coded secret candidates"
    ;;
  *)
    echo "FAIL: hard-coded secret grep failed (exit $secrets_rc)"
    issues=$((issues + 1))
    ;;
esac

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
  client_secrets="$(grep -rEn "${include_args[@]}" "${exclude_args[@]}" \
    "($prefix_regex).*(KEY|SECRET|TOKEN|PASSWORD|AUTH)" -- "${targets[@]}" 2>&1)"
  client_rc=$?
  case "$client_rc" in
    0)
      echo "FAIL: sensitive client-exposed variables found"
      printf '%s\n' "$client_secrets" | redact_file_matches "client-exposed env"
      issues=$((issues + 1))
      ;;
    1)
      echo "CLEAR: no sensitive client-exposed variable candidates"
      ;;
    *)
      echo "FAIL: client-exposed variable grep failed (exit $client_rc)"
      issues=$((issues + 1))
      ;;
  esac
elif [[ "$ui_capability" = "false" ]]; then
  echo "N/A: client-prefix scan N/A (has_ui=false)"
else
  echo "FAIL: has_ui must be true or false"
  issues=$((issues + 1))
fi

log_secrets="$(grep -riEn "${include_args[@]}" "${exclude_args[@]}" \
  "(console\.(log|info|warn|error)|print\(|logging\.).*[^[:alnum:]](token|key|secret|password|auth)([^[:alnum:]]|$)" \
  -- "${targets[@]}" 2>&1)"
log_rc=$?
case "$log_rc" in
  0)
    echo "WARN: review possible secrets in logs"
    printf '%s\n' "$log_secrets" | redact_file_matches "secret-log"
    ;;
  1)
    echo "CLEAR: no obvious secret-log candidates"
    ;;
  *)
    echo "FAIL: secret-log grep failed (exit $log_rc)"
    issues=$((issues + 1))
    ;;
esac

env_ignore_output="$(git check-ignore -v -- .env 2>&1)"
env_ignore_rc=$?
case "$env_ignore_rc" in
  0)
    env_ignore_pattern="$(printf '%s\n' "$env_ignore_output" | awk -F '\t' '
      NR == 1 {
        metadata = $1
        sub(/^.*:[0-9]+:/, "", metadata)
        print metadata
      }
    ')"
    if [[ -n "$env_ignore_pattern" && "$env_ignore_pattern" != !* ]]; then
      echo "CLEAR: .env is excluded from git"
    else
      echo "FAIL: .env is not excluded from git"
      issues=$((issues + 1))
    fi
    ;;
  1)
    echo "FAIL: .env is not excluded from git"
    issues=$((issues + 1))
    ;;
  *)
    echo "FAIL: git check-ignore failed for .env (exit $env_ignore_rc)"
    [[ -n "$env_ignore_output" ]] && echo "$env_ignore_output"
    issues=$((issues + 1))
    ;;
esac

staged_diff="$(git diff --cached --no-ext-diff --unified=0 --no-color -- 2>&1)"
staged_diff_rc=$?
if [[ "$staged_diff_rc" -ne 0 ]]; then
  echo "FAIL: staged diff failed (exit $staged_diff_rc)"
  issues=$((issues + 1))
else
  staged_secrets="$(printf '%s\n' "$staged_diff" \
    | annotate_staged_additions \
    | grep -iE ":[0-9]+:.*$staged_hardcoded_secret_re" 2>&1 \
    | filter_staged_secret_candidates)"
  staged_grep_rc=$?
  case "$staged_grep_rc" in
    0)
      if [[ -n "$staged_secrets" ]]; then
        echo "FAIL: secret found in staged changes"
        printf '%s\n' "$staged_secrets" | redact_file_matches "staged secret"
        issues=$((issues + 1))
      else
        echo "CLEAR: no staged secret candidates"
      fi
      ;;
    1)
      echo "CLEAR: no staged secret candidates"
      ;;
    *)
      echo "FAIL: staged secret grep failed (exit $staged_grep_rc)"
      issues=$((issues + 1))
      ;;
  esac
fi

if [[ "$issues" -eq 0 ]]; then
  echo "Secret preflight result: no blocking heuristic findings"
else
  echo "Secret preflight result: $issues blocking finding group(s)"
fi
exit "$issues"
