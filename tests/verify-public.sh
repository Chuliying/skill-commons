#!/usr/bin/env bash
# Fresh clean-public verification entry.
#
# This entry exports the current worktree, generates and commits a clean payload,
# then invokes its runner with explicit source scope. The outer entry is the
# public gate; inside the payload, source scope means the public tree.
# Only --cached may reuse an identical successful payload/toolchain verdict.
# Failed gates retain their temporary directory and print a retry command.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cache_file="$ROOT/.verify-cache/public-payload.digest"

usage() {
  cat <<'EOF'
usage: bash tests/verify-public.sh [--cached]

Run a fresh public export from the current worktree, generate its adapters,
commit the payload in a temporary repository, and verify its public tree.
--cached may reuse the suite verdict after generation and Git setup succeed.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
use_cache=0
if [ "${1:-}" = "--cached" ]; then use_cache=1; shift; fi
if [ "$#" -ne 0 ]; then
  echo "ERROR verify-public.sh: invalid selection: $1" >&2
  usage >&2
  exit 2
fi
if [ -n "${VERIFY_ROSTER_FILE:-}" ]; then
  echo "ERROR verify-public.sh: VERIFY_ROSTER_FILE is source-only; public verification always uses a fresh payload" >&2
  exit 2
fi

TEMP_PARENT="${TMPDIR:-/tmp}"
case "$TEMP_PARENT" in
  */) TEMP_TEMPLATE="${TEMP_PARENT}skill-commons-public.XXXXXX" ;;
  *) TEMP_TEMPLATE="${TEMP_PARENT}/skill-commons-public.XXXXXX" ;;
esac
GATE_DIR="$(mktemp -d "$TEMP_TEMPLATE" 2>/dev/null)" || {
  echo "ERROR verify-public.sh: cannot create temporary gate directory" >&2
  exit 3
}
TARGET="$GATE_DIR/payload"
mkdir -p "$TARGET"
KEEP=0
if [ "${VERIFY_PUBLIC_KEEP:-0}" = "1" ]; then
  KEEP=1
fi
cleanup() {
  cleanup_rc=$?
  # Setup/export failures must invalidate an old successful suite verdict too.
  if [ "$cleanup_rc" -ne 0 ] && [ ! -L "$ROOT/.verify-cache" ]; then
    rm -f "$cache_file"
  fi
  if [ "$KEEP" -eq 0 ]; then
    rm -rf "$GATE_DIR"
  fi
}
trap cleanup EXIT

export_log="$GATE_DIR/export.stdout.log"
export_err="$GATE_DIR/export.stderr.log"
if ! bash "$ROOT/scripts/export-public.sh" "$TARGET" --force --include-worktree >"$export_log" 2>"$export_err"; then
  KEEP=1
  echo "PUBLIC_DIAGNOSTICS dir=$GATE_DIR target=$TARGET"
  echo "RETRY: bash tests/verify-public.sh"
  echo "export stderr (last 20 lines):"
  tail -20 "$export_err"
  exit 1
fi

# Identify the exported input before generation adds adapters. Cache reuse is
# considered only after generation and Git setup succeed below. Identity errors
# force a real suite run; release/default public verification never hits.
payload_id="$(python3 - "$TARGET" "$BASH_VERSION" <<'CACHEPY'
import hashlib, os, pathlib, platform, stat, sys
root=pathlib.Path(sys.argv[1]); h=hashlib.sha256()
try:
    for path in sorted(root.rglob('*')):
        if '.git' in path.relative_to(root).parts: continue
        info=path.lstat()
        if stat.S_ISDIR(info.st_mode): continue
        data=os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
        h.update(str(path.relative_to(root)).encode()+b'\0')
        h.update(str(stat.S_IFMT(info.st_mode) | (info.st_mode & 0o111)).encode()+b'\0')
        h.update(hashlib.sha256(data).digest())
    h.update((sys.version+sys.argv[2]+platform.platform()).encode())
    print(h.hexdigest())
except OSError:
    pass
CACHEPY
)"
generate_log="$GATE_DIR/generate.stdout.log"
generate_err="$GATE_DIR/generate.stderr.log"
if ! (cd "$TARGET" && PROFILE=all bash bootstrap/generate.sh) >"$generate_log" 2>"$generate_err"; then
  KEEP=1
  echo "PUBLIC_DIAGNOSTICS dir=$GATE_DIR target=$TARGET"
  echo "RETRY: bash tests/verify-public.sh"
  echo "generate stderr (last 20 lines):"
  tail -20 "$generate_err"
  exit 1
fi

# A local commit gives the public gate the same clean payload boundary used in
# CI, while all Git state remains inside the temporary target.
if ! git -C "$TARGET" init -q ||
   ! git -C "$TARGET" config user.email "skill-commons-public@example.invalid" ||
   ! git -C "$TARGET" config user.name "skill-commons-public" ||
   ! env GIT_CONFIG_GLOBAL=/dev/null git -C "$TARGET" add -A ||
   ! git -C "$TARGET" commit -qm "fresh public verification payload"; then
  KEEP=1
  echo "PUBLIC_DIAGNOSTICS dir=$GATE_DIR target=$TARGET"
  echo "RETRY: bash tests/verify-public.sh"
  echo "target commit failed"
  exit 1
fi

# Cache only the expensive suite; setup and commit are always checked.
if [ "$use_cache" -eq 1 ] && [ "${SKILL_COMMONS_VERIFY_NO_CACHE:-0}" != "1" ] &&
   [ ! -L "$ROOT/.verify-cache" ] && [ -n "$payload_id" ] && [ -f "$cache_file" ] && [ ! -L "$cache_file" ] &&
   [ "$(cat "$cache_file")" = "$payload_id" ]; then
  if [ "$KEEP" -eq 1 ]; then echo "PUBLIC_LOGS dir=$GATE_DIR target=$TARGET"; fi
  echo "PUBLIC_GATE scope=public reused=identical-payload-and-toolchain digest=$payload_id rc=0 (no fresh public suite executed)"
  exit 0
fi
# A failed fresh run must not leave a previously cached verdict eligible.
if [ ! -L "$ROOT/.verify-cache" ]; then rm -f "$cache_file"; fi

verify_log="$GATE_DIR/verify.stdout.log"
verify_err="$GATE_DIR/verify.stderr.log"
if ! (cd "$TARGET" && unset VERIFY_ACTIVE && VERIFY_SCOPE=source VERIFY_LOG_ROOT="$GATE_DIR" bash tests/verify.sh --scope source) >"$verify_log" 2>"$verify_err"; then
  KEEP=1
  echo "PUBLIC_DIAGNOSTICS dir=$GATE_DIR target=$TARGET"
  echo "RETRY: bash tests/verify-public.sh"
  echo "verify stdout:"
  cat "$verify_log"
  echo "verify stderr:"
  cat "$verify_err"
  exit 1
fi

inner_summary="$(grep '^SUMMARY ' "$verify_log" | tail -1)"
if [ -z "$inner_summary" ]; then
  KEEP=1
  echo "PUBLIC_DIAGNOSTICS dir=$GATE_DIR target=$TARGET"
  echo "RETRY: bash tests/verify-public.sh"
  echo "verify output did not contain a summary"
  exit 1
fi
if [ "$KEEP" -eq 1 ]; then
  echo "PUBLIC_LOGS dir=$GATE_DIR target=$TARGET"
fi
if [ -n "$payload_id" ] && [ ! -L "$ROOT/.verify-cache" ]; then
  mkdir -p "$ROOT/.verify-cache"
  cache_temp="$(mktemp "$ROOT/.verify-cache/public-payload.XXXXXX")"
  if [ -n "$cache_temp" ]; then
    printf '%s\n' "$payload_id" > "$cache_temp" && mv "$cache_temp" "$cache_file"
  fi
fi
echo "PUBLIC_GATE scope=public inner=[$inner_summary] rc=0"
exit 0
