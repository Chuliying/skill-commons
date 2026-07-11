#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rc=0
for suite in \
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
do
  echo "=== $suite ==="
  bash "$suite" || rc=1
done

if [ "$rc" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$rc"
