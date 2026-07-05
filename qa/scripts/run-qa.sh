#!/bin/bash
# run-qa.sh — qa validate mode
# 委託 verify.sh 跑基礎 CI，再加上 E2E + QA spec 獨有邏輯
# Usage: bash scripts/run-qa.sh [qa-spec-file]

set -o pipefail

QA_SPEC="${1:-}"
PASS="✅"
FAIL="❌"
WARN="⚠️ "
EXIT_CODE=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/../../verification-before-completion/scripts/verify.sh"
STACK_HELPER="$SCRIPT_DIR/../../scripts/manifest-stack.sh"
if [[ ! -r "$STACK_HELPER" ]]; then
  echo "$FAIL manifest stack helper not found: $STACK_HELPER"
  exit 1
fi
# shellcheck source=../../scripts/manifest-stack.sh
source "$STACK_HELPER"

echo ""
echo "══════════════════════════════════════════"
echo "  QA Validator — Acceptance Test Runner"
echo "══════════════════════════════════════════"
echo ""

# ── Step 1-2: 委託 verify.sh 跑 type-check + lint + test ──
echo "▶ [1/3] Running base CI checks (via verify.sh)..."
echo ""
if [[ -x "$VERIFY_SCRIPT" ]]; then
  bash "$VERIFY_SCRIPT"
  if [[ $? -ne 0 ]]; then
    EXIT_CODE=1
  fi
else
  echo "$FAIL verify.sh not found; cannot run manifest-aware base checks"
  EXIT_CODE=1
fi
echo ""

# ── Step 3: E2E Tests (qa validate) ────────────────────
echo "▶ [2/3] E2E Tests..."
has_e2e="$(manifest_stack_capability has_e2e 2>/dev/null || printf invalid)"
if [[ "$has_e2e" = "false" ]]; then
  echo "⏩ E2E N/A (has_e2e=false)"
elif [[ "$has_e2e" = "invalid" ]]; then
  echo "$FAIL has_e2e must be true or false"
  EXIT_CODE=1
elif run_manifest_stack_command e2e_cmd "E2E tests" required 2>&1; then
  echo "$PASS E2E step complete"
else
  echo "$FAIL E2E tests FAILED"
  EXIT_CODE=1
fi
echo ""

# ── Step 4: QA Spec Checklist (qa validate) ────────────
echo "▶ [3/3] QA Spec Checklist..."
if [[ -n "$QA_SPEC" && -f "$QA_SPEC" ]]; then
  echo "   QA spec: $QA_SPEC"
  echo ""

  # 計算 checklist 項目數
  TOTAL=$(grep -cE "^(-|\*|\d+\.|^\[)" "$QA_SPEC" 2>/dev/null || echo "0")
  echo "   Found $TOTAL checklist items."
  echo "   → Please verify each acceptance criterion manually."
else
  echo "$WARN No QA spec provided. Pass <work_root>/<slug>/qa-plan.md as the first argument."
fi
echo ""

# ── Summary ──────────────────────────────────
echo "══════════════════════════════════════════"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "$PASS AUTOMATED CHECKS PASSED"
  echo "→ Complete manual QA checklist from spec file"
else
  echo "$FAIL AUTOMATED CHECKS FAILED"
  echo "→ Fix failures before QA sign-off"
fi
echo "══════════════════════════════════════════"
echo ""

exit $EXIT_CODE
