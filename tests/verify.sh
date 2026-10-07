#!/usr/bin/env bash
# Canonical source/public scoped test runner for skill-commons.
#
# The runner discovers the Python layers and Bash leaf suites from the current
# tree.  Each entry gets separate stdout/stderr files in a unique temporary run
# directory.  Successful runs remove that directory; a run with any error or
# failure keeps it and replays diagnostics with a copy/paste retry.
#
# Usage:
#   bash tests/verify.sh                    local source + public (cache eligible)
#   bash tests/verify.sh --release          source + fresh public release gates
#   bash tests/verify.sh --scope source     explicit source scope
#   bash tests/verify.sh --scope public     delegate to the fresh public gate
#   bash tests/verify.sh --list             print the discovered roster only
#   VERIFY_ROSTER_FILE=f bash tests/verify.sh
#
# Roster line format: "<kind> <name> [startdir]"
#   layer <name> [startdir]   python3 -m unittest discover -t . -s <startdir|tests/py/name>
#   suite <path>              bash <path>
#
# Bash 3.2 is supported.  No suite is allowed to consume the roster because
# every child receives /dev/null as stdin.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

scope="${VERIFY_SCOPE:-source}"
list_only=0
release_mode=0
scope_selected=0
full_requested=0
if [ "$#" -eq 0 ] && [ -z "${VERIFY_ROSTER_FILE:-}" ] && [ -z "${VERIFY_SCOPE+x}" ]; then
  full_requested=1
fi

usage() {
  cat <<'EOF'
usage: bash tests/verify.sh [--release] [--list] [--scope source|public]

With no arguments, run source and public checks with a content-addressed local
public verdict cache. --release forces a fresh public run. Use
--scope source|public for one discovered suite scope.  Set VERIFY_ROSTER_FILE
for a bounded source roster, or VERIFY_LOG_ROOT to choose a temporary log
parent.  Failed runs retain their log directory and print a retry command.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release)
      release_mode=1
      ;;
    --list)
      list_only=1
      ;;
    --scope)
      scope_selected=1
      shift
      if [ "$#" -eq 0 ]; then
        echo "ERROR verify.sh: --scope requires source or public" >&2
        exit 2
      fi
      scope="$1"
      ;;
    --scope=*)
      scope_selected=1
      scope="${1#--scope=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR verify.sh: unknown option or invalid selection: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$release_mode" -eq 1 ]; then
  export SKILL_COMMONS_VERIFY_NO_CACHE=1
  if [ "$scope_selected" -eq 0 ] && [ -z "${VERIFY_ROSTER_FILE:-}" ] && [ "$list_only" -eq 0 ]; then
    full_requested=1
  fi
elif [ "$scope_selected" -eq 0 ] && [ "$list_only" -eq 0 ]; then
  if [ "${SKILL_COMMONS_VERIFY_NO_CACHE:-0}" = "1" ]; then
    echo "NOTE verify.sh: ambient SKILL_COMMONS_VERIFY_NO_CACHE=1 is ignored in local mode; use: bash tests/verify.sh --release" >&2
  fi
  export SKILL_COMMONS_VERIFY_NO_CACHE=0
fi

case "$scope" in
  source|public) ;;
  *)
    echo "ERROR verify.sh: invalid scope '$scope' (choose source or public)" >&2
    exit 2
    ;;
esac

# Keep local full checks and the explicit fresh release mode on one entry.
# Scoped source runs are the local/contract hook and never claim that public was
# run.  Public scope is a deliberate delegation to the fresh public gate.
# Check re-entrancy before delegation so an accidental nested default invocation
# fails in milliseconds instead of starting either gate.
if [ "$full_requested" -eq 1 ]; then
  if [ "${VERIFY_ACTIVE:-}" = "1" ]; then
    echo "ERROR verify.sh: nested un-scoped invocation (re-entrancy guard); use --list or VERIFY_ROSTER_FILE" >&2
    exit 3
  fi
  if [ "$release_mode" -eq 1 ]; then export VERIFY_LOCAL_CACHE=0; else export VERIFY_LOCAL_CACHE=1; fi
  exec bash "$HERE/verify-release.sh"
fi

if [ "$scope" = "public" ]; then
  if [ "$list_only" -eq 1 ]; then
    echo "ERROR verify.sh: --list is source-only; public scope requires a fresh export" >&2
    exit 2
  fi
  if [ -n "${VERIFY_ROSTER_FILE:-}" ]; then
    echo "ERROR verify.sh: custom VERIFY_ROSTER_FILE is source-only; use verify-public.sh for a fresh public scope" >&2
    exit 2
  fi
  exec bash "$HERE/verify-public.sh"
fi

PY_LAYERS="unit integration e2e"

# Suites are discovered, never listed.  A hardcoded roster is how a suite goes
# dark: every tests/test_*.sh and tests/bootstrap/test_*.sh is included by
# construction.  The public/private boundary is declared in .gitattributes;
# export-ignore removes maintainer-only files before public discovery.
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

if [ "$list_only" -eq 1 ]; then
  emit_default_roster
  exit 0
fi

# Re-entrancy guard applies to the full discovered run.  A scoped roster is an
# intentional contract-test hook and is therefore allowed to run independently.
if [ -z "${VERIFY_ROSTER_FILE:-}" ]; then
  if [ "${VERIFY_ACTIVE:-}" = "1" ]; then
    echo "ERROR verify.sh: nested un-scoped invocation (re-entrancy guard); use --list or VERIFY_ROSTER_FILE" >&2
    exit 3
  fi
  export VERIFY_ACTIVE=1
fi

# Wall-clock epoch (time.time), NOT time.monotonic: each _now is a separate
# Python process and monotonic's reference point is process-local.
_now() { python3 -c 'import time; print("%.3f" % time.time())'; }
_delta() { python3 -c "print('%.3f' % (${2} - ${1}))"; }

log_parent="${VERIFY_LOG_ROOT:-${TMPDIR:-/tmp}}"
log_dir="${VERIFY_LOG_DIR:-}"
selection="discovered"
if [ -n "${VERIFY_ROSTER_FILE:-}" ]; then
  selection="custom"
fi
if [ -n "$log_dir" ]; then
  if [ -e "$log_dir" ] || [ -L "$log_dir" ]; then
    echo "ERROR verify.sh: VERIFY_LOG_DIR already exists (refusing to overwrite): $log_dir" >&2
    exit 3
  fi
  if ! mkdir -p "$log_dir"; then
    echo "ERROR verify.sh: cannot create VERIFY_LOG_DIR=$log_dir" >&2
    exit 3
  fi
else
  if [ ! -d "$log_parent" ]; then
    echo "ERROR verify.sh: log parent does not exist: $log_parent" >&2
    exit 3
  fi
  case "$log_parent" in
    */) log_template="${log_parent}skill-commons-verify.XXXXXX" ;;
    *) log_template="${log_parent}/skill-commons-verify.XXXXXX" ;;
  esac
  log_dir="$(mktemp -d "$log_template" 2>/dev/null)" || {
    echo "ERROR verify.sh: cannot create unique temporary log directory under $log_parent" >&2
    exit 3
  }
fi

keep_logs=0
cleanup_logs() {
  if [ "$keep_logs" -eq 0 ] && [ -n "${log_dir:-}" ]; then
    rm -rf "$log_dir"
  fi
}
trap cleanup_logs EXIT

roster_file="$log_dir/roster"
failure_file="$log_dir/failures.tsv"
printf 'scope=%s\nselection=%s\n' "$scope" "$selection" > "$log_dir/run.meta"

if [ -n "${VERIFY_ROSTER_FILE:-}" ]; then
  if ! cat "$VERIFY_ROSTER_FILE" > "$roster_file" 2>"$log_dir/roster.stderr.log"; then
    printf 'cannot read VERIFY_ROSTER_FILE=%s\n' "$VERIFY_ROSTER_FILE" >"$log_dir/roster.stderr.log"
    echo "ERROR verify.sh: cannot read VERIFY_ROSTER_FILE=$VERIFY_ROSTER_FILE (fail-closed)" >&2
    keep_logs=1
    echo "DIAGNOSTICS dir=$log_dir"
    echo "RETRY: VERIFY_SCOPE=$scope VERIFY_ROSTER_FILE=$roster_file bash tests/verify.sh"
    exit 3
  fi
else
  emit_default_roster > "$roster_file"
fi

errors=0
failures=0
count=0

record_failure() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" >> "$failure_file"
}

write_entry_roster() {
  entry_roster="$log_dir/entry-$1.roster"
  if [ "$2" = "layer" ]; then
    if [ -n "${4:-}" ]; then
      printf 'layer %s %s\n' "${3:-}" "$4" > "$entry_roster"
    else
      printf 'layer %s\n' "${3:-}" > "$entry_roster"
    fi
  elif [ "$2" = "suite" ]; then
    if [ -n "${4:-}" ]; then
      printf 'suite %s %s\n' "${3:-}" "$4" > "$entry_roster"
    else
      printf 'suite %s\n' "${3:-}" > "$entry_roster"
    fi
  else
    printf '%s %s %s\n' "$2" "${3:-}" "${4:-}" > "$entry_roster"
  fi
}

shell_quote() {
  quoted_value="$1"
  quoted_value="$(printf '%s' "$quoted_value" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$quoted_value"
}

file_contains() {
  pattern="$1"
  file="$2"
  grep -qE "$pattern" "$file" 2>/dev/null
}

entry_diagnostic() {
  label="$1"
  file="$2"
  echo "  ${label}:"
  if [ -s "$file" ]; then
    cat "$file"
  else
    echo "    (empty)"
  fi
}

# Aggregation reads from a file (not pipe | while) so counters survive.  The
# final-line clause processes a roster without a trailing newline.
while IFS=' ' read -r kind name extra || [ -n "${kind:-}" ]; do
  [ -n "${kind:-}" ] || continue
  count=$((count + 1))
  entry_id="$(printf '%03d' "$count")"
  stdout_log="$log_dir/entry-${entry_id}.stdout.log"
  stderr_log="$log_dir/entry-${entry_id}.stderr.log"
  write_entry_roster "$entry_id" "$kind" "${name:-}" "${extra:-}"
  printf 'kind=%s\nname=%s\nextra=%s\n' "$kind" "${name:-}" "${extra:-}" > "$log_dir/entry-${entry_id}.meta"
  start="$(_now)"

  if [ "$kind" = "layer" ]; then
    if [ -z "${name:-}" ]; then
      printf 'invalid layer selection; expected: layer <name> [startdir]\n' > "$stderr_log"
      rc=2
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      echo "SUITE layer:${name:-<empty>} rc=$rc secs=$secs ERROR(invalid-selection,fail-closed)"
      errors=$((errors + 1))
      record_failure "$entry_id" "$kind" "${name:-<empty>}" "$rc" "$stdout_log" "$stderr_log"
    else
      sdir="${extra:-tests/py/$name}"
      python3 -m unittest discover -t . -s "$sdir" </dev/null >"$stdout_log" 2>"$stderr_log"
      rc=$?
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      if [ "$rc" -eq 5 ] || file_contains 'Ran 0 tests|NO TESTS RAN' "$stdout_log" || file_contains 'Ran 0 tests|NO TESTS RAN' "$stderr_log"; then
        echo "SUITE layer:$name rc=$rc secs=$secs ERROR(empty-layer,fail-closed)"
        errors=$((errors + 1))
        record_failure "$entry_id" "$kind" "$name" "$rc" "$stdout_log" "$stderr_log"
      elif [ "$rc" -ne 0 ]; then
        if file_contains 'errors=[1-9]' "$stdout_log" || file_contains 'errors=[1-9]' "$stderr_log"; then
          echo "SUITE layer:$name rc=$rc secs=$secs ERROR"
          errors=$((errors + 1))
        else
          echo "SUITE layer:$name rc=$rc secs=$secs FAILURE"
          failures=$((failures + 1))
        fi
        record_failure "$entry_id" "$kind" "$name" "$rc" "$stdout_log" "$stderr_log"
      else
        # unittest prints skips only in its summary (stderr); show the count on a
        # green layer so coverage lost to a missing tool is visible. Skips do not fail.
        skipped="$(sed -n 's/.*skipped=\([0-9][0-9]*\).*/\1/p' "$stderr_log" | tail -1)"
        echo "SUITE layer:$name rc=$rc secs=$secs${skipped:+ skipped=$skipped}"
      fi
    fi
  elif [ "$kind" = "suite" ]; then
    if [ -z "${name:-}" ] || [ -n "${extra:-}" ]; then
      printf 'invalid suite selection; expected: suite <path>\n' > "$stderr_log"
      rc=2
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      echo "SUITE suite:${name:-<empty>} rc=$rc secs=$secs ERROR(invalid-selection,fail-closed)"
      errors=$((errors + 1))
      record_failure "$entry_id" "$kind" "${name:-<empty>}" "$rc" "$stdout_log" "$stderr_log"
    elif [ ! -f "$name" ]; then
      printf 'missing roster entry: %s\n' "$name" > "$stderr_log"
      rc=127
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      echo "SUITE suite:$name rc=$rc secs=$secs ERROR(missing-roster-entry,fail-closed)"
      errors=$((errors + 1))
      record_failure "$entry_id" "$kind" "$name" "$rc" "$stdout_log" "$stderr_log"
    else
      bash "$name" </dev/null >"$stdout_log" 2>"$stderr_log"
      rc=$?
      end="$(_now)"
      secs="$(_delta "$start" "$end")"
      if [ "$rc" -ne 0 ]; then
        echo "SUITE suite:$name rc=$rc secs=$secs FAIL"
        failures=$((failures + 1))
        record_failure "$entry_id" "$kind" "$name" "$rc" "$stdout_log" "$stderr_log"
      else
        echo "SUITE suite:$name rc=$rc secs=$secs"
      fi
    fi
  else
    printf 'invalid roster kind: %s\n' "$kind" > "$stderr_log"
    rc=2
    end="$(_now)"
    secs="$(_delta "$start" "$end")"
    echo "SUITE unknown:${name:-<empty>} rc=$rc secs=$secs ERROR(bad-roster-kind,fail-closed)"
    errors=$((errors + 1))
    record_failure "$entry_id" "$kind" "${name:-<empty>}" "$rc" "$stdout_log" "$stderr_log"
  fi
done < "$roster_file"

if [ "$count" -eq 0 ]; then
  printf 'empty roster: 0 entries executed\n' > "$log_dir/roster.stderr.log"
  errors=$((errors + 1))
  echo "ERROR verify.sh: empty roster (0 entries executed, fail-closed)" >&2
fi
echo "SUMMARY entries=$count errors=$errors failures=$failures scope=$scope selection=$selection"

if [ "$errors" -ne 0 ] || [ "$failures" -ne 0 ]; then
  keep_logs=1
  echo "DIAGNOSTICS dir=$log_dir"
  echo "RETRY: VERIFY_SCOPE=$scope VERIFY_ROSTER_FILE=$roster_file bash tests/verify.sh"
  if [ -s "$failure_file" ]; then
    while IFS="	" read -r failed_id failed_kind failed_name failed_rc failed_stdout failed_stderr; do
      failed_roster="$log_dir/entry-$failed_id.roster"
      retry_repo="$(shell_quote "$REPO")"
      retry_roster="$(shell_quote "$failed_roster")"
      echo "FAILED $failed_kind:${failed_name} rc=$failed_rc stdout=$failed_stdout stderr=$failed_stderr"
      echo "RETRY_ENTRY: (cd $retry_repo && VERIFY_SCOPE=$scope VERIFY_ROSTER_FILE=$retry_roster bash tests/verify.sh --scope $scope)"
      entry_diagnostic "stdout" "$failed_stdout"
      entry_diagnostic "stderr" "$failed_stderr"
    done < "$failure_file"
  fi
  exit 1
fi

if [ "${VERIFY_KEEP_LOGS:-0}" = "1" ]; then
  keep_logs=1
  echo "LOGS dir=$log_dir"
fi
exit 0
