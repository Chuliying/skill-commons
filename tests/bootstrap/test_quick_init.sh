#!/usr/bin/env bash
# The documented Quick Start is two commands: add the submodule over HTTPS, then onboard.
# No SSH key, no hand-edited manifest, no questions. This test runs the same two commands
# in a fresh repository (with the local checkout as the submodule source) and checks that
# the README pair and the submodule bridge document exactly that.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"

HTTPS_ADD='git submodule add https://github.com/Chuliying/skill-commons.git .agent/skills/_shared'
ONBOARD='bash .agent/skills/_shared/bootstrap/onboard.sh'

# --- Documentation: both READMEs and the bridge show the same two commands -------------
for doc in README.md README.en.md docs/skill-commons-submodule-bridge.md; do
  text="$(cat "$REPO/$doc")"
  assert_contains "$text" "$HTTPS_ADD" "$doc documents the HTTPS submodule command"
  assert_contains "$text" "$ONBOARD" "$doc documents onboarding as the second command"
  if printf '%s' "$text" | grep -q 'git@github.com:Chuliying/skill-commons.git'; then
    TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $doc still requires an SSH key for the submodule"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $doc does not require SSH"
  fi
done
for doc in README.md README.en.md; do
  quick="$(awk '/^## Quick Start/{on=1; next} on && /^## /{exit} on' "$REPO/$doc")"
  if printf '%s' "$quick" | grep -q 'cp .*project-manifest.md'; then
    TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $doc Quick Start still asks to copy the manifest by hand"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $doc Quick Start does not hand-copy the manifest"
  fi
  assert_contains "$quick" "jq" "$doc Quick Start names the jq requirement"
done

# --- Behavior: the two commands work in a fresh repository ------------------------------
# The submodule source is the current working tree (tracked and new files), committed in a
# throwaway repo, so the test covers uncommitted changes rather than the last commit.
SRC="$TMP/src"
mkdir -p "$SRC"
python3 - "$REPO" "$SRC" <<'PY'
import shutil, subprocess, sys
from pathlib import Path
repo, src = Path(sys.argv[1]), Path(sys.argv[2])
names = subprocess.run(["git", "-C", str(repo), "ls-files", "-co", "--exclude-standard", "-z"], capture_output=True, check=True).stdout.split(b"\0")
for raw in filter(None, names):
    path = repo / raw.decode()
    if path.is_file() or path.is_symlink():
        target = src / raw.decode()
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target, follow_symlinks=False)
PY
git -C "$SRC" init -q && git -C "$SRC" add -A && git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -m src
PROJECT="$TMP/project"
mkdir -p "$PROJECT" && git -C "$PROJECT" init -q
git -C "$PROJECT" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
# Same command as the README, with the local clone standing in for GitHub.
( cd "$PROJECT" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
onboard_output="$(cd "$PROJECT" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"; onboard_rc=$?
assert_eq "0" "$onboard_rc" "onboard succeeds with no manifest and no input"
assert_file "$PROJECT/.agent/project-manifest.md" "onboard writes the default manifest"
assert_file "$PROJECT/.claude/skills/skill-router/SKILL.md" "onboard installs skills for Claude Code"
assert_file "$PROJECT/.agents/skills/skill-router/SKILL.md" "onboard installs skills for Codex"
# The default includes the optional pack, so the requirement step has its owner.
assert_file "$PROJECT/.claude/skills/to-prd/SKILL.md" "default install includes to-prd for requirements"

doctor_output="$(cd "$PROJECT" && bash .agent/skills/_shared/bootstrap/manage.sh doctor 2>&1)"; doctor_rc=$?
assert_eq "0" "$doctor_rc" "doctor is healthy right after the two commands"
assert_contains "$doctor_output" "healthy" "doctor reports healthy"

# A first work item can be checked with the installed tools.
mkdir -p "$PROJECT/docs/work/first-task"
cat > "$PROJECT/docs/work/first-task/meta.yml" <<'EOF'
schema_version: work-item/v3
slug: first-task
title: First task
created_at: 2026-10-29T00:00:00Z
updated_at: 2026-10-29T00:00:00Z
execution_mode: personal-feature
work_status: active
delivery_status: not_requested
documentation_impact: n/a:test fixture
stages:
  prd: { skill: to-prd, file: prd.md, status: ready }
inputs:
  - user: first-request
EOF
printf '# First task\n' > "$PROJECT/docs/work/first-task/prd.md"
check_output="$(cd "$PROJECT" && bash .agent/skills/_shared/scripts/work-items.sh check 2>&1)"; check_rc=$?
assert_eq "0" "$check_rc" "installed work-item check passes on a first item"
assert_contains "$check_output" "1 valid" "installed work-item check sees the first item"

# The generated verification wrapper must find its evidence helper in a consumer repo.
wrapper_output="$(cd "$PROJECT" && bash .claude/skills/verification-before-completion/scripts/verify.sh --work-item first-task 2>&1)"
assert_not_contains "$wrapper_output" "could not record verification evidence" "generated verify.sh records evidence in a consumer repo"
assert_file "$PROJECT/docs/work/first-task/verification.json" "generated verify.sh writes the evidence file"
assert_file "$PROJECT/docs/work/first-task/activity.jsonl" "generated verify.sh logs the run to activity.jsonl (T08)"

# An existing manifest that predates skill-commons (closetmate/job-board trial, 2026-10-30):
# onboarding names every missing key at once, and pasting the printed lines is enough.
OWN="$TMP/own-manifest"
mkdir -p "$OWN/.agent" && git -C "$OWN" init -q
printf '# Own manifest\n\n## Stack\n\n- test_cmd: npm test\n' > "$OWN/.agent/project-manifest.md"
git -C "$OWN" add -A && git -C "$OWN" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$OWN" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
own_output="$(cd "$OWN" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"; own_rc=$?
assert_neq "0" "$own_rc" "onboard stops when an existing manifest has no selection"
assert_contains "$own_output" "platform selection is required" "the missing platform is named"
assert_contains "$own_output" "delivery mode is required" "the missing delivery mode is named in the same run"
printf '%s\n' "$own_output" | grep '^- ' >> "$OWN/.agent/project-manifest.md"
own_rerun="$(cd "$OWN" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"; own_rerun_rc=$?
assert_eq "0" "$own_rerun_rc" "pasting the printed lines is enough to onboard"
assert_contains "$own_rerun" "capability-packs=optional" "the pasted lines include the recommended pack"
assert_file "$OWN/.agents/skills/to-prd/SKILL.md" "the pasted selection installs to-prd"

# Verification scope (trial decision 2026-10-30): a manifest onboarding creates gets
# source_roots and tests_root derived from top-level directories; an existing manifest is
# user-owned and only gets suggested lines.
ROOTS="$TMP/derived-roots"
mkdir -p "$ROOTS/src" "$ROOTS/tests" "$ROOTS/docs" && git -C "$ROOTS" init -q
printf 'x\n' > "$ROOTS/src/a.js"; printf 't\n' > "$ROOTS/tests/a.test.js"; printf 'd\n' > "$ROOTS/docs/r.md"
git -C "$ROOTS" add -A && git -C "$ROOTS" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$ROOTS" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
roots_output="$(cd "$ROOTS" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"
roots_manifest="$(cat "$ROOTS/.agent/project-manifest.md")"
assert_contains "$roots_manifest" "- source_roots: src" "a new manifest gets the derived source root"
assert_contains "$roots_manifest" "- tests_root: tests" "a new manifest gets the derived tests root"
assert_not_contains "$roots_manifest" "source_roots: src,docs" "docs is not a derived source root"
assert_contains "$roots_output" "check them" "onboard asks the user to check the derived roots"
roots_doctor="$(cd "$ROOTS" && bash .agent/skills/_shared/bootstrap/manage.sh doctor 2>&1)"; roots_doctor_rc=$?
assert_eq "0" "$roots_doctor_rc" "doctor stays healthy with derived roots"

mkdir -p "$OWN/src" && printf 'x\n' > "$OWN/src/a.js" && git -C "$OWN" add src && git -C "$OWN" -c user.name=t -c user.email=t@example.invalid commit -q -m src
own_before="$(cat "$OWN/.agent/project-manifest.md")"
own_roots="$(cd "$OWN" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"
assert_eq "$own_before" "$(cat "$OWN/.agent/project-manifest.md")" "an existing manifest is not modified"
assert_contains "$own_roots" "- source_roots: src" "an existing manifest gets suggested roots to add"

# Test command (competitor test round 2, criterion C): a new manifest gets a test command
# derived from project files, so the first verification runs without editing the manifest.
PYPROJ="$TMP/derived-test"
mkdir -p "$PYPROJ" && git -C "$PYPROJ" init -q
printf 'def f():\n    return 1\n' > "$PYPROJ/todo.py"
printf 'import unittest\nfrom todo import f\nclass T(unittest.TestCase):\n    def test(self):\n        self.assertEqual(f(), 1)\n' > "$PYPROJ/test_todo.py"
git -C "$PYPROJ" add -A && git -C "$PYPROJ" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$PYPROJ" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
pyproj_output="$(cd "$PYPROJ" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"
assert_contains "$(cat "$PYPROJ/.agent/project-manifest.md")" "- test_cmd: python3 -m unittest" "a new manifest gets the derived test command"
assert_contains "$pyproj_output" "check it" "onboard asks the user to check the derived test command"
mkdir -p "$PYPROJ/docs/work/first"
sed 's/^slug: first-task/slug: first/' "$PROJECT/docs/work/first-task/meta.yml" > "$PYPROJ/docs/work/first/meta.yml"
printf '# First\n' > "$PYPROJ/docs/work/first/prd.md"
(cd "$PYPROJ" && bash .claude/skills/verification-before-completion/scripts/verify.sh --work-item first >/dev/null 2>&1); pyproj_verify=$?
assert_eq "0" "$pyproj_verify" "the first verification runs without editing the manifest"
assert_contains "$(cat "$PYPROJ/docs/work/first/verification.json")" '"result": "pass"' "the first verification records a pass"

derive_case() { # name setup expected label
  local d="$TMP/derive-$1"; mkdir -p "$d" && git -C "$d" init -q
  (cd "$d" && eval "$2") && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@example.invalid commit -q -m init
  local got; got="$(. "$REPO/bootstrap/lib/manifest.sh"; derive_test_cmd "$d")"
  assert_eq "$3" "$got" "$4"
}
derive_case npm-default "printf '{\"scripts\":{\"test\":\"echo \\\\\"Error: no test specified\\\\\" && exit 1\"}}' > package.json" "" "npm's placeholder test script is not a test command"
derive_case npm "printf '{\"scripts\":{\"test\":\"vitest run\"}}' > package.json" "npm test" "a package.json test script gives npm test"
derive_case pnpm "printf '{\"scripts\":{\"test\":\"vitest run\"}}' > package.json; : > pnpm-lock.yaml" "pnpm test" "a pnpm lockfile gives pnpm test"
derive_case tests-dir "mkdir tests; printf 'x\n' > tests/test_a.py" "python3 -m unittest discover -s tests" "unittest files under tests/ are discovered there"
derive_case pytest "printf '[tool.pytest.ini_options]\n' > pyproject.toml; printf 'x\n' > test_a.py" "python3 -m pytest" "pytest configuration gives pytest"
derive_case go "printf 'module x\n' > go.mod" "go test ./..." "go.mod gives go test"
derive_case none "printf 'x\n' > README.md" "" "no test files gives no command"

# Fable round 2 spot check, blocking: a Python package at the root plus tests/ derived only
# tests_root, which verified the tests alone. Partial roots are suggested, never written.
PKG="$TMP/root-package"
mkdir -p "$PKG/mytool" "$PKG/tests" && git -C "$PKG" init -q
printf 'x = 1\n' > "$PKG/mytool/app.py"; printf 'x = 1\n' > "$PKG/mytool/cli.py"; printf 'import unittest\n' > "$PKG/tests/test_app.py"
git -C "$PKG" add -A && git -C "$PKG" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$PKG" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
pkg_output="$(cd "$PKG" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"
assert_not_contains "$(cat "$PKG/.agent/project-manifest.md")" "tests_root:" "roots that miss most code are not written"
assert_contains "$pkg_output" "1 of 3 tracked code files" "onboard says how much code the suggested roots miss"

# T07: platforms follow the repository; CLAUDE.md imports AGENTS.md; the directive is a
# command card (competitor test round 2, criteria B and D).
assert_contains "$(cat "$PROJECT/.agent/project-manifest.md")" "- platforms: claude-code, codex" "an empty repository defaults to Claude Code and Codex"
assert_eq "0" "$([ -e "$PROJECT/.cursor" ] && echo 1 || echo 0)" "Cursor is not installed by default"
assert_contains "$(cat "$PROJECT/CLAUDE.md")" "@AGENTS.md" "CLAUDE.md imports AGENTS.md"
assert_not_contains "$(cat "$PROJECT/CLAUDE.md")" "work-items.sh new" "CLAUDE.md does not repeat the directive"
assert_contains "$(cat "$PROJECT/AGENTS.md")" "work-items.sh new <slug>" "AGENTS.md carries the command card"
CUR="$TMP/cursor-repo"
mkdir -p "$CUR/.cursor" && git -C "$CUR" init -q && printf 'x\n' > "$CUR/README.md"
git -C "$CUR" add -A && git -C "$CUR" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$CUR" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
(cd "$CUR" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
assert_contains "$(cat "$CUR/.agent/project-manifest.md")" "- platforms: cursor" "a repository that uses Cursor keeps Cursor only"
assert_eq "0" "$([ -e "$CUR/.claude" ] && echo 1 || echo 0)" "a Cursor repository gets no Claude Code adapter"

# Fable T07 review: a custom submodule_path reaches every command on the card; the template
# comment does not survive into the user's manifest.
assert_not_contains "$(cat "$PROJECT/.agent/project-manifest.md")" "onboard.sh replaces this" "the template comment is removed once platforms are written"
MOUNT="$TMP/custom-mount"
mkdir -p "$MOUNT/.agent" && git -C "$MOUNT" init -q
printf '## skill-commons bootstrap\n\n- submodule_path: vendor/sc\n- platforms: codex\n- delivery_mode: personal\n' > "$MOUNT/.agent/project-manifest.md"
git -C "$MOUNT" add -A && git -C "$MOUNT" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$MOUNT" && git -c protocol.file.allow=always submodule add -q "$SRC" vendor/sc ) </dev/null
(cd "$MOUNT" && bash vendor/sc/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
assert_contains "$(cat "$MOUNT/AGENTS.md")" "bash vendor/sc/scripts/work-items.sh new" "the card uses the custom mount"
assert_not_contains "$(cat "$MOUNT/AGENTS.md")" ".agent/skills/_shared" "the card names no default mount under a custom one"

# T09: an English first-use path. Files onboarding writes into the user's repository contain no
# CJK characters (the round 3 criterion G pattern), and a generic AGENTS.md does not mean Codex.
for generated in AGENTS.md CLAUDE.md .agent/guardrails.md .agent/project-manifest.md; do
  cjk="$(python3 -c 'import re,sys; print(len(re.findall("[　-ヿ㐀-鿿＀-￯]", open(sys.argv[1], encoding="utf-8").read())))' "$PROJECT/$generated")"
  assert_eq "0" "$cjk" "generated $generated is English"
done
for skill in skill-router implement verification-before-completion systematic-debugging sync-work; do
  cjk="$(python3 -c 'import re,sys; print(len(re.findall("[　-ヿ㐀-鿿＀-￯]", open(sys.argv[1], encoding="utf-8").read())))' "$PROJECT/.claude/skills/$skill/SKILL.md")"
  assert_eq "0" "$cjk" "first-use skill $skill is English"
done
GEN="$TMP/generic-agents"
mkdir -p "$GEN" && git -C "$GEN" init -q && printf '# Agent notes\n' > "$GEN/AGENTS.md"
git -C "$GEN" add -A && git -C "$GEN" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$GEN" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
(cd "$GEN" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
assert_contains "$(cat "$GEN/.agent/project-manifest.md")" "- platforms: claude-code, codex" "a generic AGENTS.md keeps the default platforms"
assert_file "$GEN/CLAUDE.md" "a repository with only a generic AGENTS.md still gets Claude Code"

# T09 review: CLAUDE.md plus AGENTS.md without .codex selects Claude Code and says how to add Codex.
CA="$TMP/claude-and-agents"
mkdir -p "$CA" && git -C "$CA" init -q && printf '# Claude notes\n' > "$CA/CLAUDE.md" && printf '# Agent notes\n' > "$CA/AGENTS.md"
git -C "$CA" add -A && git -C "$CA" -c user.name=t -c user.email=t@example.invalid commit -q -m init
( cd "$CA" && git -c protocol.file.allow=always submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
ca_out="$(cd "$CA" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"
assert_contains "$(cat "$CA/.agent/project-manifest.md")" "- platforms: claude-code" "CLAUDE.md selects Claude Code"
assert_contains "$ca_out" "AGENTS.md alone does not select Codex" "onboard says how to add Codex when AGENTS.md is present"

finish
