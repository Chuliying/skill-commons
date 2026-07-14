#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rc=0
PUBLIC_SUITES="
  tests/test_skills_reorg.sh \
  tests/test_profiles.sh \
  tests/test_artifact_contract.sh \
  tests/test_work_items.sh \
  tests/test_protocol_registry.sh \
  tests/test_plan_sync.sh \
  tests/test_repo_map.sh \
  tests/test_journey_evals.sh \
  tests/test_gate_automation.sh \
  tests/test_brainstorming.sh \
  tests/test_release_convergence.sh \
  tests/bootstrap/run-all.sh
"
PRIVATE_SUITES="
  tests/test_skill_inventory.sh
  tests/test_skill_surface.sh
  tests/test_skill_bundle_benchmark.sh
"

SUITES="$PUBLIC_SUITES"
if [ -d "$ROOT/docs/work" ] && [ -f "$ROOT/docs/STATUS.md" ]; then
  SUITES="$SUITES$PRIVATE_SUITES"
else
  echo "=== private development suites skipped (public payload) ==="
fi

for suite in $SUITES; do
  echo "=== $suite ==="
  bash "$suite" || rc=1
done

if [ "$rc" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$rc"
