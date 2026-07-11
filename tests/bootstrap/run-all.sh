#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
rc=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  bash "$t" || rc=1
done
if [ "$rc" = 0 ]; then echo "ALL BOOTSTRAP TESTS PASSED"; else echo "SOME BOOTSTRAP TESTS FAILED"; fi
exit "$rc"
