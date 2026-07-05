#!/bin/bash
# verify.sh — verification-before-completion skill
# 執行完整 CI 驗證並輸出結構化摘要
# Usage: bash scripts/verify.sh [--skip-test]

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_HELPER="$SCRIPT_DIR/../../scripts/manifest-stack.sh"
if [[ ! -r "$STACK_HELPER" ]]; then
  echo "❌ manifest stack helper not found: $STACK_HELPER"
  exit 1
fi
# shellcheck source=../../scripts/manifest-stack.sh
source "$STACK_HELPER"

PASS="✅"
FAIL="❌"
SKIP="⏩"
EXIT_CODE=0

echo ""
echo "══════════════════════════════════════════"
echo "  Verification Before Completion"
echo "══════════════════════════════════════════"
echo ""

# ── Type Check ──────────────────────────────
echo "▶ Running type-check..."
typed_contracts="$(manifest_stack_capability typed_contracts 2>/dev/null || printf invalid)"
if [[ "$typed_contracts" = "false" ]]; then
  echo "$SKIP type-check N/A (typed_contracts=false)"
elif [[ "$typed_contracts" = "invalid" ]]; then
  echo "$FAIL typed_contracts must be true or false"
  EXIT_CODE=1
elif run_manifest_stack_command typecheck_cmd type-check required 2>&1; then
  echo "$PASS type-check PASSED"
else
  echo "$FAIL type-check FAILED"
  EXIT_CODE=1
fi
echo ""

# ── Lint ─────────────────────────────────────
echo "▶ Running lint..."
if run_manifest_stack_command lint_cmd lint optional 2>&1; then
  if [[ "$MANIFEST_STACK_STATUS" = "missing-optional" ]]; then
    echo "$SKIP lint SKIPPED"
  else
    echo "$PASS lint PASSED"
  fi
else
  echo "$FAIL lint FAILED"
  EXIT_CODE=1
fi
echo ""

# ── Tests ────────────────────────────────────
if [[ "${1:-}" != "--skip-test" ]]; then
  echo "▶ Running tests..."
  if run_manifest_stack_command test_cmd tests required 2>&1; then
    echo "$PASS tests PASSED"
  else
    echo "$FAIL tests FAILED"
    EXIT_CODE=1
  fi
else
  echo "$SKIP tests SKIPPED (--skip-test)"
fi
echo ""

# ── Summary ──────────────────────────────────
echo "══════════════════════════════════════════"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "$PASS ALL CHECKS PASSED — Safe to commit/PR"
else
  echo "$FAIL SOME CHECKS FAILED — Fix before claiming completion"
fi
echo "══════════════════════════════════════════"
echo ""

exit $EXIT_CODE
