#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
rc=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  bash "$t" || rc=1
done
echo "=== ../test_skills_reorg.sh ==="
bash ../test_skills_reorg.sh || rc=1
echo "=== ../test_artifact_contract.sh ==="
bash ../test_artifact_contract.sh || rc=1
if [ "$rc" = 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$rc"
