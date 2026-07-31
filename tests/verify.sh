#!/usr/bin/env bash
# Canonical test runner for skill-commons (v0.9.0 item 0; spec D-007).
#
# Thin orchestrator: runs the python3 unittest layers + flatten-enumerated bash
# leaf suites, one each, timed. Python layers distinguish ERROR vs FAILURE from
# unittest's summary; wrapped bash suites are rc-only (rc!=0 => suite-FAIL,
# rc==0 trusted -- their internal fail-open is a D-002 residual until items 1-3).
#
# Anti-fail-open (the bug this item exists to kill): NO `set -e` around suite
# invocations; each rc is captured immediately with no pipeline between the suite
# and the capture; aggregation reads the roster from a file (never `pipe | while`,
# which would run the loop in a subshell and silently drop the counters).
# Bash 3.2 compatible.
#
# Usage:
#   bash tests/verify.sh            run the full roster
#   bash tests/verify.sh --list     print the roster, run nothing (rc 0)
#   VERIFY_ROSTER_FILE=f bash tests/verify.sh   run only entries in f (contract tests)
#
# Roster line format (also --list output): "<kind> <name> [startdir]"
#   layer <name> [startdir]   python3 -m unittest discover -t . -s <startdir|tests/py/name>
#   suite <path>              bash <path>
#
# Per-entry stdout: "SUITE <kind>:<name> rc=<n> secs=<x> [ERROR|FAILURE|FAIL...]"
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

PY_LAYERS="unit integration e2e"

# Suites are DISCOVERED, never listed. A hardcoded roster is how a suite goes
# dark: adding tests/test_foo.sh without touching this file used to mean it
# simply never ran. Discovery makes that impossible -- every tests/test_*.sh and
# tests/bootstrap/test_*.sh is in the roster by construction.
#
# The public/private boundary is NOT duplicated here. Maintainer-only suites are
# export-ignored in .gitattributes, so a public payload physically lacks them and
# the same discovery yields the correct, smaller roster there. One boundary, one
# place. Non-suite helpers (run-all.sh, lib/) lack the test_ prefix and are
# skipped without an exclusion list.
emit_default_roster() {
  for l in $PY_LAYERS; do echo "layer $l"; done
  for f in tests/test_*.sh; do
    [ -f "$f" ] || continue
    echo "suite $f"
  done
  for f in tests/bootstrap/test_*.sh; do
    [ -f "$f" ] || continue
    echo "suite $f"
  done
}

# --list: print roster, execute nothing.
if [ "${1:-}" = "--list" ]; then
  emit_default_roster
  exit 0
fi

# Re-entrancy guard: only for un-scoped runs (scoped/contract runs are allowed to nest).
if [ -z "${VERIFY_ROSTER_FILE:-}" ]; then
  if [ "${VERIFY_ACTIVE:-}" = "1" ]; then
    echo "ERROR verify.sh: nested un-scoped invocation (re-entrancy guard); use --list or VERIFY_ROSTER_FILE" >&2
    exit 3
  fi
  export VERIFY_ACTIVE=1
fi

# Wall-clock epoch (time.time), NOT time.monotonic: each _now is a separate python
# process and monotonic's reference point is per-process/undefined, so cross-process
# deltas are invalid. time.time() shares the epoch across processes.
_now() { python3 -c 'import time; print("%.3f" % time.time())'; }
_delta() { python3 -c "print('%.3f' % (${2} - ${1}))"; }

roster_file="$(mktemp)"
trap 'rm -f "$roster_file"' EXIT
if [ -n "${VERIFY_ROSTER_FILE:-}" ]; then
  if ! cat "$VERIFY_ROSTER_FILE" > "$roster_file" 2>/dev/null; then
    echo "ERROR verify.sh: cannot read VERIFY_ROSTER_FILE=$VERIFY_ROSTER_FILE (fail-closed)" >&2
    exit 3
  fi
else
  emit_default_roster > "$roster_file"
fi

errors=0
failures=0
count=0

# Aggregation loop reads from a file (NOT a pipe) so counters survive. The
# `|| [ -n ... ]` clause processes a final line lacking a trailing newline.
while IFS=' ' read -r kind name extra || [ -n "${kind:-}" ]; do
  [ -n "${kind:-}" ] || continue
  count=$((count + 1))
  start="$(_now)"
  if [ "$kind" = "layer" ]; then
    sdir="${extra:-tests/py/$name}"
    out="$(python3 -m unittest discover -t . -s "$sdir" </dev/null 2>&1)"
    rc=$?
    end="$(_now)"
    secs="$(_delta "$start" "$end")"
    if [ "$rc" -eq 5 ] || printf '%s' "$out" | grep -qE 'Ran 0 tests|NO TESTS RAN'; then
      echo "SUITE layer:$name rc=$rc secs=$secs ERROR(empty-layer,fail-closed)"
      errors=$((errors + 1))
    elif [ "$rc" -ne 0 ]; then
      if printf '%s' "$out" | grep -qE 'errors=[1-9]'; then
        echo "SUITE layer:$name rc=$rc secs=$secs ERROR"
        errors=$((errors + 1))
      else
        echo "SUITE layer:$name rc=$rc secs=$secs FAILURE"
        failures=$((failures + 1))
      fi
    else
      echo "SUITE layer:$name rc=$rc secs=$secs"
    fi
  elif [ "$kind" = "suite" ]; then
    if [ ! -f "$name" ]; then
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      echo "SUITE suite:$name rc=127 secs=$secs ERROR(missing-roster-entry,fail-closed)"
      errors=$((errors + 1))
    else
      bash "$name" </dev/null >/dev/null 2>&1
      rc=$?
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      if [ "$rc" -ne 0 ]; then
        echo "SUITE suite:$name rc=$rc secs=$secs FAIL"
        failures=$((failures + 1))
      else
        echo "SUITE suite:$name rc=$rc secs=$secs"
      fi
    fi
  else
    echo "SUITE unknown:$name rc=1 secs=0 ERROR(bad-roster-kind)"
    errors=$((errors + 1))
  fi
done < "$roster_file"

echo "SUMMARY entries=$count errors=$errors failures=$failures"
if [ "$count" -eq 0 ]; then
  echo "ERROR verify.sh: empty roster (0 entries executed, fail-closed)" >&2
  exit 3
fi
if [ "$errors" -ne 0 ] || [ "$failures" -ne 0 ]; then
  exit 1
fi
exit 0
