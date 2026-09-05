#!/usr/bin/env bash
# Full verification: independent source and public gates.
# Direct invocation is fresh; verify.sh local mode explicitly enables the cache.
# The public gate always runs, even when the source gate fails.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

source_rc=0
bash "$ROOT/tests/verify.sh" --scope source
source_rc=$?

public_rc=0
if [ "${VERIFY_LOCAL_CACHE:-0}" = "1" ]; then
  bash "$ROOT/tests/verify-public.sh" --cached
else
  bash "$ROOT/tests/verify-public.sh"
fi
public_rc=$?

echo "RELEASE source_rc=$source_rc public_rc=$public_rc"
if [ "$source_rc" -eq 0 ] && [ "$public_rc" -eq 0 ]; then
  exit 0
fi
exit 1
