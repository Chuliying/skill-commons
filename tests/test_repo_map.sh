#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REPO/codebase-understanding/scripts/repo_map.py"
TMP="$(mktemp -d)"
ERR="$TMP/stderr"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

if [ ! -f "$TOOL" ]; then
  fail "Repo Map entrypoint exists"
  finish
  exit $?
fi

init_repo() {
  local path="$1"
  mkdir -p "$path"
  git init -q "$path"
  git -C "$path" config user.name "Repo Map Fixture"
  git -C "$path" config user.email "repo-map@example.invalid"
}

run_tool() {
  local repo="$1"
  shift
  : > "$ERR"
  run_out="$(cd "$repo" && python3 "$TOOL" "$@" 2>"$ERR")"
  run_rc=$?
}

json_field() {
  local document="$1" field="$2"
  printf '%s' "$document" | python3 -c \
    'import json, sys; value=json.load(sys.stdin); print(value[sys.argv[1]])' "$field"
}

assert_compact_json() {
  local document="$1" message="$2"
  if printf '%s' "$document" | python3 -c \
    'import json, sys; raw=sys.stdin.read(); value=json.loads(raw); assert "\n" not in raw and raw == json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)' \
    >/dev/null 2>&1; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $message"
  else
    fail "$message"
  fi
}

expected_cache_path() {
  local repo="$1" raw
  raw="$(git -C "$repo" rev-parse --git-path skill-commons/repo-map/v1)"
  python3 -c 'from pathlib import Path; import sys; p=Path(sys.argv[2]); print((p if p.is_absolute() else Path(sys.argv[1])/p).resolve())' "$repo" "$raw"
}

wait_for_path() {
  local path="$1" attempts="${2:-500}"
  while [ ! -e "$path" ] && [ "$attempts" -gt 0 ]; do
    sleep 0.01
    attempts=$((attempts-1))
  done
  [ -e "$path" ]
}

assert_path_stays_missing() {
  local path="$1" message="$2" attempts=100
  while [ ! -e "$path" ] && [ "$attempts" -gt 0 ]; do
    sleep 0.01
    attempts=$((attempts-1))
  done
  if [ ! -e "$path" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $message"
  else
    fail "$message"
  fi
}

CONCURRENCY_DRIVER="$TMP/repo-map-concurrency.py"
cat > "$CONCURRENCY_DRIVER" <<'PY'
import importlib.util
import os
from pathlib import Path
import sys
import time

sys.dont_write_bytecode = True
tool, repo, mode, root, ready_raw, observed_raw, release_raw = sys.argv[1:]
ready = Path(ready_raw)
observed = Path(observed_raw)
release = Path(release_raw) if release_raw else None

spec = importlib.util.spec_from_file_location("repo_map_concurrency", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def signal(path):
    path.touch()

if mode == "holding-scan":
    original_atomic_replace = module._atomic_replace
    calls = 0

    def holding_atomic_replace(cache_fd, name, data):
        global calls
        original_atomic_replace(cache_fd, name, data)
        calls += 1
        if calls == 1:
            signal(observed)
            deadline = time.monotonic() + 15
            while not release.exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError("timed out waiting to release held Repo Map writer")
                time.sleep(0.01)

    module._atomic_replace = holding_atomic_replace
elif mode == "scan-probe":
    original_write_cache = module._write_cache
    original_atomic_replace = module._atomic_replace

    def ready_write_cache(*args, **kwargs):
        signal(ready)
        return original_write_cache(*args, **kwargs)

    def observed_atomic_replace(*args, **kwargs):
        signal(observed)
        return original_atomic_replace(*args, **kwargs)

    module._write_cache = ready_write_cache
    module._atomic_replace = observed_atomic_replace
elif mode == "status-probe":
    original_status = module._status
    original_read_meta = module._read_meta

    def ready_status(*args, **kwargs):
        signal(ready)
        return original_status(*args, **kwargs)

    def observed_read_meta(*args, **kwargs):
        signal(observed)
        return original_read_meta(*args, **kwargs)

    module._status = ready_status
    module._read_meta = observed_read_meta
else:
    raise RuntimeError(f"unknown concurrency mode: {mode}")

os.chdir(repo)
command = "status" if mode == "status-probe" else "scan"
raise SystemExit(module.main([command, "--root", root]))
PY

FIXTURE="$TMP/repository with spaces"
init_repo "$FIXTURE"
mkdir -p "$FIXTURE/docs" "$FIXTURE/src" "$FIXTURE/web"

cat > "$FIXTURE/src/app.py" <<'PY'
import os
import pkg.service as service
from pkg import Thing
from . import local
if TYPE_CHECKING:
    import typing_only
def lazy():
    import inner
import os
PY
cat > "$FIXTURE/src/bad.py" <<'PY'
def broken(:
    pass
PY
cat > "$FIXTURE/web/app.ts" <<'TS'
import primary from "one";
import "side";
export { value } from 'three';
const req = require("four");
const dyn = import("five");
import Alias = require("six");
const reqAgain = require("four");
import { split } from
  "split-specifier";
const computed = require(moduleName);
const template = import(`template-name`);
import {
  multiline
} from "multiline-tail";
// require("commented-out")
TS
printf '# fixture\n' > "$FIXTURE/README.md"
printf '# inventory only\n' > "$FIXTURE/docs/guide.md"
printf 'package main\n' > "$FIXTURE/unsupported.go"
printf 'ignored = true\n' > "$FIXTURE/ignored.py"
printf 'ignored.py\n' > "$FIXTURE/.gitignore"
printf '\377' > "$FIXTURE/src/bad_encoding.py"
printf 'space_value = 1\n' > "$FIXTURE/src/space name.py"
printf 'unicode_value = 1\n' > "$FIXTURE/src/資料.py"
newline_path=$'src/line\nbreak.py'
printf 'newline_value = 1\n' > "$FIXTURE/$newline_path"
dd if=/dev/zero of="$FIXTURE/src/large.py" bs=1048576 count=2 2>/dev/null
printf x >> "$FIXTURE/src/large.py"
printf 'TOP_SECRET = True\nimport must_not_be_read\n' > "$TMP/outside.py"
ln -s "$TMP/outside.py" "$FIXTURE/src/outside.py"

git -C "$FIXTURE" add -f .gitignore
git -C "$FIXTURE" add README.md docs unsupported.go src web
git -C "$FIXTURE" commit -qm "fixture"
printf 'untracked_value = 1\n' > "$FIXTURE/src/untracked.py"

run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "status exits 1 when cache is missing"
assert_eq "missing" "$(json_field "$run_out" state)" "status reports missing"
assert_eq "$(expected_cache_path "$FIXTURE")" "$(json_field "$run_out" cache_path)" "missing status reports actual cache path"
assert_compact_json "$run_out" "missing status is one compact JSON document"

run_tool "$FIXTURE" scan
assert_eq "0" "$run_rc" "scan succeeds with partial coverage"
assert_eq "fresh" "$(json_field "$run_out" state)" "scan reports fresh artifacts"
assert_eq "partial" "$(json_field "$run_out" coverage)" "unsupported and skipped files are visible as partial coverage"
assert_compact_json "$run_out" "scan stdout is one compact JSON document"
CACHE="$(json_field "$run_out" cache_path)"
assert_eq "$(expected_cache_path "$FIXTURE")" "$CACHE" "scan reports actual Git-private cache path"
assert_file "$CACHE/meta.json" "scan writes meta.json"
assert_file "$CACHE/inventory.jsonl" "scan writes inventory.jsonl"
assert_file "$CACHE/edges.jsonl" "scan writes edges.jsonl"
if [ ! -e "$FIXTURE/.agent/cache" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scan does not write a worktree cache"
else
  fail "scan does not write a worktree cache"
fi

python3 - "$CACHE" "$newline_path" <<'PY'
import json
from pathlib import Path
import sys

cache = Path(sys.argv[1])
newline_path = sys.argv[2]
inventory = [json.loads(line) for line in (cache / "inventory.jsonl").read_text().splitlines()]
edges = [json.loads(line) for line in (cache / "edges.jsonl").read_text().splitlines()]
meta = json.loads((cache / "meta.json").read_text())
by_path = {record["path"]: record for record in inventory}

assert "ignored.py" not in by_path
assert "src/untracked.py" in by_path
assert "src/space name.py" in by_path
assert "src/資料.py" in by_path
assert newline_path in by_path
assert by_path["src/outside.py"]["kind"] == "symlink"
assert by_path["src/outside.py"]["analysis"]["status"] == "unsupported"
assert by_path["src/large.py"]["analysis"]["status"] == "skipped_too_large"
assert by_path["src/bad.py"]["analysis"]["status"] == "syntax_error"
assert by_path["src/bad_encoding.py"]["analysis"]["status"] == "decode_error"
assert by_path["src/app.py"]["analysis"] == {"extractor": "python_ast_v1", "status": "ok"}
assert by_path["README.md"]["content_sha256"] is None
assert all(not record["path"].startswith("/") for record in inventory)

edge_map = {(edge["from"], edge["specifier"]): edge for edge in edges}
assert edge_map[("src/app.py", "os")]["locations"] == [1, 9]
assert edge_map[("src/app.py", "pkg.service")]["precision"] == "syntax_exact"
assert edge_map[("src/app.py", "pkg")]["locations"] == [3]
assert edge_map[("src/app.py", ".")]["locations"] == [4]
assert edge_map[("src/app.py", "typing_only")]["locations"] == [6]
assert edge_map[("src/app.py", "inner")]["locations"] == [8]
assert not any(edge["from"] == "src/outside.py" for edge in edges)

js_specs = {edge["specifier"]: edge for edge in edges if edge["from"] == "web/app.ts"}
assert set(js_specs) == {"one", "side", "three", "four", "five", "six", "multiline-tail"}
assert js_specs["four"]["locations"] == [4, 7]
assert all(edge["precision"] == "textual_candidate" for edge in js_specs.values())
assert all(edge["kind"] == "module_reference" for edge in edges)

assert meta["schema"] == "repo-map/v1"
assert meta["scan_root"] == "."
assert meta["coverage"]["state"] == "partial"
assert set(meta["artifacts"]) == {"edges_sha256", "inventory_sha256"}
assert "generated_at" not in meta
assert "elapsed" not in meta
assert "pid" not in meta
assert not any(str(cache.parent.parent.parent) in line for line in (cache / "meta.json").read_text().splitlines())
PY
if [ "$?" = 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: inventory, extractor, precision, and meta contracts"
else
  fail "inventory, extractor, precision, and meta contracts"
fi

run_tool "$FIXTURE" scan --root web
assert_eq "0" "$run_rc" "supported-only scan succeeds"
assert_eq "complete" "$(json_field "$run_out" coverage)" "supported-only scan has complete coverage"
run_tool "$FIXTURE" status --root web
assert_eq "0" "$run_rc" "complete cache is fresh"
run_tool "$FIXTURE" scan --root docs
assert_eq "0" "$run_rc" "inventory-only scan succeeds"
assert_eq "inventory_only" "$(json_field "$run_out" coverage)" "unsupported-only scan is inventory_only"
run_tool "$FIXTURE" status --root docs
assert_eq "0" "$run_rc" "inventory-only cache can still be fresh"
run_tool "$FIXTURE" scan
assert_eq "0" "$run_rc" "full-scope cache is restored after coverage fixtures"

cp "$CACHE/meta.json" "$TMP/meta.first"
cp "$CACHE/inventory.jsonl" "$TMP/inventory.first"
cp "$CACHE/edges.jsonl" "$TMP/edges.first"
run_tool "$FIXTURE" scan
if cmp -s "$TMP/meta.first" "$CACHE/meta.json" && \
   cmp -s "$TMP/inventory.first" "$CACHE/inventory.jsonl" && \
   cmp -s "$TMP/edges.first" "$CACHE/edges.jsonl"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: repeated scan is byte-identical"
else
  fail "repeated scan is byte-identical"
fi

STATUS_HOLD_READY="$TMP/status-hold-ready"
STATUS_HOLD_RELEASE="$TMP/status-hold-release"
STATUS_HOLD_WRITTEN="$TMP/status-hold-written"
STATUS_PROBE_READY="$TMP/status-probe-ready"
STATUS_PROBE_READ="$TMP/status-probe-read"
python3 "$CONCURRENCY_DRIVER" "$TOOL" "$FIXTURE" holding-scan src \
  "$STATUS_HOLD_READY" "$STATUS_HOLD_WRITTEN" "$STATUS_HOLD_RELEASE" \
  >"$TMP/status-hold.out" 2>"$TMP/status-hold.err" &
status_hold_pid=$!
if wait_for_path "$STATUS_HOLD_WRITTEN"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: controlled writer pauses after its first artifact replace"
else
  fail "controlled writer pauses after its first artifact replace"
fi
python3 "$CONCURRENCY_DRIVER" "$TOOL" "$FIXTURE" status-probe src \
  "$STATUS_PROBE_READY" "$STATUS_PROBE_READ" "" \
  >"$TMP/status-probe.out" 2>"$TMP/status-probe.err" &
status_probe_pid=$!
if wait_for_path "$STATUS_PROBE_READY"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: concurrent status reaches the cache read boundary"
else
  fail "concurrent status reaches the cache read boundary"
fi
assert_path_stays_missing "$STATUS_PROBE_READ" \
  "status waits instead of reading a partially published generation"
touch "$STATUS_HOLD_RELEASE"
wait "$status_hold_pid"
status_hold_rc=$?
wait "$status_probe_pid"
status_probe_rc=$?
assert_eq "0" "$status_hold_rc" "held scan completes after release"
assert_eq "0" "$status_probe_rc" "waiting status completes after writer release"
assert_eq "fresh" "$(json_field "$(cat "$TMP/status-probe.out")" state)" \
  "waiting status observes the completed generation"

SCAN_HOLD_READY="$TMP/scan-hold-ready"
SCAN_HOLD_RELEASE="$TMP/scan-hold-release"
SCAN_HOLD_WRITTEN="$TMP/scan-hold-written"
SCAN_PROBE_READY="$TMP/scan-probe-ready"
SCAN_PROBE_WRITE="$TMP/scan-probe-write"
python3 "$CONCURRENCY_DRIVER" "$TOOL" "$FIXTURE" holding-scan src \
  "$SCAN_HOLD_READY" "$SCAN_HOLD_WRITTEN" "$SCAN_HOLD_RELEASE" \
  >"$TMP/scan-hold.out" 2>"$TMP/scan-hold.err" &
scan_hold_pid=$!
if wait_for_path "$SCAN_HOLD_WRITTEN"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: controlled scan holds the publication boundary"
else
  fail "controlled scan holds the publication boundary"
fi
python3 "$CONCURRENCY_DRIVER" "$TOOL" "$FIXTURE" scan-probe web \
  "$SCAN_PROBE_READY" "$SCAN_PROBE_WRITE" "" \
  >"$TMP/scan-probe.out" 2>"$TMP/scan-probe.err" &
scan_probe_pid=$!
if wait_for_path "$SCAN_PROBE_READY"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: second scan reaches the cache publication boundary"
else
  fail "second scan reaches the cache publication boundary"
fi
assert_path_stays_missing "$SCAN_PROBE_WRITE" \
  "a second scan waits before publishing any artifact"
touch "$SCAN_HOLD_RELEASE"
wait "$scan_hold_pid"
scan_hold_rc=$?
wait "$scan_probe_pid"
scan_probe_rc=$?
assert_eq "0" "$scan_hold_rc" "first concurrent scan completes after release"
assert_eq "0" "$scan_probe_rc" "serialized second scan completes"
run_tool "$FIXTURE" status --root web
assert_eq "0" "$run_rc" "serialized scans leave one complete fresh generation"

run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "status detects a different requested root after concurrency fixtures"
run_tool "$FIXTURE" scan
assert_eq "0" "$run_rc" "full-scope cache is restored after concurrency fixtures"
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "status exits 0 for fresh partial cache"
assert_eq "fresh" "$(json_field "$run_out" state)" "status separates freshness from coverage"
assert_eq "partial" "$(json_field "$run_out" coverage)" "fresh cache retains partial coverage"

rm "$FIXTURE/src/outside.py"
printf 'import replacement_regular_file\n' > "$FIXTURE/src/outside.py"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "replacing a tracked symlink with a regular source is stale"
rm "$FIXTURE/src/outside.py"
ln -s "$TMP/outside.py" "$FIXTURE/src/outside.py"
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "restoring the tracked symlink restores freshness"

git -C "$FIXTURE" add src/untracked.py
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "staging unchanged bytes does not make cache stale"
git -C "$FIXTURE" commit -qm "track existing input"
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "HEAD-only change with identical extraction inputs stays fresh"

printf '\nimport dirty_change\n' >> "$FIXTURE/src/app.py"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "dirty supported source exits 1"
assert_eq "stale" "$(json_field "$run_out" state)" "dirty supported source is stale"
git -C "$FIXTURE" add src/app.py
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "staged supported source remains stale"
run_tool "$FIXTURE" scan
assert_eq "0" "$run_rc" "rescan refreshes dirty supported source"

printf 'README content changed without changing inventory\n' > "$FIXTURE/README.md"
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "unsupported file content change stays fresh"
printf 'new inventory member\n' > "$FIXTURE/SECOND.md"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "new unsupported path still invalidates inventory"
rm "$FIXTURE/SECOND.md"
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "removing unscanned path restores the prior input digest"

mv "$FIXTURE/src/untracked.py" "$FIXTURE/src/renamed.py"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "rename is stale"
mv "$FIXTURE/src/renamed.py" "$FIXTURE/src/untracked.py"
run_tool "$FIXTURE" status
assert_eq "0" "$run_rc" "restoring path restores freshness"
rm "$FIXTURE/src/untracked.py"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "tracked deletion is stale"
run_tool "$FIXTURE" scan
python3 - "$CACHE/inventory.jsonl" <<'PY'
import json
from pathlib import Path
import sys
records = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
record = next(value for value in records if value["path"] == "src/untracked.py")
assert record["kind"] == "missing"
assert record["analysis"]["status"] == "missing"
assert record["content_sha256"] is None
PY
if [ "$?" = 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scan records tracked missing input without fabricating a hash"
else
  fail "scan records tracked missing input without fabricating a hash"
fi
printf 'untracked_value = 1\n' > "$FIXTURE/src/untracked.py"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "restoring content stales a cache scanned while missing"
run_tool "$FIXTURE" scan
assert_eq "0" "$run_rc" "rescan refreshes restored tracked content"

cp -R "$FIXTURE" "$TMP/relocated repository"
RELOCATED="$TMP/relocated repository"
run_tool "$RELOCATED" status
assert_eq "0" "$run_rc" "cache remains fresh after repository relocation"
assert_eq "$(expected_cache_path "$RELOCATED")" "$(json_field "$run_out" cache_path)" "relocated status reports relocated cache path"
if python3 - "$FIXTURE" "$(expected_cache_path "$RELOCATED")" <<'PY'
from pathlib import Path
import sys
needle = sys.argv[1].encode()
assert all(needle not in path.read_bytes() for path in Path(sys.argv[2]).iterdir() if path.is_file())
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: cache artifacts contain no repository absolute path"
else
  fail "cache artifacts contain no repository absolute path"
fi

run_tool "$FIXTURE" scan --root src
assert_eq "0" "$run_rc" "subpath scan succeeds"
assert_eq "src" "$(json_field "$run_out" scan_root)" "subpath is normalized in output"
printf 'web-only change\n' >> "$FIXTURE/web/app.ts"
run_tool "$FIXTURE" status --root src
assert_eq "0" "$run_rc" "out-of-scope source change does not stale subpath cache"
printf '\nimport scoped_change\n' >> "$FIXTURE/src/app.py"
run_tool "$FIXTURE" status --root src
assert_eq "1" "$run_rc" "in-scope source change stales subpath cache"
run_tool "$FIXTURE" status --root web
assert_eq "1" "$run_rc" "different requested root is stale"
run_tool "$FIXTURE" status --root ../
assert_eq "2" "$run_rc" "root escaping worktree is rejected"
assert_eq "error" "$(json_field "$run_out" state)" "invalid root has machine-readable error state"

run_tool "$FIXTURE" scan
printf '\n' >> "$CACHE/inventory.jsonl"
run_tool "$FIXTURE" status
assert_eq "2" "$run_rc" "checksum mismatch exits 2"
assert_eq "corrupt" "$(json_field "$run_out" state)" "checksum mismatch is corrupt"
run_tool "$FIXTURE" scan
python3 - "$CACHE" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
cache = Path(sys.argv[1])
raw = b"{}\n"
(cache / "inventory.jsonl").write_bytes(raw)
meta_path = cache / "meta.json"
meta = json.loads(meta_path.read_text())
meta["artifacts"]["inventory_sha256"] = "sha256:" + hashlib.sha256(raw).hexdigest()
meta_path.write_text(json.dumps(meta, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
PY
run_tool "$FIXTURE" status
assert_eq "2" "$run_rc" "invalid inventory schema exits 2 even with matching checksum"
assert_eq "corrupt" "$(json_field "$run_out" state)" "invalid inventory schema is corrupt"
run_tool "$FIXTURE" scan
python3 - "$CACHE/meta.json" <<'PY'
import json
from pathlib import Path
import sys
p = Path(sys.argv[1])
data = json.loads(p.read_text())
data["schema"] = "repo-map/v999"
p.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
PY
run_tool "$FIXTURE" status
assert_eq "2" "$run_rc" "schema mismatch exits 2"
assert_eq "incompatible" "$(json_field "$run_out" state)" "schema mismatch is incompatible"
run_tool "$FIXTURE" scan
rm "$CACHE/meta.json"
run_tool "$FIXTURE" status
assert_eq "2" "$run_rc" "interrupted artifact set exits 2"
assert_eq "corrupt" "$(json_field "$run_out" state)" "missing completion marker cannot look fresh"
rm -rf "$CACHE"
run_tool "$FIXTURE" status
assert_eq "1" "$run_rc" "removed cache returns to missing"
mkdir -p "$CACHE"
run_tool "$FIXTURE" status
assert_eq "2" "$run_rc" "empty existing cache exits 2"
assert_eq "corrupt" "$(json_field "$run_out" state)" "empty existing cache lacks a completion marker"
rm -rf "$CACHE"

GIT_PRIVATE_ROOT="$(git -C "$FIXTURE" rev-parse --absolute-git-dir)"
ANCESTOR_VICTIM="$TMP/cache-ancestor-victim"
mkdir -p "$ANCESTOR_VICTIM"
rm -rf "$GIT_PRIVATE_ROOT/skill-commons"
ln -s "$ANCESTOR_VICTIM" "$GIT_PRIVATE_ROOT/skill-commons"
run_tool "$FIXTURE" scan
assert_eq "2" "$run_rc" "scan rejects a symlink ancestor below the Git-private root"
assert_eq "error" "$(json_field "$run_out" state)" "symlink ancestor failure is machine-readable"
assert_eq "$GIT_PRIVATE_ROOT/skill-commons/repo-map/v1" "$(json_field "$run_out" cache_path)" "symlink ancestor output keeps the lexical Git-private cache path"
if [ -z "$(find "$ANCESTOR_VICTIM" -mindepth 1 -print -quit)" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: symlink ancestor scan writes no victim files"
else
  fail "symlink ancestor scan writes no victim files"
fi
rm "$GIT_PRIVATE_ROOT/skill-commons"
rm -rf "$ANCESTOR_VICTIM/repo-map"

LEAF_VICTIM="$TMP/cache-leaf-victim"
mkdir -p "$GIT_PRIVATE_ROOT/skill-commons/repo-map" "$LEAF_VICTIM"
ln -s "$LEAF_VICTIM" "$GIT_PRIVATE_ROOT/skill-commons/repo-map/v1"
run_tool "$FIXTURE" scan
assert_eq "2" "$run_rc" "scan rejects a symlink cache leaf"
assert_eq "error" "$(json_field "$run_out" state)" "symlink cache leaf failure is machine-readable"
assert_eq "$GIT_PRIVATE_ROOT/skill-commons/repo-map/v1" "$(json_field "$run_out" cache_path)" "symlink leaf output keeps the lexical Git-private cache path"
if [ -z "$(find "$LEAF_VICTIM" -mindepth 1 -print -quit)" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: symlink leaf scan writes no victim files"
else
  fail "symlink leaf scan writes no victim files"
fi
rm "$GIT_PRIVATE_ROOT/skill-commons/repo-map/v1"
rm -rf "$LEAF_VICTIM"/*

LOCK_VICTIM="$TMP/cache-lock-victim"
LOCK_PATH="$GIT_PRIVATE_ROOT/skill-commons/repo-map/.v1.lock"
printf 'lock-victim-sentinel\n' > "$LOCK_VICTIM"
rm -f "$LOCK_PATH"
ln -s "$LOCK_VICTIM" "$LOCK_PATH"
run_tool "$FIXTURE" scan
assert_eq "2" "$run_rc" "scan rejects a symlink at the per-cache lock path"
assert_eq "error" "$(json_field "$run_out" state)" "unsafe lock path failure is machine-readable"
if [ "$(cat "$LOCK_VICTIM")" = "lock-victim-sentinel" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: unsafe lock path scan does not write through the symlink"
else
  fail "unsafe lock path scan does not write through the symlink"
fi
rm "$LOCK_PATH"

LINK_MAIN="$TMP/linked-main"
LINKED="$TMP/linked-worktree"
init_repo "$LINK_MAIN"
printf 'import linked\n' > "$LINK_MAIN/main.py"
git -C "$LINK_MAIN" add main.py
git -C "$LINK_MAIN" commit -qm "linked base"
git -C "$LINK_MAIN" worktree add -q -b linked-fixture "$LINKED"
run_tool "$LINKED" scan
assert_eq "0" "$run_rc" "scan works in linked worktree"
LINK_CACHE="$(json_field "$run_out" cache_path)"
assert_eq "$(expected_cache_path "$LINKED")" "$LINK_CACHE" "linked worktree uses its Git-private cache path"
assert_contains "$LINK_CACHE" "/worktrees/" "linked worktree cache is worktree-scoped"
run_tool "$LINKED" status
assert_eq "0" "$run_rc" "linked worktree status is fresh"

SUB_SOURCE="$TMP/sub-source"
SUPER="$TMP/super"
init_repo "$SUB_SOURCE"
printf 'import nested_dependency\n' > "$SUB_SOURCE/nested.py"
git -C "$SUB_SOURCE" add nested.py
git -C "$SUB_SOURCE" commit -qm "submodule source"
init_repo "$SUPER"
printf 'import super_dependency\n' > "$SUPER/super.py"
git -C "$SUPER" add super.py
git -C "$SUPER" commit -qm "super base"
git -C "$SUPER" -c protocol.file.allow=always submodule add -q "$SUB_SOURCE" vendor/dep
git -C "$SUPER" commit -qm "add submodule"
run_tool "$SUPER" scan
assert_eq "0" "$run_rc" "superproject scan succeeds with submodule"
SUPER_CACHE="$(json_field "$run_out" cache_path)"
python3 - "$SUPER_CACHE/inventory.jsonl" <<'PY'
import json
from pathlib import Path
import sys
records = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
by_path = {record["path"]: record for record in records}
assert by_path["vendor/dep"]["kind"] == "submodule"
assert "vendor/dep/nested.py" not in by_path
PY
if [ "$?" = 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: superproject records but does not recurse into submodule"
else
  fail "superproject records but does not recurse into submodule"
fi
run_tool "$SUPER/vendor/dep" scan
assert_eq "0" "$run_rc" "submodule can be scanned as its own Git worktree"
SUB_CACHE="$(json_field "$run_out" cache_path)"
assert_eq "$(expected_cache_path "$SUPER/vendor/dep")" "$SUB_CACHE" "submodule uses Git module-private cache path"
assert_contains "$SUB_CACHE" "/.git/modules/" "submodule cache is outside its worktree"
run_tool "$SUPER/vendor/dep" status
assert_eq "0" "$run_rc" "submodule-local cache is fresh"

NON_GIT="$TMP/not-a-repository"
mkdir -p "$NON_GIT"
run_tool "$NON_GIT" status
assert_eq "2" "$run_rc" "non-Git directory exits 2"
assert_eq "error" "$(json_field "$run_out" state)" "runtime failure is machine-readable"

skill_text="$(cat "$REPO/codebase-understanding/SKILL.md")"
graph_text="$(cat "$REPO/graph-context-check.md")"
assert_contains "$skill_text" "Repo Map" "codebase-understanding documents Repo Map as the default"
assert_contains "$skill_text" "Optional visualization" "codebase-understanding keeps visualization explicit"
assert_contains "$skill_text" "Egonex-AI/Understand-Anything" "codebase-understanding points optional UA provenance to SOURCES"
for legacy_token in "Lum1104" "Node.js ≥ 22" "pnpm ≥ 10" "/understand-diff" "knowledge-graph.json" "7 天"; do
  assert_not_contains "$skill_text" "$legacy_token" "codebase-understanding removes legacy default token $legacy_token"
done
assert_contains "$graph_text" "source=<repo-map|search>" "shared fragment owns canonical Graph Context vocabulary"
assert_not_contains "$graph_text" ".understand-anything" "shared fragment has no UA cache coupling"
assert_not_contains "$graph_text" "understand-diff" "shared fragment has no UA command coupling"

for caller in spec systematic-debugging shared-skill-onboarder; do
  caller_text="$(cat "$REPO/$caller/SKILL.md")"
  assert_contains "$caller_text" "Graph Context:" "$caller retains the required Graph Context line"
  assert_not_contains "$caller_text" "understand-diff used" "$caller does not duplicate Graph Context enum"
done

assert_not_contains "$(cat "$REPO/.gitignore")" ".understand-anything" "root gitignore no longer owns optional UA cache rules"
sources_text="$(cat "$REPO/SOURCES.md")"
assert_contains "$sources_text" "## Optional runtime adapters" "SOURCES separates optional runtime adapters"
assert_contains "$sources_text" "Egonex-AI/Understand-Anything" "SOURCES records current UA upstream"
assert_contains "$sources_text" "9d6f025dca0253ec85e115aa2d4cc87f7b642eca" "SOURCES pins the optional UA reference"

finish
