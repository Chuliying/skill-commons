#!/usr/bin/env bash
# Compatibility shim. `tests/verify.sh` is the single canonical runner.
#
# This file used to carry its own explicit suite roster. That roster drifted from
# the tree in two ways that mattered: it never ran the python unittest layers
# under tests/py (so the foundation subsystem's tests did not gate CI at all),
# and any newly added tests/test_*.sh stayed dark until someone remembered to
# list it here. verify.sh discovers suites instead, so both classes are gone.
#
# The public/private split this file used to compute from `docs/work` presence is
# now declared once in .gitattributes (maintainer-only suites are export-ignore),
# so a public payload simply does not contain them and discovery yields the
# correct smaller roster there.
#
# Kept as a shim because README, AGENTS.md, CI and the payload check refer to it.
# Prefer `bash tests/verify.sh` in new callers.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash tests/verify.sh
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$rc"
