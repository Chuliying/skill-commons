#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

RECOVERY="$REPO/docs/work/skill-bundle-effect-benchmark/evidence-recovery.md"
EVALUATION="$REPO/docs/evaluation.md"

assert_file "$RECOVERY" "benchmark evidence recovery record exists"
assert_file "$EVALUATION" "public evaluation claim boundary exists"

if [ -f "$RECOVERY" ]; then
  recovery_text="$(cat "$RECOVERY")"
  assert_contains "$recovery_text" "No benchmark result was reconstructed" "recovery does not fabricate historical results"
  assert_contains "$recovery_text" "raw execution evidence: unavailable" "recovery states the missing raw-evidence boundary"
  assert_contains "$recovery_text" "deterministic reports: regenerated" "recovery separates reproducible repository evidence"
fi

if [ -f "$EVALUATION" ]; then
  evaluation_text="$(cat "$EVALUATION")"
  evaluation_flat="$(printf '%s' "$evaluation_text" | tr '\n' ' ')"
  assert_contains "$evaluation_flat" "not independently replayable evidence" "evaluation downgrades unrecoverable benchmark claims"
  assert_contains "$evaluation_flat" "all historical model-run figures in this document remain unverified narrative" "evaluation preserves the release claim boundary"
  assert_not_contains "$evaluation_text" "additionally retains the benchmark handoff" "evaluation removes the false private-retention claim"
fi

finish
