#!/bin/bash
# verify.sh — verification-before-completion skill
# Runs the manifest's type-check, lint and tests and prints a structured summary
# Usage: bash scripts/verify.sh [--skip-test] [--work-item <slug> [--covers <file>#<ID>]...]
#   --work-item writes <work_root>/<slug>/verification.json with the result and a
#   content fingerprint, so project-status can tell when the result goes stale.
#   --covers binds named acceptance segments; without it, every AC- segment in the
#   item's prd.md and spec.md is bound.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_HELPER="$SCRIPT_DIR/../../scripts/manifest-stack.sh"
if [[ ! -r "$STACK_HELPER" ]]; then
  echo "❌ manifest stack helper not found: $STACK_HELPER"
  exit 1
fi
# shellcheck source=../../scripts/manifest-stack.sh
source "$STACK_HELPER"

SKIP_TESTS=0
WORK_ITEM=""
COVERS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-test) SKIP_TESTS=1 ;;
    --work-item)
      if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "❌ --work-item needs a work-item slug"
        exit 2
      fi
      WORK_ITEM="$2"; shift ;;
    --covers)
      if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "❌ --covers needs a segment reference such as prd.md#AC-002"
        exit 2
      fi
      COVERS+=(--covers "$2"); shift ;;
    *) echo "❌ unknown argument: $1"; exit 2 ;;
  esac
  shift
done
if [[ ${#COVERS[@]} -gt 0 && -z "$WORK_ITEM" ]]; then
  echo "❌ --covers needs --work-item"
  exit 2
fi
if [[ -n "$WORK_ITEM" && ! "$WORK_ITEM" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "❌ --work-item must be a work-item slug"
  exit 2
fi

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
PASS="✅"
FAIL="❌"
SKIP="⏩"
EXIT_CODE=0
RAN=0

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
  RAN=$((RAN + 1))
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
    RAN=$((RAN + 1))
    echo "$PASS lint PASSED"
  fi
else
  echo "$FAIL lint FAILED"
  EXIT_CODE=1
fi
echo ""

# ── Tests ────────────────────────────────────
TESTS_RAN=0
if [[ "$SKIP_TESTS" -eq 0 ]]; then
  echo "▶ Running tests..."
  if run_manifest_stack_command test_cmd tests required 2>&1; then
    RAN=$((RAN + 1))
    TESTS_RAN=1
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
if [[ $EXIT_CODE -eq 0 && $RAN -eq 0 ]]; then
  echo "$SKIP NO CHECKS EXECUTED — nothing was verified; this is not completion evidence"
elif [[ $EXIT_CODE -eq 0 ]]; then
  echo "$PASS ALL CHECKS PASSED — Safe to commit/PR"
else
  echo "$FAIL SOME CHECKS FAILED — Fix before claiming completion"
fi
echo "══════════════════════════════════════════"
echo ""

# ── Evidence ─────────────────────────────────
# Only a run whose tests executed and whose checks all passed is passing evidence.
if [[ -n "$WORK_ITEM" ]]; then
  if [[ $EXIT_CODE -ne 0 ]]; then
    RESULT=fail
  elif [[ $TESTS_RAN -eq 0 ]]; then
    RESULT=skipped
  else
    RESULT=pass
  fi
  if [[ "$RESULT" = "skipped" ]]; then
    echo "$SKIP tests did not run; recorded as skipped, which is not completion evidence"
  fi
  if ! SKILL_COMMONS_VERIFY_RUN=1 python3 "$SCRIPT_DIR/../../scripts/verification_evidence.py" record \
      --work-item "$WORK_ITEM" --result "$RESULT" --exit-code "$EXIT_CODE" \
      --checks "$RAN" --command-text "$(manifest_stack_value test_cmd)" --started-at "$STARTED_AT" ${COVERS[@]+"${COVERS[@]}"}; then
    echo "$FAIL could not record verification evidence"
    EXIT_CODE=1
  fi
fi

exit $EXIT_CODE
