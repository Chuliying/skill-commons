#!/usr/bin/env bash
# Manifest-aware deterministic gate runner. Execute from the consuming repo root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_HELPER="$SCRIPT_DIR/manifest-stack.sh"
if [[ ! -r "$STACK_HELPER" ]]; then
  echo "manifest stack helper not found: $STACK_HELPER" >&2
  exit 1
fi
# shellcheck source=manifest-stack.sh
source "$STACK_HELPER"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

gate_name="${1:-full}"
shift 2>/dev/null || true
target_files=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      target_files="${2:-}"
      shift 2
      ;;
    *) shift ;;
  esac
done

manifest_list() {
  local value
  value="$(manifest_stack_value "$1")"
  [[ -z "$value" ]] && value="$2"
  printf '%s' "$value" | tr ',' ' '
}

if [[ -n "$target_files" ]]; then
  read -r -a scan_targets <<< "$target_files"
else
  read -r -a scan_targets <<< "$(manifest_list source_roots src)"
fi
read -r -a source_extensions <<< "$(manifest_list source_extensions 'ts tsx js jsx')"
package_manager="$(manifest_stack_value package_manager)"
[[ -z "$package_manager" ]] && package_manager="not-declared"

include_args=()
for extension in "${source_extensions[@]}"; do
  extension="${extension#.}"
  include_args+=(--include="*.$extension")
done

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; GATE_FAILED=1; }
na() { echo "N/A: $1"; }
info() { echo -e "${BLUE}INFO${NC}: $1"; }
header() { echo -e "\n${BOLD}${YELLOW}=== $1 ===${NC}"; }

GATE_FAILED=0

capability_enabled() {
  local value
  if ! value="$(manifest_stack_capability "$1")"; then
    fail "invalid manifest capability: $1"
    return 1
  fi
  [[ "$value" = "true" ]]
}

run_configured_gate() {
  local key label required
  key="$1"
  label="$2"
  required="${3:-optional}"
  if run_manifest_stack_command "$key" "$label" "$required" 2>&1; then
    if [[ "$MANIFEST_STACK_STATUS" = "missing-optional" ]]; then
      na "$label (manifest Stack.$key is not configured)"
    else
      pass "$label"
    fi
  else
    fail "$label"
  fi
}

gate_design_token() {
  header "Design Token Gate"
  if ! capability_enabled has_ui; then
    na "design-token N/A (has_ui=false)"
    return
  fi
  info "targets: ${scan_targets[*]}"
  result=$(grep -rEn "text-\[#|bg-\[#|border-\[#|from-\[#|to-\[#" \
    "${scan_targets[@]}" "${include_args[@]}" 2>/dev/null \
    | grep -vE "test|spec|\.d\.ts" || true)
  if [[ -z "$result" ]]; then
    pass "no hard-coded color values"
  else
    fail "hard-coded color values found"
    echo "$result"
  fi
}

gate_code_hygiene() {
  header "Code Hygiene Gate"
  info "targets: ${scan_targets[*]}"
  info "extensions: ${source_extensions[*]}"

  result=$(grep -rEn "TODO|FIXME|XXX|HACK" \
    "${scan_targets[@]}" "${include_args[@]}" 2>/dev/null || true)
  if [[ -z "$result" ]]; then pass "no unfinished markers"; else fail "unfinished markers found"; echo "$result"; fi

  result=$(grep -rEn "test\.(only|skip)|it\.(only|skip)|describe\.(only|skip)|@pytest\.mark\.(only|skip)" \
    "${scan_targets[@]}" "${include_args[@]}" 2>/dev/null || true)
  if [[ -z "$result" ]]; then pass "no focused or skipped tests"; else fail "focused or skipped tests found"; echo "$result"; fi

  case " ${source_extensions[*]} " in
    *" js "*|*" jsx "*|*" ts "*|*" tsx "*)
      result=$(grep -rEn "console\.log" \
        "${scan_targets[@]}" "${include_args[@]}" 2>/dev/null \
        | grep -vE "test|spec|config|\.d\.ts" || true)
      if [[ -z "$result" ]]; then pass "no production console.log"; else fail "production console.log found"; echo "$result"; fi
      ;;
    *) na "console.log hygiene N/A (non-JS source extensions)" ;;
  esac

  if capability_enabled typed_contracts; then
    result=$(grep -rEn ": any\b" \
      "${scan_targets[@]}" "${include_args[@]}" 2>/dev/null \
      | grep -vE "test|spec|\.d\.ts" || true)
    if [[ -z "$result" ]]; then pass "no unbounded any types"; else fail "unbounded any types found"; echo "$result"; fi
  else
    na "typed hygiene N/A (typed_contracts=false)"
  fi
}

gate_type_check() {
  header "Typed Contract Gate"
  if ! capability_enabled typed_contracts; then
    na "type-check N/A (typed_contracts=false)"
    return
  fi
  run_configured_gate typecheck_cmd type-check required
}

gate_lint() {
  header "Lint Gate"
  run_configured_gate lint_cmd lint optional
}

gate_test() {
  header "Test Gate"
  run_configured_gate test_cmd tests required
}

gate_api_endpoints() {
  header "API Contract Gate"
  if ! capability_enabled has_api; then
    na "api-check N/A (has_api=false)"
    return
  fi
  run_configured_gate api_check_cmd api-check required
}

gate_full() {
  header "Full Gate Suite"
  info "manifest package manager: $package_manager"
  gate_type_check
  gate_lint
  gate_test
  gate_design_token
  gate_code_hygiene
}

case "$gate_name" in
  design-token) gate_design_token ;;
  code-hygiene) gate_code_hygiene ;;
  type-check) gate_type_check ;;
  lint) gate_lint ;;
  test) gate_test ;;
  api-endpoints) gate_api_endpoints ;;
  full) gate_full ;;
  *)
    echo "unknown gate: $gate_name" >&2
    echo "available: design-token | code-hygiene | type-check | lint | test | api-endpoints | full" >&2
    exit 1
    ;;
esac

echo ""
if [[ "$GATE_FAILED" -eq 0 ]]; then
  pass "all applicable gates passed"
  exit 0
fi
fail "one or more applicable gates failed"
exit 1
