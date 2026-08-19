#!/usr/bin/env bash
# Manifest-aware secret scanner. Execute from the consuming repo root.
#
# Operation-result protocol (I-S11): every mandatory operation records exactly one
# state -- VERIFIED (ran to completion with a trustworthy answer), FINDING (ran and
# found a security problem), ERROR (could not produce a trustworthy answer: crash,
# timeout, malformed output, unexpected rc), or NA (precondition CONFIRMED absent,
# e.g. a confirmed non-repo for git-backed checks). The overall PASS is derived from
# the roster: it is emitted ONLY when every mandatory check recorded VERIFIED or NA.
# A mandatory check that records nothing is a protocol violation and fails the scan.
#
# This is containment: it guarantees fail-closed error propagation, not detection
# quality. The detection redesign lands in the secret-engine-adapter item.

set -u -o pipefail

case "$0" in
  */*) script_dir_input="${0%/*}" ;;
  *) script_dir_input="." ;;
esac
SCRIPT_DIR="$(cd "$script_dir_input" 2>/dev/null && pwd -P)"
if [[ -z "$SCRIPT_DIR" ]]; then
  echo "FAIL: cannot resolve scanner directory" >&2
  exit 1
fi

STACK_HELPER="$SCRIPT_DIR/../../scripts/manifest-stack.sh"
EXTRACT_SECRETS="$SCRIPT_DIR/extract-secrets.py"
BOUNDED_RUNNER="$SCRIPT_DIR/run-bounded.py"
SCAN_FILES="$SCRIPT_DIR/scan-files.py"
for required_file in "$STACK_HELPER" "$EXTRACT_SECRETS" "$BOUNDED_RUNNER" "$SCAN_FILES"; do
  if [[ ! -r "$required_file" ]]; then
    echo "FAIL: required scanner helper not found: $required_file" >&2
    exit 1
  fi
done

OPERATION_TIMEOUT="${SCAN_OPERATION_TIMEOUT:-60}"
REQUESTED_ENGINE_TIMEOUT="${SCAN_ENGINE_TIMEOUT:-$OPERATION_TIMEOUT}"
ENGINE_TIMEOUT="$OPERATION_TIMEOUT"

run_bounded() { # $1=timeout, remaining args=command
  local timeout="$1"
  shift
  command python3 "$BOUNDED_RUNNER" "$timeout" "$@"
}

run_operation() {
  run_bounded "$OPERATION_TIMEOUT" "$@"
}

run_engine() {
  run_bounded "$ENGINE_TIMEOUT" python3 "$EXTRACT_SECRETS" "$@"
}

run_engine_with_input() {
  run_bounded "$ENGINE_TIMEOUT" --stdin python3 "$EXTRACT_SECRETS" "$@"
}

run_support() {
  run_operation python3 "$SCAN_FILES" "$@"
}

run_support_with_input() {
  run_bounded "$OPERATION_TIMEOUT" --stdin python3 "$SCAN_FILES" "$@"
}

# Findings are reported by location and category, never by value. Emitting the
# matched text would copy the secret into CI logs, terminal scrollback and any
# artifact that captures this output -- turning a detection into a second leak.
# The path:line prefix is preserved so a finding stays actionable.
redact_file_matches() {
  awk -v category="$1" '
    {
      if (match($0, /:[0-9]+:/)) {
        print substr($0, 1, RSTART + RLENGTH - 1) "[" category " candidate redacted]"
      } else {
        print "[" category " candidate redacted]"
      }
    }
  '
}

# Search protocol v2 proves artifact coverage, not merely process success. The helper
# emits one header plus M single-line ASCII-safe records:
#   scan-files-search:v2:<enumerated>:<scanned>:<matches>
# The caller already knows the expected scope count and rejects any non-conservation.
SEARCH_PAYLOAD=""
parse_search_result() { # $1=combined stdout $2=expected artifact count
  local result="$1" expected="$2" header body="" enumerated scanned matches
  local remaining record actual_matches=0
  SEARCH_PAYLOAD=""
  case "$result" in
    *$'\n'*) header="${result%%$'\n'*}"; body="${result#*$'\n'}" ;;
    *) header="$result" ;;
  esac
  if [[ ! "$header" =~ ^scan-files-search:v2:(0|[1-9][0-9]*):(0|[1-9][0-9]*):(0|[1-9][0-9]*)$ ]]; then
    return 1
  fi
  enumerated="${BASH_REMATCH[1]}"
  scanned="${BASH_REMATCH[2]}"
  matches="${BASH_REMATCH[3]}"
  if [[ "$enumerated" -ne "$expected" || "$scanned" -ne "$enumerated" ]]; then
    return 1
  fi
  if [[ -n "$body" ]]; then
    remaining="$body"
    while :; do
      case "$remaining" in
        *$'\n'*) record="${remaining%%$'\n'*}"; remaining="${remaining#*$'\n'}" ;;
        *) record="$remaining"; remaining="" ;;
      esac
      [[ -n "$record" ]] || return 1
      actual_matches=$((actual_matches + 1))
      [[ -z "$remaining" ]] && break
    done
  fi
  [[ "$actual_matches" -eq "$matches" ]] || return 1
  SEARCH_PAYLOAD="$body"
  return 0
}

# The bounded runner cannot certify its own interpreter until it has started, so its
# exact-sentinel handshake has a tiny Bash watchdog. This closes the bootstrap gap:
# a wedged/no-op python3 cannot hang forever or unlock any PASS before the runner is
# trusted. All later mandatory subprocesses go through the verified runner.
RUNNER_HEALTH_OUT=""
terminate_bootstrap_group() { # $1=process-group id
  local process_group_id="$1" grace_pid
  kill -TERM -- "-$process_group_id" 2>/dev/null || true
  /bin/sleep 0.25 &
  grace_pid=$!
  while kill -0 -- "-$process_group_id" 2>/dev/null && kill -0 "$grace_pid" 2>/dev/null; do
    /bin/sleep 0.02
  done
  if kill -0 -- "-$process_group_id" 2>/dev/null; then
    kill -KILL -- "-$process_group_id" 2>/dev/null || true
  fi
  kill -TERM "$grace_pid" 2>/dev/null || true
  kill -KILL "$grace_pid" 2>/dev/null || true
  wait "$grace_pid" 2>/dev/null || true
}

bootstrap_runner_health_worker() {
  local health_dir health_file
  local health_pid timer_pid health_rc timed_out=0 first_line="" extra_line="" health_out=""

  # BOOTSTRAP_WORKER_SETUP_START
  if [[ ! -x /usr/bin/mktemp ]]; then
    echo "trusted bootstrap dependency missing: /usr/bin/mktemp" >&2
    return 125
  fi
  health_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/skill-commons-runner-health.XXXXXX")" || return 125
  /bin/chmod 700 "$health_dir" || {
    /bin/rmdir "$health_dir" 2>/dev/null || true
    return 125
  }
  health_file="$health_dir/evidence"
  umask 077
  set -C
  if ! exec 3> "$health_file"; then
    set +C
    echo "cannot create exclusive runner-health evidence file: $health_file" >&2
    /bin/rmdir "$health_dir" 2>/dev/null || true
    return 125
  fi
  set +C
  if ! exec 4< "$health_file"; then
    exec 3>&-
    /bin/rm -f "$health_file"
    /bin/rmdir "$health_dir" 2>/dev/null || true
    return 125
  fi
  if ! /bin/rm -f "$health_file"; then
    exec 3>&- 4>&-
    /bin/rmdir "$health_dir" 2>/dev/null || true
    return 125
  fi
  /bin/rmdir "$health_dir" || {
    exec 3>&- 4>&-
    return 125
  }

  # Bash monitor mode gives this one background job its own process group. Disable it
  # immediately after launch; the group remains independently killable by -PGID.
  set -m
  command python3 "$BOUNDED_RUNNER" --health-check >&3 2>&1 &
  health_pid=$!
  set +m
  /bin/sleep "$OPERATION_TIMEOUT" &
  timer_pid=$!
  while kill -0 "$health_pid" 2>/dev/null && kill -0 "$timer_pid" 2>/dev/null; do
    /bin/sleep 0.05
  done
  if kill -0 "$health_pid" 2>/dev/null; then
    timed_out=1
    terminate_bootstrap_group "$health_pid"
  fi
  wait "$health_pid"
  health_rc=$?
  terminate_bootstrap_group "$health_pid"
  kill -TERM "$timer_pid" 2>/dev/null || true
  kill -KILL "$timer_pid" 2>/dev/null || true
  wait "$timer_pid" 2>/dev/null || true
  exec 3>&-
  IFS= read -r first_line <&4 || true
  if IFS= read -r extra_line <&4; then
    health_out="${first_line}
${extra_line}"
  else
    health_out="$first_line"
  fi
  exec 4>&-
  [[ "$timed_out" -eq 1 ]] && return 124
  [[ "$health_rc" -ne 0 ]] && return "$health_rc"
  [[ "$health_out" == "run-bounded:v1" ]] || return 3
  printf 'run-bounded:v1\n'
  return 0
}

bootstrap_runner_health_channel() {
  local body_pid worker_rc
  set -m
  bootstrap_runner_health_worker >/dev/null 2>&1 &
  body_pid=$!
  set +m
  trap 'terminate_bootstrap_group "$body_pid"; exit 143' TERM HUP INT
  wait "$body_pid"
  worker_rc=$?
  trap - TERM HUP INT
  if [[ "$worker_rc" -eq 0 ]]; then
    printf 'VERIFIED:run-bounded:v1\n'
  else
    printf 'ERROR:%s\n' "$worker_rc"
  fi
}

terminate_bootstrap_worker() { # $1=worker pid (not a process-group id)
  local worker_pid="$1"
  kill -TERM "$worker_pid" 2>/dev/null || true
  /bin/sleep 0.5
  if kill -0 "$worker_pid" 2>/dev/null; then
    kill -KILL "$worker_pid" 2>/dev/null || true
  fi
}

bootstrap_runner_health() {
  local worker_pid outer_timer_pid worker_rc=125 timed_out=0 result_line=""
  RUNNER_HEALTH_OUT=""

  # Arm the outer deadline before the worker exists. The entire worker -- private
  # evidence setup, runtime launch, verification and cleanup -- is therefore inside
  # the bootstrap bound, even though the Python runner is not trusted yet.
  /bin/sleep "$OPERATION_TIMEOUT" &
  outer_timer_pid=$!
  exec 4< <(bootstrap_runner_health_channel)
  worker_pid=$!
  while kill -0 "$worker_pid" 2>/dev/null && kill -0 "$outer_timer_pid" 2>/dev/null; do
    /bin/sleep 0.05
  done
  if kill -0 "$worker_pid" 2>/dev/null; then
    timed_out=1
    terminate_bootstrap_worker "$worker_pid"
  fi
  wait "$worker_pid" 2>/dev/null || true
  kill -TERM "$outer_timer_pid" 2>/dev/null || true
  kill -KILL "$outer_timer_pid" 2>/dev/null || true
  wait "$outer_timer_pid" 2>/dev/null || true

  if [[ "$timed_out" -eq 1 ]]; then
    exec 4<&-
    return 124
  fi
  if IFS= read -r result_line <&4; then
    case "$result_line" in
      VERIFIED:run-bounded:v1)
        worker_rc=0
        RUNNER_HEALTH_OUT="run-bounded:v1"
        ;;
      ERROR:[0-9]|ERROR:[0-9][0-9]|ERROR:[12][0-9][0-9])
        worker_rc="${result_line#ERROR:}"
        ;;
      *) worker_rc=125 ;;
    esac
  fi
  exec 4<&-
  return "$worker_rc"
}

# Read the manifest through its canonical helper in a bounded subprocess. Missing
# values are valid rc-0 empty strings; helper/runtime failures are not defaults.
manifest_value() {
  local key="$1"
  run_operation "$BASH" -c '
set -o pipefail
source "$1" || exit $?
declare -F manifest_stack_value >/dev/null || exit 127
manifest_stack_value "$2"
' _ "$STACK_HELPER" "$key"
}

load_manifest_value() { # $1=key $2=destination variable $3=operation name
  local key="$1" destination="$2" operation="$3" output rc
  output="$(manifest_value "$key")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: manifest helper failed while reading '$key' (exit $rc); configuration cannot be trusted" >&2
    record_operation "$operation" ERROR
    return "$rc"
  fi
  printf -v "$destination" '%s' "$output"
  record_operation "$operation" VERIFIED
}

# ---- check protocol ----
MANDATORY_CHECKS="runtime_health manifest_config engine_health git_state scan_scope worktree_scan env_ignore staged_scan client_exposure log_hygiene"
CHECK_PROTOCOL=""
MANDATORY_OPERATIONS="runner_health timeout_config manifest_helper_health manifest_source_roots manifest_source_extensions manifest_package_manager manifest_framework manifest_client_prefixes manifest_has_ui support_health engine_health git_state_probe scope_enumerate worktree_search worktree_extract client_search log_search env_ignore staged_temp_create staged_materialize staged_search staged_extract staged_cleanup"
OPERATION_PROTOCOL=""
protocol_error=0
issues=0
record_check() { # $1=name $2=VERIFIED|FINDING|ERROR|NA
  local name="$1" state="$2"
  case " $MANDATORY_CHECKS " in
    *" $name "*) ;;
    *)
      echo "FAIL: unknown mandatory check '$name' (protocol violation)"
      issues=$((issues + 1)); protocol_error=1
      return 1
      ;;
  esac
  case "$state" in
    VERIFIED|FINDING|ERROR|NA) ;;
    *)
      echo "FAIL: invalid state '$state' for mandatory check '$name' (protocol violation)"
      issues=$((issues + 1)); protocol_error=1
      state=ERROR
      ;;
  esac
  case " $CHECK_PROTOCOL " in
    *" $name:"*)
      echo "FAIL: mandatory check '$name' recorded more than once (protocol violation)"
      issues=$((issues + 1)); protocol_error=1
      CHECK_PROTOCOL="${CHECK_PROTOCOL}${name}:ERROR "
      return 1
      ;;
  esac
  CHECK_PROTOCOL="${CHECK_PROTOCOL}${name}:${state} "
}

record_operation() { # $1=name $2=VERIFIED|FINDING|ERROR|NA
  local name="$1" state="$2"
  case " $MANDATORY_OPERATIONS " in
    *" $name "*) ;;
    *)
      echo "FAIL: unknown mandatory operation '$name' (protocol violation)"
      issues=$((issues + 1)); protocol_error=1
      return 1
      ;;
  esac
  case "$state" in
    VERIFIED|FINDING|ERROR|NA) ;;
    *)
      echo "FAIL: invalid state '$state' for mandatory operation '$name' (protocol violation)"
      issues=$((issues + 1)); protocol_error=1
      state=ERROR
      ;;
  esac
  case " $OPERATION_PROTOCOL " in
    *" $name:"*)
      echo "FAIL: mandatory operation '$name' recorded more than once (protocol violation)"
      issues=$((issues + 1)); protocol_error=1
      OPERATION_PROTOCOL="${OPERATION_PROTOCOL}${name}:ERROR "
      return 1
      ;;
  esac
  OPERATION_PROTOCOL="${OPERATION_PROTOCOL}${name}:${state} "
}

bootstrap_runner_health
runner_health_rc=$?
runner_health_out="$RUNNER_HEALTH_OUT"
if [[ "$runner_health_rc" -ne 0 || "$runner_health_out" != "run-bounded:v1" ]]; then
  echo "FAIL: bounded runner health check failed (exit $runner_health_rc, invalid handshake); no checks were executed"
  record_operation runner_health ERROR
  record_check runtime_health ERROR
  exit 1
fi
record_operation runner_health VERIFIED
record_check runtime_health VERIFIED

timeout_config_out="$(run_operation python3 "$BOUNDED_RUNNER" --min-timeout \
  "$OPERATION_TIMEOUT" "$REQUESTED_ENGINE_TIMEOUT" 2>&1)"
timeout_config_rc=$?
if [[ "$timeout_config_rc" -ne 0 || -z "$timeout_config_out" ]]; then
  echo "FAIL: invalid operation/engine timeout configuration (exit $timeout_config_rc)"
  record_operation timeout_config ERROR
  exit 1
fi
ENGINE_TIMEOUT="$timeout_config_out"
record_operation timeout_config VERIFIED

manifest_health_out="$(run_operation "$BASH" -c '
source "$1" || exit $?
declare -F manifest_stack_value >/dev/null || exit 127
probe_dir="$(/usr/bin/mktemp -d /tmp/skill-commons-manifest-probe.XXXXXX)" || exit $?
/bin/chmod 700 "$probe_dir" || exit $?
probe_file="$probe_dir/manifest.md"
cleanup_probe() {
  /bin/rm -f "$probe_file"
  /bin/rmdir "$probe_dir" 2>/dev/null || true
}
trap cleanup_probe EXIT
umask 077
set -C
printf "%s\n" "- skill_commons_probe: manifest-stack:v1" > "$probe_file" || exit $?
set +C
PROJECT_MANIFEST="$probe_file"
probe="$(manifest_stack_value skill_commons_probe)" || exit $?
[[ "$probe" == "manifest-stack:v1" ]] || exit 3
printf "manifest-stack:v1"
' _ "$STACK_HELPER" 2>&1)"
manifest_health_rc=$?
if [[ "$manifest_health_rc" -ne 0 || "$manifest_health_out" != "manifest-stack:v1" ]]; then
  echo "FAIL: manifest helper health check failed (exit $manifest_health_rc, invalid handshake)"
  record_operation manifest_helper_health ERROR
  record_check manifest_config ERROR
  exit 1
fi
record_operation manifest_helper_health VERIFIED

load_manifest_value source_roots manifest_source_roots manifest_source_roots || {
  record_check manifest_config ERROR
  exit 1
}
load_manifest_value source_extensions manifest_source_extensions manifest_source_extensions || {
  record_check manifest_config ERROR
  exit 1
}
load_manifest_value package_manager manifest_package_manager manifest_package_manager || {
  record_check manifest_config ERROR
  exit 1
}
load_manifest_value framework manifest_framework manifest_framework || {
  record_check manifest_config ERROR
  exit 1
}
load_manifest_value client_env_prefixes manifest_client_prefixes manifest_client_prefixes || {
  record_check manifest_config ERROR
  exit 1
}
load_manifest_value has_ui manifest_has_ui manifest_has_ui || {
  record_check manifest_config ERROR
  exit 1
}
record_check manifest_config VERIFIED

source_roots_text="${manifest_source_roots//,/ }"
# A missing source_roots declaration means the scanner has no narrower trustworthy
# boundary. Cover the worktree rather than inventing a conventional `src` directory:
# repositories with root-level sources remain usable, and repositories with an
# explicit declaration still receive the strict target validation below.
[[ -z "$source_roots_text" ]] && source_roots_text="."
source_extensions_text="${manifest_source_extensions//,/ }"
[[ -z "$source_extensions_text" ]] && source_extensions_text="ts tsx js jsx json py"

if [[ $# -gt 0 ]]; then
  targets=("$@")
else
  read -r -a targets <<< "$source_roots_text"
fi

# Several targets are allowed and every one of them is scanned. Select both CLI and
# manifest targets before validating any of them, so neither source can bypass the
# worktree boundary. This must finish before emitting target output or invoking a
# filesystem scan helper.
scan_worktree_root="$(pwd -P)"
scan_worktree_logical_root="$(pwd -L)"
target_path_is_contained_without_symlink() { # $1=target
  local candidate="$1" target_path component current depth=0
  local -a path_components normalized_components
  if [[ "$candidate" == /* ]]; then
    # An absolute spelling is valid only when it is lexically beneath this
    # worktree. Resolving an arbitrary absolute path could let an outside symlink
    # point inward and bypass the boundary.
    case "$candidate" in
      "$scan_worktree_root") target_path="." ;;
      "$scan_worktree_root"/*) target_path="${candidate#"$scan_worktree_root"/}" ;;
      "$scan_worktree_logical_root") target_path="." ;;
      "$scan_worktree_logical_root"/*) target_path="${candidate#"$scan_worktree_logical_root"/}" ;;
      *) return 1 ;;
    esac
  else
    target_path="$candidate"
  fi
  current="$scan_worktree_root"
  IFS=/ read -r -a path_components <<< "$target_path"
  for component in "${path_components[@]}"; do
    case "$component" in
      ""|.) continue ;;
      ..)
        [[ "$depth" -gt 0 ]] || return 1
        depth=$((depth - 1))
        unset "normalized_components[$depth]"
        current="$scan_worktree_root"
        if [[ "$depth" -gt 0 ]]; then
          current+="/$(IFS=/; printf '%s' "${normalized_components[*]}")"
        fi
        ;;
      *)
        if [[ -L "$current/$component" ]]; then
          return 2
        fi
        normalized_components+=("$component")
        depth=$((depth + 1))
        current="$current/$component"
        ;;
    esac
  done
  return 0
}

for candidate in "${targets[@]}"; do
  case "$candidate" in
    -*)
      echo "FAIL: unsafe scan target(s) begin with '-': $candidate"
      exit 1
      ;;
  esac
  target_path_is_contained_without_symlink "$candidate"
  target_validation_rc=$?
  case "$target_validation_rc" in
    0) ;;
    2)
      echo "FAIL: target is a symlink and cannot be scanned: $candidate"
      exit 1
      ;;
    *)
      echo "FAIL: target resolves outside the Git worktree: $candidate"
      exit 1
      ;;
  esac
done

read -r -a extensions <<< "$source_extensions_text"
extensions_csv="$(IFS=,; printf '%s' "${extensions[*]}")"
package_manager="$manifest_package_manager"
[[ -z "$package_manager" ]] && package_manager="not-declared"
framework="$manifest_framework"
[[ -z "$framework" ]] && framework="not-declared"

case "$manifest_has_ui" in
  ""|[Ff][Aa][Ll][Ss][Ee]) ui_capability=false ;;
  [Tt][Rr][Uu][Ee]) ui_capability=true ;;
  *) ui_capability=invalid ;;
esac

client_env_prefixes() {
  if [[ -n "$manifest_client_prefixes" ]]; then
    printf '%s' "${manifest_client_prefixes//,/ }"
    return 0
  fi
  case "$framework" in
    [Nn][Ee][Xx][Tt]|[Nn][Ee][Xx][Tt][Jj][Ss]|[Nn][Ee][Xx][Tt].[Jj][Ss])
      printf 'NEXT_PUBLIC_'
      ;;
    [Vv][Ii][Tt][Ee]|[Vv][Ii][Tt][Ee]-[Rr][Ee][Aa][Cc][Tt]|[Rr][Ee][Aa][Cc][Tt]-[Vv][Ii][Tt][Ee])
      printf 'VITE_'
      ;;
    *) printf 'NEXT_PUBLIC_ VITE_' ;;
  esac
}

echo "Secret scan targets: ${targets[*]}"
echo "Secret scan extensions: ${extensions[*]}"
echo "Manifest package manager: $package_manager"
echo "Manifest framework: $framework"

support_health_out="$(run_support --health-check 2>&1)"
support_health_rc=$?
if [[ "$support_health_rc" -ne 0 || "$support_health_out" != "scan-files:v2" ]]; then
  echo "FAIL: filesystem support helper health check failed (exit $support_health_rc, invalid handshake)"
  record_operation support_health ERROR
  exit 1
fi
record_operation support_health VERIFIED

# I-S1: unconditional positive engine handshake. Empty rc-0 output is not evidence
# that the runtime actually executed the engine; the exact versioned sentinel is.
engine_healthy=1
health_out="$(run_engine --health-check 2>&1)"
health_rc=$?
if [[ "$health_rc" -ne 0 ]]; then
  echo "FAIL: secret engine health check failed (exit $health_rc); scan results cannot be trusted"
  issues=$((issues + 1)); engine_healthy=0
  record_operation engine_health ERROR
  record_check engine_health ERROR
elif [[ "$health_out" != "extract-secrets:v1" ]]; then
  echo "FAIL: secret engine health check failed (invalid handshake); scan results cannot be trusted"
  issues=$((issues + 1)); engine_healthy=0
  record_operation engine_health ERROR
  record_check engine_health ERROR
else
  record_operation engine_health VERIFIED
  record_check engine_health VERIFIED
fi

# I-S1: determine the git state explicitly. The probe's result contract is strict:
# rc 0 with stdout EXACTLY `true` or `false`, or rc 128 whose stderr carries the
# canonical not-a-repository message (LC_ALL=C pins the locale), are the only
# confirmed answers. Anything else -- absent git (127), crashes, malformed success
# output -- is undetermined and must FAIL, never masquerade as "not a repo".
git_state=undetermined
git_probe_out="$(LC_ALL=C run_operation git rev-parse --is-inside-work-tree 2>&1)"
git_probe_rc=$?
if [[ "$git_probe_rc" -eq 0 ]]; then
  case "$git_probe_out" in
    true) git_state=repo ;;
    false) git_state=nonrepo ;;
  esac
elif [[ "$git_probe_rc" -eq 128 && "$git_probe_out" == *"not a git repository"* ]]; then
  git_state=nonrepo
fi
if [[ "$git_state" == undetermined ]]; then
  echo "FAIL: cannot determine git state (git rev-parse exit $git_probe_rc, unexpected result); refusing to skip git-backed checks"
  issues=$((issues + 1))
  record_operation git_state_probe ERROR
  record_check git_state ERROR
else
  record_operation git_state_probe VERIFIED
  record_check git_state VERIFIED
fi

# Scope guard: a scan that covers zero files must never report a clean PASS, and the
# canonical enumeration itself must succeed and return a strict numeric count.
missing_targets=()
existing_targets=()
invalid_targets=()
scope_state=VERIFIED
for target in "${targets[@]}"; do
  case "$target" in
    -*)
      invalid_targets+=("$target")
      scope_state=ERROR
      ;;
    *)
      if [[ -e "$target" ]]; then existing_targets+=("$target"); else missing_targets+=("$target"); fi
      ;;
  esac
done
scanned_count=0
scope_operation_state=ERROR
scope_rc=125
scope_count_out=""
if [[ "${#existing_targets[@]}" -gt 0 ]]; then
  scope_count_out="$(run_support --extensions "$extensions_csv" count ${existing_targets[@]+"${existing_targets[@]}"} 2>&1)"
  scope_rc=$?
  if [[ "$scope_rc" -eq 0 && "$scope_count_out" =~ ^[0-9]+$ ]]; then
    scanned_count="$scope_count_out"
    scope_operation_state=VERIFIED
  else
    echo "FAIL: canonical scope enumerator failed or returned malformed output (exit $scope_rc)"
    [[ -n "$scope_count_out" ]] && echo "$scope_count_out"
    issues=$((issues + 1)); scope_state=ERROR
  fi
fi
echo "Secret scan files scanned: $scanned_count"
if [[ "${#invalid_targets[@]}" -gt 0 ]]; then
  echo "FAIL: unsafe scan target(s) begin with '-': ${invalid_targets[*]}"
  issues=$((issues + 1)); scope_state=ERROR; scope_operation_state=ERROR
fi
if [[ "${#missing_targets[@]}" -gt 0 ]]; then
  echo "WARN: declared scan target(s) do not exist: ${missing_targets[*]}"
  issues=$((issues + 1)); scope_state=ERROR
fi
if [[ "$scanned_count" -eq 0 ]]; then
  echo "WARN: secret scan matched 0 files (targets=${targets[*]} extensions=${extensions[*]}); scope is empty, not clean"
  issues=$((issues + 1)); scope_state=ERROR
fi
record_operation scope_enumerate "$scope_operation_state"
record_check scan_scope "$scope_state"

# Worktree scan: broad case-insensitive byte keyword prefilter with an artifact-count
# envelope, then precise extraction+suppression in the
# bounded engine. The per-check PASS is a guarded conclusion: candidate search AND
# engine (health + per-path) must all have succeeded.
worktree_state=VERIFIED
if [[ "$engine_healthy" -ne 1 ]]; then
  echo "FAIL: secret engine is unhealthy; cannot verify worktree"
  issues=$((issues + 1)); worktree_state=ERROR
fi
worktree_search_out="$(run_support --extensions "$extensions_csv" worktree ${existing_targets[@]+"${existing_targets[@]}"} 2>&1)"
grep_rc=$?
raw_secrets=""
if [[ "$grep_rc" -eq 0 ]] && parse_search_result "$worktree_search_out" "$scanned_count"; then
  raw_secrets="$SEARCH_PAYLOAD"
  record_operation worktree_search VERIFIED
else
  echo "FAIL: worktree candidate search coverage mismatch or malformed output (exit $grep_rc); cannot verify worktree"
  issues=$((issues + 1)); worktree_state=ERROR
  record_operation worktree_search ERROR
fi
secrets=""
worktree_extract_state=NA
if [[ "$worktree_state" == ERROR ]]; then
  worktree_extract_state=ERROR
elif [[ "$engine_healthy" -eq 1 && -n "$raw_secrets" ]]; then
  secrets="$(printf '%s\n' "$raw_secrets" | run_engine_with_input)"
  engine_rc=$?
  if [[ "$engine_rc" -ne 0 ]]; then
    echo "FAIL: secret engine failed on worktree candidates (exit $engine_rc); cannot verify worktree"
    issues=$((issues + 1)); worktree_state=ERROR; worktree_extract_state=ERROR
  else
    worktree_extract_state=VERIFIED
  fi
fi
if [[ -n "$secrets" ]]; then
  echo "FAIL: hard-coded secrets found"
  printf '%s\n' "$secrets" | redact_file_matches "hard-coded secret"
  issues=$((issues + 1))
  [[ "$worktree_state" == VERIFIED ]] && worktree_state=FINDING
  [[ "$worktree_extract_state" == VERIFIED ]] && worktree_extract_state=FINDING
elif [[ "$worktree_state" == VERIFIED ]]; then
  echo "PASS: no hard-coded secrets"
fi
record_operation worktree_extract "$worktree_extract_state"
record_check worktree_scan "$worktree_state"

if [[ "$ui_capability" = "true" ]]; then
  client_state=VERIFIED
  read -r -a prefixes <<< "$(client_env_prefixes)"
  prefix_regex=""
  invalid_prefixes=()
  for prefix in "${prefixes[@]}"; do
    [[ -z "$prefix" ]] && continue
    if [[ ! "$prefix" =~ ^[A-Za-z_][A-Za-z0-9_]*_$ ]]; then
      invalid_prefixes+=("$prefix")
      continue
    fi
    if [[ -z "$prefix_regex" ]]; then
      prefix_regex="$prefix"
    else
      prefix_regex="$prefix_regex|$prefix"
    fi
  done
  if [[ "${#invalid_prefixes[@]}" -gt 0 ]]; then
    echo "FAIL: invalid client_env_prefixes value(s): ${invalid_prefixes[*]}"
    issues=$((issues + 1)); client_state=ERROR
  fi
  if [[ -z "$prefix_regex" ]]; then
    echo "FAIL: no valid client env prefixes configured for has_ui=true"
    issues=$((issues + 1)); client_state=ERROR
    prefix_regex='a^'
  fi
  echo "Client env prefixes: ${prefixes[*]}"
  client_search_out="$(run_support --extensions "$extensions_csv" --prefixes "$prefix_regex" \
    client ${existing_targets[@]+"${existing_targets[@]}"} 2>&1)"
  client_rc=$?
  client_secrets=""
  if [[ "$client_rc" -eq 0 ]] && parse_search_result "$client_search_out" "$scanned_count"; then
    client_secrets="$SEARCH_PAYLOAD"
    client_operation_state=VERIFIED
  else
    echo "FAIL: client-prefix search coverage mismatch or malformed output (exit $client_rc); cannot verify client exposure"
    issues=$((issues + 1)); client_state=ERROR
    client_operation_state=ERROR
  fi
  if [[ -n "$client_secrets" ]]; then
    echo "FAIL: sensitive client-exposed variables found"
    printf '%s\n' "$client_secrets" | redact_file_matches "client-exposed env"
    issues=$((issues + 1))
    [[ "$client_state" == VERIFIED ]] && client_state=FINDING
    [[ "$client_operation_state" == VERIFIED ]] && client_operation_state=FINDING
  elif [[ "$client_state" == VERIFIED ]]; then
    echo "PASS: no sensitive client-exposed variables"
  fi
  record_operation client_search "$client_operation_state"
  record_check client_exposure "$client_state"
elif [[ "$ui_capability" = "false" ]]; then
  echo "N/A: client-prefix scan N/A (has_ui=false)"
  record_operation client_search NA
  record_check client_exposure NA
else
  echo "FAIL: has_ui must be true or false"
  issues=$((issues + 1))
  record_operation client_search ERROR
  record_check client_exposure ERROR
fi

# Log hygiene: the VERDICT is advisory (findings only WARN and never block), but the
# EXECUTION INTEGRITY is mandatory -- an errored search verified nothing, so it is an
# ERROR that fails the scan, not a warning beside an overall PASS.
log_search_out="$(run_support --extensions "$extensions_csv" log ${existing_targets[@]+"${existing_targets[@]}"} 2>&1)"
log_rc=$?
log_secrets=""
log_search_valid=0
if [[ "$log_rc" -eq 0 ]] && parse_search_result "$log_search_out" "$scanned_count"; then
  log_secrets="$SEARCH_PAYLOAD"
  log_search_valid=1
fi
if [[ "$log_search_valid" -eq 1 && -n "$log_secrets" ]]; then
  echo "WARN: review possible secrets in logs"
  printf '%s\n' "$log_secrets" | redact_file_matches "secret-log"
  record_operation log_search VERIFIED
  record_check log_hygiene VERIFIED
elif [[ "$log_search_valid" -eq 1 ]]; then
  echo "PASS: no obvious secrets in logs"
  record_operation log_search VERIFIED
  record_check log_hygiene VERIFIED
else
  echo "FAIL: log-pattern search coverage mismatch or malformed output (exit $log_rc); cannot verify log hygiene"
  issues=$((issues + 1))
  record_operation log_search ERROR
  record_check log_hygiene ERROR
fi

# Use git's own ignore resolution, not a substring match on .gitignore: a rule of
# only `.env.example`, or a negation like `!.env`, must NOT count as ".env ignored".
# check-ignore rc 1 is a valid negative answer; rc > 1 is a git error.
if [[ "$git_state" == repo ]]; then
  run_operation git check-ignore -q .env
  ignore_rc=$?
  if [[ "$ignore_rc" -eq 0 ]]; then
    echo "PASS: .env is git-ignored"
    record_operation env_ignore VERIFIED
    record_check env_ignore VERIFIED
  elif [[ "$ignore_rc" -eq 1 ]]; then
    echo "FAIL: .env is not git-ignored; .env is not excluded by .gitignore (git check-ignore .env returned 1)"
    issues=$((issues + 1))
    record_operation env_ignore FINDING
    record_check env_ignore FINDING
  else
    echo "FAIL: git check-ignore failed (exit $ignore_rc); cannot verify .env ignore state"
    issues=$((issues + 1))
    record_operation env_ignore ERROR
    record_check env_ignore ERROR
  fi
elif [[ "$git_state" == nonrepo ]]; then
  echo "SKIP: .env ignore check (confirmed not a git work tree)"
  record_operation env_ignore NA
  record_check env_ignore NA
else
  # Undetermined git state: the git-state ERROR is the evidence; this check verified
  # nothing and must not claim PASS or SKIP.
  record_operation env_ignore ERROR
  record_check env_ignore ERROR
fi

# Staged scan materializes raw stage-0 index blobs for every changed path, including
# paths outside source_roots. It never trusts a workspace-controlled diff presentation
# (`.gitattributes`, textconv, binary classification). The canonical helper gets raw
# object IDs from the index and writes their blobs into a private directory; candidate
# search and extraction then use the same bounded contracts as the worktree path.
if [[ "$git_state" == repo ]]; then
  staged_state=VERIFIED
  if [[ "$engine_healthy" -ne 1 ]]; then
    echo "FAIL: secret engine is unhealthy; cannot verify staged content"
    issues=$((issues + 1)); staged_state=ERROR
  fi

  staged_dir="$(run_operation /usr/bin/mktemp -d /tmp/skill-commons-staged.XXXXXX 2>&1)"
  staged_temp_rc=$?
  if [[ "$staged_temp_rc" -ne 0 || -z "$staged_dir" || "$staged_dir" == *$'\n'* || ! -d "$staged_dir" || -L "$staged_dir" ]]; then
    echo "FAIL: cannot create private staged-index workspace (exit $staged_temp_rc); cannot verify staged content"
    issues=$((issues + 1)); staged_state=ERROR
    record_operation staged_temp_create ERROR
    staged_dir=""
  else
    record_operation staged_temp_create VERIFIED
  fi

  staged_count=0
  staged_materialize_state=ERROR
  if [[ -n "$staged_dir" ]]; then
    staged_count_out="$(run_support staged-materialize "$staged_dir" 2>&1)"
    staged_materialize_rc=$?
    if [[ "$staged_materialize_rc" -eq 0 && "$staged_count_out" =~ ^[0-9]+$ ]]; then
      staged_count="$staged_count_out"
      staged_materialize_state=VERIFIED
    else
      echo "FAIL: staged index materialization failed or returned malformed output (exit $staged_materialize_rc); cannot verify staged content"
      [[ -n "$staged_count_out" ]] && echo "$staged_count_out"
      issues=$((issues + 1)); staged_state=ERROR
    fi
  fi
  record_operation staged_materialize "$staged_materialize_state"

  staged_added=""
  staged_search_state=NA
  if [[ "$staged_materialize_state" == VERIFIED && "$staged_count" -gt 0 ]]; then
    staged_search_out="$(run_support staged "$staged_dir" 2>&1)"
    staged_search_rc=$?
    if [[ "$staged_search_rc" -eq 0 ]] && parse_search_result "$staged_search_out" "$staged_count"; then
      staged_added="$SEARCH_PAYLOAD"
      staged_search_state=VERIFIED
    else
      echo "FAIL: staged index search coverage mismatch or malformed output (exit $staged_search_rc); cannot verify staged content"
      issues=$((issues + 1)); staged_state=ERROR; staged_search_state=ERROR
      staged_added=""
    fi
  elif [[ "$staged_materialize_state" == ERROR ]]; then
    staged_search_state=ERROR
  fi
  record_operation staged_search "$staged_search_state"

  staged_secrets=""
  staged_extract_state=NA
  if [[ "$staged_state" == ERROR ]]; then
    staged_extract_state=ERROR
  elif [[ "$staged_search_state" == VERIFIED && "$engine_healthy" -eq 1 && -n "$staged_added" ]]; then
    staged_secrets="$(printf '%s\n' "$staged_added" | run_engine_with_input)"
    staged_engine_rc=$?
    if [[ "$staged_engine_rc" -ne 0 ]]; then
      echo "FAIL: secret engine failed on staged changes (exit $staged_engine_rc); cannot verify staged content"
      issues=$((issues + 1)); staged_state=ERROR; staged_extract_state=ERROR
    else
      staged_extract_state=VERIFIED
    fi
  fi
  if [[ -n "$staged_secrets" ]]; then
    echo "FAIL: secret found in staged changes"
    printf '%s\n' "$staged_secrets" | redact_file_matches "staged secret"
    issues=$((issues + 1))
    [[ "$staged_state" == VERIFIED ]] && staged_state=FINDING
    [[ "$staged_extract_state" == VERIFIED ]] && staged_extract_state=FINDING
  elif [[ "$staged_state" == VERIFIED ]]; then
    echo "PASS: no secrets in staged changes"
  fi
  record_operation staged_extract "$staged_extract_state"

  staged_cleanup_state=NA
  if [[ -n "$staged_dir" ]]; then
    run_operation /bin/rm -rf -- "$staged_dir"
    staged_cleanup_rc=$?
    if [[ "$staged_cleanup_rc" -eq 0 && ! -e "$staged_dir" ]]; then
      staged_cleanup_state=VERIFIED
    else
      echo "FAIL: cannot remove private staged-index workspace (exit $staged_cleanup_rc)"
      issues=$((issues + 1)); staged_state=ERROR; staged_cleanup_state=ERROR
    fi
  fi
  record_operation staged_cleanup "$staged_cleanup_state"
  record_check staged_scan "$staged_state"
elif [[ "$git_state" == nonrepo ]]; then
  echo "SKIP: staged scan (confirmed not a git work tree)"
  record_operation staged_temp_create NA
  record_operation staged_materialize NA
  record_operation staged_search NA
  record_operation staged_extract NA
  record_operation staged_cleanup NA
  record_check staged_scan NA
else
  record_operation staged_temp_create ERROR
  record_operation staged_materialize ERROR
  record_operation staged_search ERROR
  record_operation staged_extract ERROR
  record_operation staged_cleanup ERROR
  record_check staged_scan ERROR
fi

# ---- summary: derived from the protocol roster, not from scattered call sites ----
protocol_fail=$protocol_error
for required in $MANDATORY_OPERATIONS; do
  state=""
  for entry in $OPERATION_PROTOCOL; do
    case "$entry" in
      "$required":*) state="${entry#*:}" ;;
    esac
  done
  case "$state" in
    VERIFIED|NA) ;;
    FINDING|ERROR) protocol_fail=1 ;;
    *)
      echo "FAIL: mandatory operation '$required' recorded no result (protocol violation)"
      issues=$((issues + 1)); protocol_fail=1
      ;;
  esac
done
for required in $MANDATORY_CHECKS; do
  state=""
  for entry in $CHECK_PROTOCOL; do
    case "$entry" in
      "$required":*) state="${entry#*:}" ;;
    esac
  done
  case "$state" in
    VERIFIED|NA) ;;
    FINDING|ERROR) protocol_fail=1 ;;
    *)
      echo "FAIL: mandatory check '$required' recorded no result (protocol violation)"
      issues=$((issues + 1)); protocol_fail=1
      ;;
  esac
done
if [[ "$protocol_fail" -eq 0 && "$issues" -eq 0 ]]; then
  # Scoped, not comprehensive: this is a heuristic preflight whose PASS means every
  # MANDATORY check recorded VERIFIED or NA -- not that the repo is free of secrets.
  echo "Secret preflight result: PASS (all mandatory checks VERIFIED or NA)"
  exit 0
fi
[[ "$issues" -eq 0 ]] && issues=1
echo "FAIL: secret scan found $issues issue(s)"
exit "$issues"
