#!/bin/bash
# pre-merge.sh — finishing-a-development-branch skill
# 委託 verify.sh 執行 CI 流程，避免重複維護
# Usage: bash scripts/pre-merge.sh

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/../../verification-before-completion/scripts/verify.sh"

echo ""
echo "══════════════════════════════════════════"
echo "  Pre-Merge CI Check"
echo "══════════════════════════════════════════"
echo ""

# 優先使用共用的 verify.sh，避免重複維護
if [[ -x "$VERIFY_SCRIPT" ]]; then
  echo "▶ Delegating to verify.sh..."
  echo ""
  bash "$VERIFY_SCRIPT"
  EXIT_CODE=$?
else
  echo "⚠️  verify.sh not found at: $VERIFY_SCRIPT"
  echo "   Cannot verify safely without the manifest-aware runner."
  EXIT_CODE=1
fi

echo ""
echo "══════════════════════════════════════════"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ ALL CHECKS PASSED"
  echo "→ Proceed to Step 2: Confirm base branch"
else
  echo "❌ CI FAILED — Fix before merging"
  echo "→ DO NOT proceed to merge"
fi
echo "══════════════════════════════════════════"
echo ""

exit $EXIT_CODE
