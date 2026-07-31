#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

# The scan-secrets fixtures assert on git-ignore state, including negative cases
# where a file must NOT be ignored. A host-level core.excludesFile would answer
# those probes instead of the fixture .gitignore and silently invert the result.
# Fixture commits already pass identity inline, so nothing here needs global config.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

cat > "$TMP/prd.md" <<'EOF'
# PRD
- AC-001: default greeting
- AC-002: custom greeting
EOF
cat > "$TMP/qa-good.md" <<'EOF'
| AC-ID | TC-ID | Description |
|---|---|---|
| AC-001 | TC-001 | default |
| AC-002 | TC-002 | custom |
EOF
cat > "$TMP/qa-bad.md" <<'EOF'
| AC-ID | TC-ID | Description |
|---|---|---|
| AC-001 | TC-001 | default |
EOF

if python3 "$REPO/qa/scripts/check-traceability.py" --prd "$TMP/prd.md" --qa-plan "$TMP/qa-good.md" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: QA traceability accepts complete AC-to-TC mappings"
else
  fail "QA traceability accepts complete AC-to-TC mappings"
fi
if python3 "$REPO/qa/scripts/check-traceability.py" --prd "$TMP/prd.md" --qa-plan "$TMP/qa-bad.md" >/dev/null 2>&1; then
  fail "QA traceability rejects an unmapped AC"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: QA traceability rejects an unmapped AC"
fi

mkdir -p "$TMP/prototype/assets"
cat > "$TMP/prototype/map.json" <<'EOF'
{"meta":{"shellType":"standard","frozenAt":"2026-07-04T00:00:00Z","coverageRate":100,"gaps":[]},"routes":{"s1":{"pages":["home"]}},"pages":{"home":{"frameRef":"frame-home","acs":[{"id":"AC-001"}]}}}
EOF
cat > "$TMP/prototype/index.html" <<'EOF'
<link rel="stylesheet" href="assets/component-library.css">
<div id="scenario-s1"><div id="s1-home">frame-home AC-001</div></div>
<script>var PROTOTYPE_MAP={}, FRAME_REGISTRY={}, SCENARIO_STATE={};</script>
EOF
for asset in engine.js shell-common.css shell-standard.css component-library.css print-report.css; do
  printf 'asset\n' > "$TMP/prototype/assets/$asset"
done

if python3 "$REPO/prototype/scripts/verify-freeze.py" --map "$TMP/prototype/map.json" --html "$TMP/prototype/index.html" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: prototype freeze verifier accepts matching output"
else
  fail "prototype freeze verifier accepts matching output"
fi
sed 's/AC-001//' "$TMP/prototype/index.html" > "$TMP/prototype/index-bad.html"
if python3 "$REPO/prototype/scripts/verify-freeze.py" --map "$TMP/prototype/map.json" --html "$TMP/prototype/index-bad.html" >/dev/null 2>&1; then
  fail "prototype freeze verifier rejects missing frozen AC"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: prototype freeze verifier rejects missing frozen AC"
fi

cat > "$TMP/prototype/map-bad-route.json" <<'EOF'
{"meta":{"shellType":"standard","frozenAt":"2026-07-04T00:00:00Z","coverageRate":100,"gaps":[]},"routes":{"s1":{"pages":[{"id":"home"}]}},"pages":{"home":{"frameRef":"frame-home","acs":[{"id":"AC-001"}]}}}
EOF
set +e
bad_route_output="$(python3 "$REPO/prototype/scripts/verify-freeze.py" \
  --map "$TMP/prototype/map-bad-route.json" --html "$TMP/prototype/index.html" 2>&1)"
bad_route_rc=$?
set -e
assert_neq "0" "$bad_route_rc" "prototype freeze verifier rejects malformed route page IDs"
assert_contains "$bad_route_output" "FAIL route page id must be a string" "malformed route page has an actionable failure"
assert_not_contains "$bad_route_output" "Traceback" "malformed route page does not leak a Python traceback"

# --- check-prd.py: deterministic PRD shape gate ---
CHECK_PRD="$REPO/scripts/check-prd.py"
GOLD="$REPO/prd-interview/examples/good-prd-sample.md"
run_prd() { python3 "$CHECK_PRD" --prd "$1" --tier "$2" >/dev/null 2>&1; }

if run_prd "$GOLD" team; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd accepts the gold PRD sample (team)"
else
  fail "check-prd accepts the gold PRD sample (team)"
fi
if run_prd "$GOLD" core; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd accepts the gold PRD sample (core)"
else
  fail "check-prd accepts the gold PRD sample (core)"
fi

cat > "$TMP/prd-core.md" <<'EOF'
# Minimal PRD

## 1. Follow-ups

無 Blocking FU。

## 2. Context

### Goal

Let users export the current report as a CSV file.

## 3. Scope

### In scope

- A CSV export button on the report page.

### Out of scope

- PDF export.

## 5. Functional Requirements (FR)

### FR-001: Export CSV

**Behavior**: Clicking export downloads a CSV of the current report.

**Data source**: Existing report API.

## 7. Error Scenarios (ERR)

### ERR-001: Export fails

**Trigger**: The report API returns a 5xx status.

**Recovery**: Show a retry action and keep the current view.

## 8. Acceptance Criteria (AC)

### AC-001: Export downloads a file

```gherkin
Given a report is loaded
When the user clicks export
Then a CSV file downloads
```
EOF

if run_prd "$TMP/prd-core.md" core; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd accepts a core-tier PRD at --tier core"
else
  fail "check-prd accepts a core-tier PRD at --tier core"
fi
if run_prd "$TMP/prd-core.md" team; then
  fail "check-prd rejects a core-tier PRD at --tier team (missing metadata/NFR)"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd rejects a core-tier PRD at --tier team"
fi

sed '/## 1. Follow-ups/d' "$TMP/prd-core.md" > "$TMP/prd-no-fu.md"
if run_prd "$TMP/prd-no-fu.md" core; then
  fail "check-prd rejects a PRD missing the Follow-ups section"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd rejects a PRD missing Follow-ups"
fi

sed '/## 5. Functional Requirements/d' "$TMP/prd-core.md" > "$TMP/prd-no-fr.md"
if run_prd "$TMP/prd-no-fr.md" core; then
  fail "check-prd rejects a PRD missing the FR section heading"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd rejects a PRD missing the FR heading"
fi

sed '/^Then /d' "$TMP/prd-core.md" > "$TMP/prd-bad-ac.md"
if run_prd "$TMP/prd-bad-ac.md" core; then
  fail "check-prd rejects an AC without Given-When-Then"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd rejects a non-GWT AC"
fi

cp "$TMP/prd-core.md" "$TMP/prd-placeholder.md"
printf '\n**Permissions / Visibility**: [roles]\n' >> "$TMP/prd-placeholder.md"
if run_prd "$TMP/prd-placeholder.md" core; then
  fail "check-prd rejects a residual template placeholder"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd rejects a residual placeholder"
fi

# mermaid node labels and markdown links that reuse template placeholder words
# ([reason], [field]) must NOT be flagged as unfilled placeholders
cp "$TMP/prd-core.md" "$TMP/prd-mermaid.md"
cat >> "$TMP/prd-mermaid.md" <<'EOF'

## 4. Flow

See [field docs](https://example.test/schema) for the schema.

```mermaid
flowchart TD
  A[reason] --> B[field]
```
EOF
if run_prd "$TMP/prd-mermaid.md" core; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd ignores mermaid/link brackets matching template words"
else
  fail "check-prd ignores mermaid/link brackets matching template words"
fi

# anti-drift: every REQUIRED_TEAM heading must exist in the canonical template
if python3 - "$REPO" <<'PY'
import sys, importlib.util
repo = sys.argv[1]
spec = importlib.util.spec_from_file_location("check_prd", f"{repo}/scripts/check-prd.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
present = set(mod.headings(open(f"{repo}/prd-template.md", encoding="utf-8").read()))
missing = [h for h in mod.REQUIRED_TEAM if h not in present]
sys.exit(1 if missing else 0)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: check-prd required headings stay in sync with prd-template.md"
else
  fail "check-prd required headings drifted from prd-template.md"
fi

# boundary wiring: producers (postcondition) and spec (precondition) all invoke
# check-prd via a consuming-repo-resolvable path (a bare dev-repo "scripts/..."
# path would be file-not-found from a consuming project root, so lock the form)
for skill in to-prd prd-interview spec; do
  if grep -q "<shared_skills_root>/scripts/check-prd.py" "$REPO/$skill/SKILL.md"; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $skill invokes check-prd via a resolvable shared-scripts path"
  else
    fail "$skill invokes check-prd via a resolvable shared-scripts path"
  fi
done

# --- subagent-driven-development implementer loop must commit only after both
# review gates and a secret scan (sync-work Hard Rule 5: no commit bypasses
# verification + security). ---
sdd="$REPO/subagent-driven-development/SKILL.md"
sdd_commit_line="$(grep -n 'Commit' "$sdd" | head -1 | cut -d: -f1)"
sdd_quality_line="$(grep -n 'Code Quality Gate' "$sdd" | head -1 | cut -d: -f1)"
if [ -n "$sdd_commit_line" ] && [ -n "$sdd_quality_line" ] && [ "$sdd_commit_line" -gt "$sdd_quality_line" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: SDD implementer commits only after the code quality gate"
else
  fail "SDD implementer commit must follow both review gates (commit@${sdd_commit_line:-none} quality-gate@${sdd_quality_line:-none})"
fi
if grep -qiE 'scan-secrets|secret 掃描|secret scan' "$sdd"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: SDD implementer loop runs a secret scan before commit"
else
  fail "SDD implementer loop must run a secret scan before commit"
fi

# --- FR-005 router/flow contracts must not dead-end any of the three main flows. ---
# P1-A: spec's PRD gate tier is execution-mode conditional (team-feature -> team,
# refactor optional spec -> core), so a to-prd core PRD can enter spec without failing
# a hardcoded --tier team gate.
spec_text="$(cat "$REPO/spec/SKILL.md")"
assert_contains "$spec_text" "--tier core" "spec PRD gate offers core tier for no-team execution modes"
assert_contains "$spec_text" "--tier team" "spec PRD gate keeps team tier for team-feature"

# P1-I: brainstorming handoff is profile-conditional (team -> prd-interview,
# personal -> to-prd) instead of hardcoding prd-interview, which personal lacks.
brainstorm_text="$(cat "$REPO/brainstorming/SKILL.md")"
assert_contains "$brainstorm_text" "personal" "brainstorming handoff names the personal profile path"
assert_contains "$brainstorm_text" "to-prd" "brainstorming personal handoff targets to-prd"

# P1-J: grilling durable-docs mode makes domain-modeling conditional on availability
# (team or already installed), else write glossary.md directly.
grilling_text="$(cat "$REPO/grilling/SKILL.md")"
assert_contains "$grilling_text" "已安裝" "grilling domain-modeling step is conditional on availability"

# P1-K: to-prd and qa validate emit a contract-compatible Execution Checklist so the
# checklist iron law does not create an unsatisfiable rerun loop.
assert_contains "$(cat "$REPO/to-prd/SKILL.md")" "Execution Checklist" "to-prd emits a contract-compatible Execution Checklist"
assert_contains "$(cat "$REPO/qa/references/qa-validate.md")" "Execution Checklist" "qa validate emits a contract-compatible Execution Checklist"

# --- FR-002 scan-secrets must not false-PASS (P0-B/C/D). ---
SCAN="$REPO/security/scripts/scan-secrets.sh"
# Negative fixtures assemble their detector canary at runtime. Keeping the complete
# credential-like value out of this tracked test file lets the repository's own staged
# secret gate inspect the test suite without weakening the fixture verdicts below.
CANARY_LEFT="publish"
CANARY_RIGHT="Canary123456"
CANARY_VALUE="${CANARY_LEFT}${CANARY_RIGHT}"

# Negative fixture: secret outside the default scan root, .gitignore lists only
# .env.example, and a real unignored .env. The old scanner reported all-PASS/exit 0.
SCAN_FIX="$TMP/scan-fixture"
mkdir -p "$SCAN_FIX/scripts"
( cd "$SCAN_FIX" && git init -q && git checkout -q -b main ) >/dev/null 2>&1
printf 'api_key = "%s"\n' "$CANARY_VALUE" > "$SCAN_FIX/scripts/foo.py"
printf '.env.example\n' > "$SCAN_FIX/.gitignore"
printf 'SECRET=%s\n' "$CANARY_VALUE" > "$SCAN_FIX/.env"
set +e
scan_out="$(cd "$SCAN_FIX" && bash "$SCAN" 2>&1)"
scan_rc=$?
set -e
assert_neq "0" "$scan_rc" "scan-secrets fails when scope is empty and .env is unignored"
assert_contains "$scan_out" ".env is not git-ignored" "scan-secrets reports .env is not ignored (git check-ignore)"
if printf '%s' "$scan_out" | grep -qiE "0 file|does not exist|scope is empty"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scan-secrets warns on an empty scan scope"
else
  fail "scan-secrets warns on an empty scan scope"
fi

# P1-D: a real secret carrying a harmless comment word must still be reported
# (suppression must not match the trailing comment).
SCAN_CMT="$TMP/scan-comment"
mkdir -p "$SCAN_CMT/src"
( cd "$SCAN_CMT" && git init -q && git checkout -q -b main ) >/dev/null 2>&1
printf '.env\n' > "$SCAN_CMT/.gitignore"
printf 'const password = "%s"; // rotate this example later\n' "$CANARY_VALUE" > "$SCAN_CMT/src/app.js"
set +e
scan_cmt_out="$(cd "$SCAN_CMT" && bash "$SCAN" 2>&1)"
scan_cmt_rc=$?
set -e
assert_neq "0" "$scan_cmt_rc" "scan-secrets reports a real secret despite a harmless comment"
assert_contains "$scan_cmt_out" "FAIL: hard-coded secrets found" "scan-secrets flags the commented hard-coded secret"

# Positive fixture: a clean TS source repo with .env ignored must PASS (exit 0).
SCAN_OK="$TMP/scan-ok"
mkdir -p "$SCAN_OK/src"
( cd "$SCAN_OK" && git init -q && git checkout -q -b main ) >/dev/null 2>&1
printf 'export const greet = (n: string) => `hello ${n}`;\n' > "$SCAN_OK/src/app.ts"
printf '.env\n.env.*\n!.env.example\n' > "$SCAN_OK/.gitignore"
set +e
scan_ok_out="$(cd "$SCAN_OK" && bash "$SCAN" 2>&1)"
scan_ok_rc=$?
set -e
assert_eq "0" "$scan_ok_rc" "scan-secrets passes a clean TS source repo with an ignored .env"

# P1-C: the staged-diff scan must catch a JSON-style ("key": "value") secret that the
# old `= "..."`-only regex missed.
SCAN_STAGED="$TMP/scan-staged"
mkdir -p "$SCAN_STAGED/src"
( cd "$SCAN_STAGED" && git init -q && git checkout -q -b main &&
  printf '.env\n' > .gitignore && printf 'export const x = 1;\n' > src/app.ts &&
  git add -A && git -c user.name=t -c user.email=t@e commit -qm base ) >/dev/null 2>&1
printf '{\n  "api_key": "%s"\n}\n' "$CANARY_VALUE" > "$SCAN_STAGED/src/config.json"
( cd "$SCAN_STAGED" && git add src/config.json ) >/dev/null 2>&1
set +e
scan_staged_out="$(cd "$SCAN_STAGED" && bash "$SCAN" 2>&1)"
scan_staged_rc=$?
set -e
assert_neq "0" "$scan_staged_rc" "scan-secrets catches a JSON-style secret in staged changes"
assert_contains "$scan_staged_out" "secret found in staged changes" "scan-secrets reports the staged JSON secret"

# Git attributes control presentation, not staged evidence. Marking a source file as
# binary must not hide its raw index blob from the staged scanner.
SCAN_ATTR="$TMP/scan-staged-attributes"
mkdir -p "$SCAN_ATTR/src" "$SCAN_ATTR/deploy"
( cd "$SCAN_ATTR" && git init -q && git checkout -q -b main &&
  printf '.env\n' > .gitignore && printf 'x = 1\n' > src/app.py &&
  git add -A && git -c user.name=t -c user.email=t@e commit -qm base ) >/dev/null 2>&1
printf '*.py binary\n' > "$SCAN_ATTR/.gitattributes"
printf 'api_key = "%s"\n' "$CANARY_VALUE" > "$SCAN_ATTR/deploy/hidden.py"
( cd "$SCAN_ATTR" && git add .gitattributes deploy/hidden.py ) >/dev/null 2>&1
set +e
scan_attr_out="$(cd "$SCAN_ATTR" && bash "$SCAN" 2>&1)"
scan_attr_rc=$?
set -e
assert_neq "0" "$scan_attr_rc" "workspace attributes cannot hide a staged source secret"
assert_contains "$scan_attr_out" "deploy/hidden.py" "staged scan reports the attribute-hidden index path"
assert_not_contains "$scan_attr_out" "Secret preflight result: PASS" "attribute-hidden staged secret: no overall PASS"

# I-S14/I-S15: the same bytes must have the same verdict whether obtained from the
# worktree or a materialized stage-0 blob. Encoding and NUL bytes are data, never an
# implicit SKIP. This corpus also pins the clean non-UTF-8 behavior.
write_parity_payload() { # $1=case $2=path
  case "$1" in
    utf8-secret) printf 'password = "%s"\n' "$CANARY_VALUE" > "$2" ;;
    nul-secret) printf 'password = "%s"\n\000tail\n' "$CANARY_VALUE" > "$2" ;;
    latin1-secret) printf 'password = "%s"\n# caf\351\n' "$CANARY_VALUE" > "$2" ;;
    latin1-clean) printf 'x = 1  # caf\351\n' > "$2" ;;
  esac
}
make_parity_repo() { # $1=repo
  mkdir -p "$1/src" "$1/deploy"
  ( cd "$1" && git init -q && git checkout -q -b main &&
    printf '.env\n' > .gitignore && printf 'x = 1\n' > src/app.py &&
    git add -A && git -c user.name=t -c user.email=t@e commit -qm base ) >/dev/null 2>&1
}
for parity_case in utf8-secret nul-secret latin1-secret latin1-clean; do
  parity_worktree="$TMP/parity-$parity_case-worktree"
  parity_staged="$TMP/parity-$parity_case-staged"
  make_parity_repo "$parity_worktree"
  make_parity_repo "$parity_staged"
  write_parity_payload "$parity_case" "$parity_worktree/src/artifact.py"
  write_parity_payload "$parity_case" "$parity_staged/deploy/artifact.py"
  ( cd "$parity_staged" && git add deploy/artifact.py ) >/dev/null 2>&1
  set +e
  parity_worktree_out="$(cd "$parity_worktree" && bash "$SCAN" 2>&1)"
  parity_worktree_rc=$?
  parity_staged_out="$(cd "$parity_staged" && bash "$SCAN" 2>&1)"
  parity_staged_rc=$?
  set -e
  parity_worktree_verdict=FAIL
  parity_staged_verdict=FAIL
  [[ "$parity_worktree_rc" -eq 0 ]] && parity_worktree_verdict=PASS
  [[ "$parity_staged_rc" -eq 0 ]] && parity_staged_verdict=PASS
  parity_expected=FAIL
  [[ "$parity_case" == latin1-clean ]] && parity_expected=PASS
  assert_eq "$parity_expected" "$parity_worktree_verdict" "$parity_case has the expected worktree verdict"
  assert_eq "$parity_expected" "$parity_staged_verdict" "$parity_case has the expected staged verdict"
  assert_eq "$parity_worktree_verdict" "$parity_staged_verdict" "$parity_case preserves worktree/staged verdict parity"
  if [[ "$parity_expected" == FAIL ]]; then
    assert_not_contains "$parity_staged_out" "Secret preflight result: PASS" "$parity_case staged finding has no overall PASS"
  fi
done

# Type changes and unmerged entries are staged evidence too. A symlink-to-regular
# transition outside source_roots must expose its raw stage-0 blob; an unresolved
# index has no trustworthy stage-0 answer and must fail closed.
SCAN_TYPECHANGE="$TMP/scan-staged-typechange"
mkdir -p "$SCAN_TYPECHANGE/src" "$SCAN_TYPECHANGE/deploy"
( cd "$SCAN_TYPECHANGE" && git init -q && git checkout -q -b main &&
  printf '.env\n' > .gitignore && printf 'x = 1\n' > src/app.py &&
  ln -s target.py deploy/config.py && git add -A &&
  git -c user.name=t -c user.email=t@e commit -qm base ) >/dev/null 2>&1
rm "$SCAN_TYPECHANGE/deploy/config.py"
printf 'password = "%s"\n' "$CANARY_VALUE" > "$SCAN_TYPECHANGE/deploy/config.py"
( cd "$SCAN_TYPECHANGE" && git add deploy/config.py ) >/dev/null 2>&1
set +e
scan_typechange_out="$(cd "$SCAN_TYPECHANGE" && bash "$SCAN" 2>&1)"
scan_typechange_rc=$?
set -e
assert_neq "0" "$scan_typechange_rc" "staged type-change cannot be omitted from index materialization"
assert_contains "$scan_typechange_out" "deploy/config.py" "staged type-change reports its raw index path"
assert_not_contains "$scan_typechange_out" "Secret preflight result: PASS" "staged type-change secret: no overall PASS"

SCAN_UNMERGED="$TMP/scan-staged-unmerged"
mkdir -p "$SCAN_UNMERGED/src" "$SCAN_UNMERGED/deploy"
( cd "$SCAN_UNMERGED" && git init -q && git checkout -q -b main &&
  printf '.env\n' > .gitignore && printf 'x = 1\n' > src/app.py &&
  git add -A && git -c user.name=t -c user.email=t@e commit -qm base &&
  one=$(printf 'password = "%s%s"\n' one "$CANARY_VALUE" | git hash-object -w --stdin) &&
  two=$(printf 'password = "%s%s"\n' two "$CANARY_VALUE" | git hash-object -w --stdin) &&
  three=$(printf 'password = "%s%s"\n' three "$CANARY_VALUE" | git hash-object -w --stdin) &&
  printf '100644 %s 1\tdeploy/conflict.py\n100644 %s 2\tdeploy/conflict.py\n100644 %s 3\tdeploy/conflict.py\n' "$one" "$two" "$three" |
    git update-index --index-info ) >/dev/null 2>&1
set +e
scan_unmerged_out="$(cd "$SCAN_UNMERGED" && bash "$SCAN" 2>&1)"
scan_unmerged_rc=$?
set -e
assert_neq "0" "$scan_unmerged_rc" "unmerged staged path fails closed without a stage-0 blob"
assert_contains "$scan_unmerged_out" "no unambiguous stage-0 blob" "unmerged staged path reports the index conflict"
assert_not_contains "$scan_unmerged_out" "Secret preflight result: PASS" "unmerged staged path: no overall PASS"

# Review finding (P1-D on the staged path): a staged secret in a file OUTSIDE
# source_roots, carrying a harmless comment word, must still be caught (token-level
# suppression on the staged diff, not line-level).
SCAN_SCMT="$TMP/scan-staged-cmt"
mkdir -p "$SCAN_SCMT/deploy" "$SCAN_SCMT/src"
( cd "$SCAN_SCMT" && git init -q && git checkout -q -b main &&
  printf '.env\n' > .gitignore && printf 'x = 1\n' > src/app.py &&
  git add -A && git -c user.name=t -c user.email=t@e commit -qm base ) >/dev/null 2>&1
printf 'api_key = "%s"  # example rotate later\n' "$CANARY_VALUE" > "$SCAN_SCMT/deploy/run.sh"
( cd "$SCAN_SCMT" && git add deploy/run.sh ) >/dev/null 2>&1
set +e
scan_scmt_out="$(cd "$SCAN_SCMT" && bash "$SCAN" 2>&1)"
scan_scmt_rc=$?
set -e
assert_neq "0" "$scan_scmt_rc" "scan-secrets catches a staged out-of-root secret with a harmless comment"
assert_contains "$scan_scmt_out" "secret found in staged changes" "staged scan reports the commented out-of-root secret"

# Review finding: an unquoted value after `:` (a TS type annotation on a secret-named
# field) must NOT be flagged as a staged secret -- only quoted values match after `:`.
SCAN_TYPE="$TMP/scan-type"
mkdir -p "$SCAN_TYPE/src"
( cd "$SCAN_TYPE" && git init -q && git checkout -q -b main &&
  printf '.env\n' > .gitignore && printf 'export const x = 1;\n' > src/app.ts &&
  git add -A && git -c user.name=t -c user.email=t@e commit -qm base ) >/dev/null 2>&1
printf 'interface Creds {\n  refresh_token: ReadonlyRecordOfLongName;\n}\n' > "$SCAN_TYPE/src/types.ts"
( cd "$SCAN_TYPE" && git add src/types.ts ) >/dev/null 2>&1
set +e
scan_type_out="$(cd "$SCAN_TYPE" && bash "$SCAN" 2>&1)"
scan_type_rc=$?
set -e
assert_eq "0" "$scan_type_rc" "scan-secrets does not flag a TS type annotation as a staged secret"

# Review C1: a suppression word elsewhere on the line (a `test`/`type` identifier)
# must NOT hide a real secret in the key/value. Token-level suppression only.
SCAN_TOK="$TMP/scan-token"
mkdir -p "$SCAN_TOK/src"
( cd "$SCAN_TOK" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'const test = { password: "%s" };\n' "$CANARY_VALUE" > "$SCAN_TOK/src/app.js"
set +e
scan_tok_out="$(cd "$SCAN_TOK" && bash "$SCAN" 2>&1)"
scan_tok_rc=$?
set -e
assert_neq "0" "$scan_tok_rc" "scan-secrets catches a real secret when a suppression word appears elsewhere on the line"
assert_contains "$scan_tok_out" "FAIL: hard-coded secrets found" "token-level suppression does not hide the secret"

# Review M1: a scaffold whose only source file is empty must NOT false-FAIL as an
# empty scan scope -- count by file enumeration, not content match.
SCAN_EF="$TMP/scan-emptyfile"
mkdir -p "$SCAN_EF/src"
( cd "$SCAN_EF" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
: > "$SCAN_EF/src/app.ts"
set +e
scan_ef_out="$(cd "$SCAN_EF" && bash "$SCAN" 2>&1)"
scan_ef_rc=$?
set -e
assert_eq "0" "$scan_ef_rc" "scan-secrets does not false-FAIL a scaffold whose only source file is empty"
assert_contains "$scan_ef_out" "files scanned: 1" "an empty source file is still counted in scan scope"

# Round-3 C1: a placeholder value on a NON-keyword field must not suppress a real
# secret on a keyword field on the same line (suppression is per key/value token).
SCAN_MIX="$TMP/scan-mix"
mkdir -p "$SCAN_MIX/src"
( cd "$SCAN_MIX" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'label="example"; password="%s"\n' "$CANARY_VALUE" > "$SCAN_MIX/src/app.js"
set +e; scan_mix_rc=$(cd "$SCAN_MIX" && bash "$SCAN" >/dev/null 2>&1; echo $?); set -e
assert_neq "0" "$scan_mix_rc" "scan-secrets catches a keyword secret even when another field holds a placeholder"

# Round-3 C2: generic secret/token keywords must be scanned in the worktree, not only
# the *_key / *_token compounds.
SCAN_GEN="$TMP/scan-generic"
mkdir -p "$SCAN_GEN/src"
( cd "$SCAN_GEN" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'token = "%s"\n' "$CANARY_VALUE" > "$SCAN_GEN/src/app.js"
set +e; scan_gen_rc=$(cd "$SCAN_GEN" && bash "$SCAN" >/dev/null 2>&1; echo $?); set -e
assert_neq "0" "$scan_gen_rc" "scan-secrets catches a generic token= secret in the worktree"

# Round-3 C3: staged suppression must be token-level too; a placeholder word elsewhere
# on a staged line must not hide a real secret.
SCAN_STG2="$TMP/scan-staged2"
mkdir -p "$SCAN_STG2/src"
( cd "$SCAN_STG2" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore &&
  printf 'x=1\n' > src/keep.py && git add -A && git -c user.name=t -c user.email=t@e commit -qm b ) >/dev/null 2>&1
printf 'password="%s" ; note="example"\n' "$CANARY_VALUE" > "$SCAN_STG2/src/cfg.py"
( cd "$SCAN_STG2" && git add src/cfg.py ) >/dev/null 2>&1
set +e; scan_stg2_out="$(cd "$SCAN_STG2" && bash "$SCAN" 2>&1)"; scan_stg2_rc=$?; set -e
assert_neq "0" "$scan_stg2_rc" "scan-secrets staged scan uses token-level suppression"
assert_contains "$scan_stg2_out" "secret found in staged changes" "staged token-level suppression reports the real secret"

# Round-4: the extractor must be case-insensitive and accept unquoted / typed-assignment
# / backtick values (previously worktree missed all of these).
scan_case() { # $1 desc, $2 file content, $3 expected FAIL|PASS
  local d="$TMP/scan_r4_$RANDOM"; mkdir -p "$d/src"
  ( cd "$d" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
  printf '%b' "$2" > "$d/src/app.ts"
  local rc=0; ( cd "$d" && bash "$SCAN" >/dev/null 2>&1 ) || rc=$?
  if [ "$3" = FAIL ]; then assert_neq "0" "$rc" "scan-secrets: $1"; else assert_eq "0" "$rc" "scan-secrets: $1"; fi
}
scan_case "catches an UPPERCASE keyword secret" "$(printf 'const PASSWORD = \"%s\"\\n' "$CANARY_VALUE")" FAIL
scan_case "catches an unquoted env-style secret" "$(printf 'token=%s\\n' "$CANARY_VALUE")" FAIL
scan_case "catches a typed-assignment secret" "$(printf 'const password: string = \"%s\"\\n' "$CANARY_VALUE")" FAIL
scan_case "catches a backtick-literal secret" "$(printf 'const password = `%s`\\n' "$CANARY_VALUE")" FAIL
scan_case "does not flag a bare type annotation" 'interface C { refresh_token: ReadonlyRecordName }\n' PASS
scan_case "does not flag a keyword loop variable" 'for token in ("PROTOTYPE_MAP", "FRAME"):\n' PASS

# --- I-S1 containment: engine/helper failure must fail the scan (fault injection). ---
# Owner-mandated matrix: engine absent; exit 2; exit 42; stdout+non-zero; empty
# stdout+non-zero; both worktree and staged paths; final exit non-zero and the overall
# "Secret preflight result: PASS" line must never appear.
make_scanner_copy() { # $1 = extract-secrets.py replacement body; prints scan path
  local cp="$TMP/scancopy_$RANDOM"
  mkdir -p "$cp/security/scripts" "$cp/scripts"
  cp "$REPO/security/scripts/scan-secrets.sh" "$cp/security/scripts/"
  cp "$REPO/security/scripts/run-bounded.py" "$cp/security/scripts/"
  cp "$REPO/security/scripts/scan-files.py" "$cp/security/scripts/"
  cp "$REPO/scripts/manifest-stack.sh" "$cp/scripts/"
  printf '%s\n' "$1" > "$cp/security/scripts/extract-secrets.py"
  printf '%s' "$cp/security/scripts/scan-secrets.sh"
}
make_support_scanner_copy() { # $1 = scan-files.py replacement body; prints scan path
  local cp="$TMP/supportcopy_$RANDOM"
  mkdir -p "$cp/security/scripts" "$cp/scripts"
  cp "$REPO/security/scripts/scan-secrets.sh" "$cp/security/scripts/"
  cp "$REPO/security/scripts/run-bounded.py" "$cp/security/scripts/"
  cp "$REPO/security/scripts/extract-secrets.py" "$cp/security/scripts/"
  cp "$REPO/scripts/manifest-stack.sh" "$cp/scripts/"
  printf '%s\n' "$1" > "$cp/security/scripts/scan-files.py"
  printf '%s' "$cp/security/scripts/scan-secrets.sh"
}
FI="$TMP/fault-injection"
mkdir -p "$FI/src"
( cd "$FI" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore &&
  printf 'x=1\n' > src/base.py && git add -A && git -c user.name=t -c user.email=t@e commit -qm b ) >/dev/null 2>&1
printf 'password = "%s"\n' "$CANARY_VALUE" > "$FI/src/wt.py"
printf 'api_key = "%s"\n' "$CANARY_VALUE" > "$FI/src/staged.py"
( cd "$FI" && git add src/staged.py ) >/dev/null 2>&1
for variant in \
  "absent:" \
  "exit2:import sys; health=sys.argv[1:]==['--health-check']; print('extract-secrets:v1') if health else None; sys.exit(0 if health else 2)" \
  "exit42:import sys; health=sys.argv[1:]==['--health-check']; print('extract-secrets:v1') if health else None; sys.exit(0 if health else 42)" \
  "noisy:import sys; health=sys.argv[1:]==['--health-check']; print('extract-secrets:v1' if health else 'bogus finding'); sys.exit(0 if health else 3)" \
  "silent:import sys; health=sys.argv[1:]==['--health-check']; print('extract-secrets:v1') if health else None; sys.exit(0 if health else 3)"; do
  fi_name="${variant%%:*}"; fi_body="${variant#*:}"
  fi_scan="$(make_scanner_copy "$fi_body")"
  if [ "$fi_name" = absent ]; then rm -f "${fi_scan%scan-secrets.sh}extract-secrets.py"; fi
  set +e
  fi_out="$(cd "$FI" && bash "$fi_scan" 2>&1)"
  fi_rc=$?
  set -e
  assert_neq "0" "$fi_rc" "fault injection ($fi_name): engine failure fails the scan"
  assert_not_contains "$fi_out" "Secret preflight result: PASS" "fault injection ($fi_name): no overall PASS on engine failure"
  if [ "$fi_name" = silent ]; then
    assert_contains "$fi_out" "cannot verify worktree" "fault injection covers the worktree path"
    assert_contains "$fi_out" "cannot verify staged" "fault injection covers the staged path"
    # A failed worktree verification must not co-emit the contradictory per-check PASS.
    assert_not_contains "$fi_out" "PASS: no hard-coded secrets" "fault injection ($fi_name): no contradictory worktree PASS line"
  fi
done

# State-space cell: CLEAN input (no candidates on any path) x broken engine. The
# engine is never fed data on this cell, so only an UNCONDITIONAL health check can
# catch it -- a broken engine must fail the scan even when the repo is clean.
FI_CLEAN="$TMP/fault-clean"
mkdir -p "$FI_CLEAN/src"
( cd "$FI_CLEAN" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore &&
  printf 'x = 1\n' > src/clean.py ) >/dev/null 2>&1
fic_scan="$(make_scanner_copy 'import sys; sys.exit(42)')"
set +e
fic_out="$(cd "$FI_CLEAN" && bash "$fic_scan" 2>&1)"
fic_rc=$?
set -e
assert_neq "0" "$fic_rc" "clean-input fault: broken engine fails the scan even with zero candidates"
assert_not_contains "$fic_out" "Secret preflight result: PASS" "clean-input fault: no overall PASS"
assert_not_contains "$fic_out" "PASS: no hard-coded secrets" "clean-input fault: no unverified worktree PASS claim"

# State-space cell: REAL repo x broken git (exit 42 via PATH shim) x healthy engine.
# Only a CONFIRMED non-repo may downgrade git-backed checks to SKIP; a crashing or
# missing git must FAIL, never masquerade as "not a repo".
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
printf '#!/bin/sh\nexit 42\n' > "$FAKEBIN/git"
chmod +x "$FAKEBIN/git"
set +e
fg_out="$(cd "$FI_CLEAN" && PATH="$FAKEBIN:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
fg_rc=$?
set -e
assert_neq "0" "$fg_rc" "broken git in a real repo fails the scan instead of skipping"
assert_contains "$fg_out" "cannot determine git state" "broken git is reported as an undetermined git state"
assert_not_contains "$fg_out" "Secret preflight result: PASS" "broken git: no overall PASS"
assert_not_contains "$fg_out" "SKIP: staged scan" "broken git must not downgrade the staged scan to SKIP"

# State-space cell: CONFIRMED non-repo x healthy engine stays a legitimate explicit
# downgrade: both git-backed checks SKIP and the scan may pass on the other checks.
NONGIT="$TMP/non-git-clean"
mkdir -p "$NONGIT/src"
printf 'x = 1\n' > "$NONGIT/src/clean.py"
set +e
ng_out="$(cd "$NONGIT" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
ng_rc=$?
set -e
assert_eq "0" "$ng_rc" "confirmed non-repo with a healthy engine passes with explicit SKIPs"
assert_contains "$ng_out" "SKIP: .env ignore check" "confirmed non-repo skips the .env check explicitly"
assert_contains "$ng_out" "SKIP: staged scan" "confirmed non-repo skips the staged scan explicitly"

# --- Operation-result protocol cells: every external command's result contract
# (rc x output shape), not just domain axes. These enumerate known cells; they do
# NOT claim exhaustive state-space coverage. ---
REAL_GREP="$(command -v grep)"
REAL_SUPPORT="$REPO/security/scripts/scan-files.py"

# git rc 0 with garbage output is a MALFORMED success, not a confirmed answer.
GITGARBAGE="$TMP/git-garbage-bin"; mkdir -p "$GITGARBAGE"
printf '#!/bin/sh\nprintf "garbage\\n"\nexit 0\n' > "$GITGARBAGE/git"; chmod +x "$GITGARBAGE/git"
set +e
mg_out="$(cd "$FI_CLEAN" && PATH="$GITGARBAGE:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
mg_rc=$?
set -e
assert_neq "0" "$mg_rc" "malformed git success (garbage at rc 0) fails the scan"
assert_contains "$mg_out" "cannot determine git state" "malformed git success is undetermined, not confirmed non-repo"
assert_not_contains "$mg_out" "Secret preflight result: PASS" "malformed git success: no overall PASS"

# git absent (command-not-found rc 127) must FAIL, never SKIP.
GITABSENT="$TMP/git-absent-bin"; mkdir -p "$GITABSENT"
printf '#!/bin/sh\nexit 127\n' > "$GITABSENT/git"; chmod +x "$GITABSENT/git"
set +e
ga_out="$(cd "$FI_CLEAN" && PATH="$GITABSENT:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
ga_rc=$?
set -e
assert_neq "0" "$ga_rc" "absent git (rc 127) fails the scan"
assert_not_contains "$ga_out" "SKIP: staged scan" "absent git must not downgrade the staged scan to SKIP"

# Canonical staged-index search failure is a verification failure, not "no additions".
sg_scan="$(make_support_scanner_copy "import os,sys; a=sys.argv[1:]; (print('scan-files:v2') or sys.exit(0)) if a==['--health-check'] else (sys.exit(2) if a and a[0]=='staged' else os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*a]))")"
set +e
sg_out="$(cd "$FI" && bash "$sg_scan" 2>&1)"
sg_rc=$?
set -e
assert_neq "0" "$sg_rc" "staged index-search failure (exit 2) fails the scan"
assert_contains "$sg_out" "cannot verify staged" "staged index-search failure is reported"
assert_not_contains "$sg_out" "Secret preflight result: PASS" "staged filter failure: no overall PASS"

# log-hygiene search failure: execution integrity is mandatory even though its
# verdict is advisory -- an errored search must FAIL the scan, not WARN and PASS.
lg_scan="$(make_support_scanner_copy "import os,sys; a=sys.argv[1:]; (print('scan-files:v2') or sys.exit(0)) if a==['--health-check'] else (sys.exit(42) if 'log' in a else os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*a]))")"
set +e
lg_out="$(cd "$FI_CLEAN" && bash "$lg_scan" 2>&1)"
lg_rc=$?
set -e
assert_neq "0" "$lg_rc" "log-hygiene search failure fails the scan"
assert_contains "$lg_out" "cannot verify log hygiene" "log-hygiene search failure is reported as unverified"
assert_not_contains "$lg_out" "Secret preflight result: PASS" "log-hygiene search failure: no overall PASS"

# canonical enumerator emitting partial output then failing must not be accepted as a scope count.
ff_scan="$(make_support_scanner_copy "import os,sys; a=sys.argv[1:]; (print('scan-files:v2') or sys.exit(0)) if a==['--health-check'] else ((print('1') or sys.exit(42)) if 'count' in a else os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*a]))")"
set +e
ff_out="$(cd "$FI_CLEAN" && bash "$ff_scan" 2>&1)"
ff_rc=$?
set -e
assert_neq "0" "$ff_rc" "scope helper failure after partial output fails the scan"
assert_contains "$ff_out" "canonical scope enumerator failed" "scope helper failure is reported as an enumeration error"
assert_not_contains "$ff_out" "Secret preflight result: PASS" "scope helper failure: no overall PASS"

# engine malformed success: non-empty output on the benign health probe at rc 0 is
# not a healthy engine.
fi_scan_garbage="$(make_scanner_copy 'import sys; print("garbage finding"); sys.exit(0)')"
set +e
eg_out="$(cd "$FI_CLEAN" && bash "$fi_scan_garbage" 2>&1)"
eg_rc=$?
set -e
assert_neq "0" "$eg_rc" "engine malformed success (garbage at rc 0) fails the health check"
assert_contains "$eg_out" "health check failed" "engine malformed success is a failed health check"
assert_not_contains "$eg_out" "Secret preflight result: PASS" "engine malformed success: no overall PASS"

# sleeping engine: every engine invocation is bounded (SCAN_ENGINE_TIMEOUT); the scan
# must terminate and FAIL within the watchdog bound instead of hanging.
fi_scan_sleep="$(make_scanner_copy 'import time; time.sleep(300)')"
sl_out_file="$TMP/sleep-scan-out"
# -e-safe: the subshell inherits set -e, so the scan's expected non-zero rc must be
# captured with `|| rc=$?`, and the outer wait must not propagate it either.
( cd "$FI_CLEAN" && sl_rc=0 && { SCAN_ENGINE_TIMEOUT=1 bash "$fi_scan_sleep" > "$sl_out_file" 2>&1 || sl_rc=$?; } && printf 'scan_rc=%s\n' "$sl_rc" >> "$sl_out_file" ) &
sl_pid=$!
sl_done=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if ! kill -0 "$sl_pid" 2>/dev/null; then sl_done=1; break; fi
  sleep 1
done
if [ "$sl_done" = 1 ]; then
  wait "$sl_pid" 2>/dev/null || true
  if grep -q "scan_rc=0" "$sl_out_file" || grep -q "Secret preflight result: PASS" "$sl_out_file"; then
    fail "sleeping engine: bounded runner must fail the scan, not pass"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: sleeping engine is bounded and fails the scan"
  fi
else
  kill "$sl_pid" 2>/dev/null || true; wait "$sl_pid" 2>/dev/null || true
  fail "sleeping engine: scan did not terminate within the watchdog bound"
fi

# The manifest-stack reader is itself a mandatory dependency. A helper-internal
# command failure must not be converted into empty values and accepted as defaults.
MANIFESTSED="$TMP/manifest-sed-bin"; mkdir -p "$MANIFESTSED"
printf '#!/bin/sh\nexit 42\n' > "$MANIFESTSED/sed"; chmod +x "$MANIFESTSED/sed"
set +e
mh_out="$(cd "$FI_CLEAN" && PROJECT_MANIFEST="$REPO/.gitignore" PATH="$MANIFESTSED:$PATH" \
  bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
mh_rc=$?
set -e
assert_neq "0" "$mh_rc" "manifest helper dependency failure fails the scan"
assert_contains "$mh_out" "manifest" "manifest helper dependency failure is identified"
assert_not_contains "$mh_out" "Secret preflight result: PASS" "manifest helper dependency failure: no overall PASS"

# Manifest health must not trust a PATH-resolved mktemp. A hostile shim returning an
# existing victim path previously let the probe truncate and delete that file.
MKTEMPBIN="$TMP/manifest-mktemp-bin"; mkdir -p "$MKTEMPBIN"
MKTEMP_VICTIM="$TMP/manifest-mktemp-victim"
printf 'preserve-me\n' > "$MKTEMP_VICTIM"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$MKTEMP_VICTIM" > "$MKTEMPBIN/mktemp"
chmod +x "$MKTEMPBIN/mktemp"
set +e
mktemp_out="$(cd "$FI_CLEAN" && PATH="$MKTEMPBIN:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
mktemp_rc=$?
set -e
assert_eq "0" "$mktemp_rc" "hostile PATH mktemp cannot alter a healthy manifest probe"
if [[ -f "$MKTEMP_VICTIM" && "$(<"$MKTEMP_VICTIM")" == "preserve-me" ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: manifest probe preserves a hostile-shim victim"
else
  fail "manifest probe preserves a hostile-shim victim"
fi

# Engine health uses a positive handshake, not the absence of errors. A no-op
# python runtime returning rc 0 without executing the runner/extractor is malformed
# success and must not certify the engine.
NOOPPY="$TMP/noop-python-bin"; mkdir -p "$NOOPPY"
printf '#!/bin/sh\nexit 0\n' > "$NOOPPY/python3"; chmod +x "$NOOPPY/python3"
set +e
np_out="$(cd "$FI_CLEAN" && PATH="$NOOPPY:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
np_rc=$?
set -e
assert_neq "0" "$np_rc" "no-op python runtime cannot certify engine health"
assert_contains "$np_out" "health check failed" "no-op python runtime fails the positive engine handshake"
assert_not_contains "$np_out" "Secret preflight result: PASS" "no-op python runtime: no overall PASS"
assert_not_contains "$np_out" "PASS:" "no-op python runtime: no per-check PASS before runtime health is established"

# The runner handshake is the timeout trust-chain entry point. It must itself be
# bounded; otherwise a wedged python runtime can hang before the shared runner ever
# gets a chance to enforce SCAN_OPERATION_TIMEOUT.
SLOWPY="$TMP/slow-python-bin"; mkdir -p "$SLOWPY"
printf '#!/bin/sh\ncase "$1:$2" in *run-bounded.py:--health-check) sleep 5 ;; esac\nexec %s "$@"\n' \
  "$(command -v python3)" > "$SLOWPY/python3"
chmod +x "$SLOWPY/python3"
set +e
rp_start=$(date +%s)
rp_out="$(cd "$FI_CLEAN" && SCAN_OPERATION_TIMEOUT=0.2 PATH="$SLOWPY:$PATH" \
  bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
rp_rc=$?
rp_elapsed=$(( $(date +%s) - rp_start ))
set -e
assert_neq "0" "$rp_rc" "sleeping python runtime cannot certify runner health"
if [ "$rp_elapsed" -le 2 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: runner health handshake obeys the operation timeout"
else
  fail "runner health handshake obeys the operation timeout (elapsed=${rp_elapsed}s)"
fi
assert_not_contains "$rp_out" "PASS:" "sleeping python runtime: no PASS before runner health is established"

# The outer bootstrap deadline starts before any temp/evidence setup. Fault-inject a
# pre-health setup stall; the scanner must not wait for that stall to finish.
bootstrap_setup_scan="$(make_support_scanner_copy "import os,sys; os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*sys.argv[1:]])")"
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); s=p.read_text(); marker="  # BOOTSTRAP_WORKER_SETUP_START\n"; assert marker in s; p.write_text(s.replace(marker, marker + "  /bin/sleep 5\n", 1))' "$bootstrap_setup_scan"
set +e
bsu_start=$(date +%s)
bsu_out="$(cd "$FI_CLEAN" && SCAN_OPERATION_TIMEOUT=0.2 bash "$bootstrap_setup_scan" 2>&1)"
bsu_rc=$?
bsu_elapsed=$(( $(date +%s) - bsu_start ))
set -e
assert_neq "0" "$bsu_rc" "bootstrap setup stall fails before any scanner PASS"
if [[ "$bsu_elapsed" -le 2 ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: bootstrap deadline includes pre-health setup"
else
  fail "bootstrap deadline includes pre-health setup (elapsed=${bsu_elapsed}s)"
fi
assert_not_contains "$bsu_out" "PASS:" "bootstrap setup stall: no PASS"

# One portable bounded runner governs every mandatory subprocess, not only the
# extractor. Its timeout and command-not-found normalization are direct contracts.
BOUNDED_RUNNER="$REPO/security/scripts/run-bounded.py"
set +e
python3 "$BOUNDED_RUNNER" 0.1 python3 -c 'import time; time.sleep(5)' >/dev/null 2>&1
br_timeout_rc=$?
python3 "$BOUNDED_RUNNER" 1 definitely-not-a-real-command >/dev/null 2>&1
br_missing_rc=$?
set -e
assert_eq "124" "$br_timeout_rc" "bounded runner normalizes timeout to rc 124"
assert_eq "127" "$br_missing_rc" "bounded runner normalizes command-not-found to rc 127"

# Timeout owns the whole process group. A child that ignores SIGTERM must not survive
# merely because its parent exits first after the group's initial TERM.
BR_READY="$TMP/bounded-descendant-ready"
BR_MARKER="$TMP/bounded-descendant-marker"
set +e
READY="$BR_READY" MARKER="$BR_MARKER" python3 "$BOUNDED_RUNNER" 0.2 python3 -c '
import os, subprocess, sys, time
subprocess.Popen([sys.executable, "-c", """
import os, signal, time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
Path(os.environ[\"READY\"]).write_text(\"ready\")
time.sleep(1)
Path(os.environ[\"MARKER\"]).write_text(\"survived\")
"""])
while not os.path.exists(os.environ["READY"]):
    time.sleep(0.01)
time.sleep(300)
' >/dev/null 2>&1
br_group_rc=$?
set -e
if [[ -e "$BR_READY" ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: timeout descendant fixture reached its ready state"
else
  fail "timeout descendant fixture reached its ready state"
fi
sleep 1.2
assert_eq "124" "$br_group_rc" "bounded runner times out a process group with descendants"
if [[ ! -e "$BR_MARKER" ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: bounded runner reaps descendants that ignore SIGTERM"
else
  fail "bounded runner reaps descendants that ignore SIGTERM"
fi

# A mandatory filesystem search is bounded by the same runner as the engine.
bt_scan="$(make_support_scanner_copy "import os,sys,time; a=sys.argv[1:]; (print('scan-files:v2') or sys.exit(0)) if a==['--health-check'] else ((time.sleep(5) or sys.exit(0)) if 'worktree' in a else os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*a]))")"
set +e
bt_start=$(date +%s)
bt_out="$(cd "$FI_CLEAN" && SCAN_OPERATION_TIMEOUT=0.2 bash "$bt_scan" 2>&1)"
bt_rc=$?
bt_elapsed=$(( $(date +%s) - bt_start ))
set -e
assert_neq "0" "$bt_rc" "mandatory worktree search timeout fails the scan"
if [ "$bt_elapsed" -le 2 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: mandatory worktree search obeys the shared timeout"
else
  fail "mandatory worktree search obeys the shared timeout (elapsed=${bt_elapsed}s)"
fi
assert_not_contains "$bt_out" "Secret preflight result: PASS" "mandatory worktree search timeout: no overall PASS"

# The engine-specific value may narrow, never widen, the global operation deadline.
set +e
et_start=$(date +%s)
et_out="$(cd "$FI_CLEAN" && SCAN_OPERATION_TIMEOUT=0.2 SCAN_ENGINE_TIMEOUT=5 \
  bash "$fi_scan_sleep" 2>&1)"
et_rc=$?
et_elapsed=$(( $(date +%s) - et_start ))
set -e
assert_neq "0" "$et_rc" "engine timeout cannot widen the global operation timeout"
if [[ "$et_elapsed" -le 2 ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: engine timeout is capped by the global operation timeout"
else
  fail "engine timeout is capped by the global operation timeout (elapsed=${et_elapsed}s)"
fi
assert_not_contains "$et_out" "Secret preflight result: PASS" "widening engine timeout: no overall PASS"

# A healthy engine can still hang on real candidate input. Exercise both actual
# worktree and staged invocations, not only the initial health handshake.
sleeping_call_scan="$(make_scanner_copy "import sys,time; health=sys.argv[1:]==['--health-check']; print('extract-secrets:v1') if health else None; sys.exit(0) if health else time.sleep(300)")"
set +e
sc_out="$(cd "$FI" && SCAN_OPERATION_TIMEOUT=0.2 bash "$sleeping_call_scan" 2>&1)"
sc_rc=$?
set -e
assert_neq "0" "$sc_rc" "sleeping real engine invocations fail the scan"
assert_contains "$sc_out" "failed on worktree candidates (exit 124)" "worktree engine invocation obeys its timeout"
assert_contains "$sc_out" "failed on staged changes (exit 124)" "staged engine invocation obeys its timeout"
assert_not_contains "$sc_out" "Secret preflight result: PASS" "sleeping real engine invocations: no overall PASS"

# External grep is no longer in the trust surface; replacing it with a no-op cannot
# affect the canonical helper's worktree/staged verdicts.
NOOPGREP="$TMP/noop-grep-bin"; mkdir -p "$NOOPGREP"
printf '#!/bin/sh\nexit 0\n' > "$NOOPGREP/grep"; chmod +x "$NOOPGREP/grep"
set +e
ngrep_out="$(cd "$FI" && PATH="$NOOPGREP:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
ngrep_rc=$?
set -e
assert_neq "0" "$ngrep_rc" "no-op grep cannot hide a real worktree/staged secret"
assert_not_contains "$ngrep_out" "Secret preflight result: PASS" "no-op grep outside the trust surface: no overall PASS"

# At the canonical helper boundary, rc 0 plus empty stdout is malformed success.
noop_support_scan="$(make_support_scanner_copy "import os,sys; a=sys.argv[1:]; (print('scan-files:v2') or sys.exit(0)) if a==['--health-check'] else (sys.exit(0) if 'worktree' in a else os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*a]))")"
set +e
ns_out="$(cd "$FI" && bash "$noop_support_scan" 2>&1)"
ns_rc=$?
set -e
assert_neq "0" "$ns_rc" "no-op canonical worktree search cannot hide a real secret"
assert_contains "$ns_out" "malformed output" "no-op canonical search is identified as malformed success"
assert_not_contains "$ns_out" "Secret preflight result: PASS" "no-op canonical search: no overall PASS"

# A helper that admits it enumerated one artifact but scanned none must not be able to
# turn that unverified artifact into clean. Health is delegated to the real helper so
# this specifically exercises the coverage envelope, not the health sentinel.
coverage_support_scan="$(make_support_scanner_copy "import os,sys; a=sys.argv[1:]; (print('scan-files-search:v2:1:0:0') or sys.exit(0)) if 'worktree' in a else os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*a])")"
set +e
coverage_out="$(cd "$FI_CLEAN" && bash "$coverage_support_scan" 2>&1)"
coverage_rc=$?
set -e
assert_neq "0" "$coverage_rc" "artifact coverage mismatch cannot certify a clean worktree"
assert_contains "$coverage_out" "coverage mismatch" "artifact coverage mismatch is diagnosed explicitly"
assert_not_contains "$coverage_out" "Secret preflight result: PASS" "artifact coverage mismatch: no overall PASS"

# The invocation ledger is structural: deleting one successful operation record from
# an otherwise clean scanner copy must make the final roster reject the run.
ledger_scan="$(make_support_scanner_copy "import os,sys; os.execv(sys.executable,[sys.executable,r'$REAL_SUPPORT',*sys.argv[1:]])")"
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); s=p.read_text(); old="record_operation worktree_search VERIFIED"; assert old in s; p.write_text(s.replace(old, ": # fault: omitted worktree operation result", 1))' "$ledger_scan"
set +e
ledger_out="$(cd "$FI_CLEAN" && bash "$ledger_scan" 2>&1)"
ledger_rc=$?
set -e
assert_neq "0" "$ledger_rc" "missing mandatory invocation result fails the final ledger"
assert_contains "$ledger_out" "mandatory operation 'worktree_search' recorded no result" "missing invocation result is a protocol violation"
assert_not_contains "$ledger_out" "Secret preflight result: PASS" "missing invocation result: no overall PASS"

# Scope enumeration output is evidence only if every emitted path exists and is a
# regular file under an authorized target. A forged ghost path cannot make an empty
# source tree look scanned.
FI_EMPTY="$TMP/fault-empty"
mkdir -p "$FI_EMPTY/src"
( cd "$FI_EMPTY" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore &&
  git add .gitignore && git -c user.name=t -c user.email=t@e commit -qm b ) >/dev/null 2>&1
GHOSTFIND="$TMP/ghost-find-bin"; mkdir -p "$GHOSTFIND"
printf '#!/bin/sh\nprintf "src/ghost.py\\n"\nexit 0\n' > "$GHOSTFIND/find"; chmod +x "$GHOSTFIND/find"
set +e
ghost_out="$(cd "$FI_EMPTY" && PATH="$GHOSTFIND:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
ghost_rc=$?
set -e
assert_neq "0" "$ghost_rc" "forged find output cannot certify a non-empty scan scope"
assert_contains "$ghost_out" "scope is empty" "canonical enumerator ignores forged find output"
assert_not_contains "$ghost_out" "Secret preflight result: PASS" "forged find output: no overall PASS"

# Manifest parsing also needs a positive contract. A no-op sed must not erase a
# non-default source_roots value and silently redirect the scan to a clean default.
FI_MANIFEST="$TMP/fault-manifest-noop"
mkdir -p "$FI_MANIFEST/src" "$FI_MANIFEST/private"
( cd "$FI_MANIFEST" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'x = 1\n' > "$FI_MANIFEST/src/clean.py"
printf 'password = "%s"\n' "$CANARY_VALUE" > "$FI_MANIFEST/private/secret.py"
printf '%s\n' '- source_roots: private' '- source_extensions: py' > "$FI_MANIFEST/project-manifest.md"
NOOPSED="$TMP/noop-sed-bin"; mkdir -p "$NOOPSED"
printf '#!/bin/sh\nexit 0\n' > "$NOOPSED/sed"; chmod +x "$NOOPSED/sed"
set +e
ms_out="$(cd "$FI_MANIFEST" && PROJECT_MANIFEST="$FI_MANIFEST/project-manifest.md" \
  PATH="$NOOPSED:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
ms_rc=$?
set -e
assert_neq "0" "$ms_rc" "no-op manifest dependency cannot replace configured roots with defaults"
assert_contains "$ms_out" "manifest helper" "no-op manifest dependency fails its positive contract"
assert_not_contains "$ms_out" "Secret preflight result: PASS" "no-op manifest dependency: no overall PASS"

# A successful direct child may still leave descendants in its process group. The
# runner must close that group before returning, even when no timeout fired.
REAL_PYTHON="$(command -v python3)"
BR_EARLY_READY="$TMP/bounded-early-ready"
BR_EARLY_MARKER="$TMP/bounded-early-marker"
set +e
READY="$BR_EARLY_READY" MARKER="$BR_EARLY_MARKER" python3 "$BOUNDED_RUNNER" 2 python3 -c '
import os, subprocess, sys
subprocess.Popen([sys.executable, "-c", """
import os, signal, time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
Path(os.environ[\"READY\"]).write_text(\"ready\")
time.sleep(1)
Path(os.environ[\"MARKER\"]).write_text(\"survived\")
"""])
while not os.path.exists(os.environ["READY"]):
    pass
' >/dev/null 2>&1
br_early_rc=$?
set -e
if [[ -e "$BR_EARLY_READY" ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: early-exit descendant fixture reached its ready state"
else
  fail "early-exit descendant fixture reached its ready state"
fi
sleep 1.2
assert_eq "0" "$br_early_rc" "bounded runner preserves the successful direct-child rc"
if [[ ! -e "$BR_EARLY_MARKER" ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: bounded runner closes descendants after a successful parent exit"
else
  fail "bounded runner closes descendants after a successful parent exit"
fi

# A descendant can create a new session and escape the direct child's process group.
# Even when that escaped process inherits stdout/stderr, it must not keep the runner's
# caller pipe open beyond the operation bound.
set +e
br_escape_start=$(date +%s)
br_escape_out="$(python3 "$BOUNDED_RUNNER" 0.2 python3 -c '
import subprocess, sys
subprocess.Popen(
    [sys.executable, "-c", "import time; print(chr(120), flush=True); time.sleep(5)"],
    start_new_session=True,
)
' 2>&1)"
br_escape_rc=$?
br_escape_elapsed=$(( $(date +%s) - br_escape_start ))
set -e
assert_eq "0" "$br_escape_rc" "bounded runner preserves rc when an escaped descendant inherits output"
if [[ "$br_escape_elapsed" -le 2 ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: escaped descendant cannot hold the runner caller pipe open"
else
  fail "escaped descendant cannot hold the runner caller pipe open (elapsed=${br_escape_elapsed}s)"
fi

# Commands that need stdin opt into a runner-owned regular-file channel. This keeps
# an escaped descendant from retaining the upstream pipe while preserving input.
br_stdin_roundtrip="$(printf 'secret-input\n' | python3 "$BOUNDED_RUNNER" 1 --stdin /bin/cat)"
assert_eq "secret-input" "$br_stdin_roundtrip" "bounded runner preserves explicit stdin through an isolated channel"
set +e
br_stdin_start=$(date +%s)
br_stdin_out="$(python3 -c 'print("x" * 200000)' | python3 "$BOUNDED_RUNNER" 0.5 --stdin python3 -c '
import subprocess, sys
subprocess.Popen([sys.executable, "-c", "import time; time.sleep(5)"], start_new_session=True)
' 2>&1)"
br_stdin_rc=$?
br_stdin_elapsed=$(( $(date +%s) - br_stdin_start ))
set -e
assert_eq "0" "$br_stdin_rc" "bounded runner preserves rc with isolated stdin and an escaped descendant"
if [[ "$br_stdin_elapsed" -le 2 ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: escaped descendant cannot retain the runner input pipe"
else
  fail "escaped descendant cannot retain the runner input pipe (elapsed=${br_stdin_elapsed}s)"
fi

# Bootstrap timeout is outside the Python runner trust boundary, so it needs its own
# TERM->grace->KILL group policy. An outer trusted runner prevents this RED cell from
# hanging the test suite indefinitely.
IGNOREPY="$TMP/ignore-term-python-bin"; mkdir -p "$IGNOREPY"
printf '#!/bin/sh\ncase "$1:$2" in *run-bounded.py:--health-check) trap "" TERM; while :; do sleep 1; done ;; esac\nexec %s "$@"\n' \
  "$REAL_PYTHON" > "$IGNOREPY/python3"; chmod +x "$IGNOREPY/python3"
set +e
ib_out="$(cd "$FI_CLEAN" && "$REAL_PYTHON" "$BOUNDED_RUNNER" 3 env \
  SCAN_OPERATION_TIMEOUT=0.2 PATH="$IGNOREPY:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
ib_rc=$?
set -e
assert_neq "124" "$ib_rc" "runner bootstrap handles a TERM-ignoring runtime before the outer watchdog"
assert_neq "0" "$ib_rc" "TERM-ignoring runtime cannot certify runner health"
assert_not_contains "$ib_out" "PASS:" "TERM-ignoring runtime: no PASS before runner health"

# Option-shaped targets are never passed to find/grep. This fixture is isolated so a
# vulnerable GNU find can only damage the temporary directory during RED evidence.
OPT_TARGET="$TMP/option-target"
mkdir -p "$OPT_TARGET/-delete"
printf 'x = 1\n' > "$OPT_TARGET/-delete/marker.py"
set +e
opt_out="$(cd "$OPT_TARGET" && bash "$REPO/security/scripts/scan-secrets.sh" -delete 2>&1)"
opt_rc=$?
set -e
assert_neq "0" "$opt_rc" "option-shaped scan target is rejected"
assert_contains "$opt_out" "unsafe scan target" "option-shaped target rejection is explicit"
if [[ -e "$OPT_TARGET/-delete/marker.py" ]]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: option-shaped target cannot trigger a destructive find primary"
else
  fail "option-shaped target cannot trigger a destructive find primary"
fi

# Every explicit CLI target is in scope. A clean first target cannot hide a secret in
# the second target.
MULTI_TARGET="$TMP/multi-target"
mkdir -p "$MULTI_TARGET/clean" "$MULTI_TARGET/secret"
( cd "$MULTI_TARGET" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'x = 1\n' > "$MULTI_TARGET/clean/app.py"
printf 'password = "%s"\n' "$CANARY_VALUE" > "$MULTI_TARGET/secret/config.py"
set +e
multi_out="$(cd "$MULTI_TARGET" && bash "$REPO/security/scripts/scan-secrets.sh" clean secret 2>&1)"
multi_rc=$?
set -e
assert_neq "0" "$multi_rc" "all explicit scan targets are examined"
assert_contains "$multi_out" "hard-coded secrets found" "second explicit target cannot be omitted"
assert_not_contains "$multi_out" "Secret preflight result: PASS" "multi-target secret: no overall PASS"

# Helper basenames are not globally exempt. Only the scanner's own exact helper
# paths may be excluded; a requested source file with the same basename stays in scope.
BASENAME_SCOPE="$TMP/helper-basename-scope"
mkdir -p "$BASENAME_SCOPE/src"
( cd "$BASENAME_SCOPE" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'x = 1\n' > "$BASENAME_SCOPE/src/app.py"
printf 'api_key = "%s"\n' "$CANARY_VALUE" > "$BASENAME_SCOPE/src/extract-secrets.py"
set +e
basename_out="$(cd "$BASENAME_SCOPE" && bash "$REPO/security/scripts/scan-secrets.sh" src 2>&1)"
basename_rc=$?
set -e
assert_neq "0" "$basename_rc" "helper-like source basename cannot escape an explicit scan target"
assert_contains "$basename_out" "src/extract-secrets.py" "helper-like source file remains in canonical scope"
assert_not_contains "$basename_out" "Secret preflight result: PASS" "helper-like source basename: no overall PASS"

# Nested symlinks are an explicit scope error; silently omitting one can make the
# count non-zero from a clean file while skipping build-consumed source.
SYMLINK_SCOPE="$TMP/symlink-scope"
mkdir -p "$SYMLINK_SCOPE/src" "$SYMLINK_SCOPE/external"
( cd "$SYMLINK_SCOPE" && git init -q && git checkout -q -b main && printf '.env\n' > .gitignore ) >/dev/null 2>&1
printf 'x = 1\n' > "$SYMLINK_SCOPE/src/clean.py"
printf 'password = "%s"\n' "$CANARY_VALUE" > "$SYMLINK_SCOPE/external/linked.py"
ln -s ../external/linked.py "$SYMLINK_SCOPE/src/linked.py"
set +e
symlink_out="$(cd "$SYMLINK_SCOPE" && bash "$REPO/security/scripts/scan-secrets.sh" src 2>&1)"
symlink_rc=$?
set -e
assert_neq "0" "$symlink_rc" "nested source symlink cannot be silently omitted"
assert_contains "$symlink_out" "symbolic link" "symlink scope error is explicit"
assert_not_contains "$symlink_out" "Secret preflight result: PASS" "symlink scope error: no overall PASS"

# Bootstrap timing primitives are outside the verified runner. PATH cannot replace
# sleep with a TERM-ignoring hang and stall the health loop.
BAD_SLEEP="$TMP/bad-sleep-bin"; mkdir -p "$BAD_SLEEP"
printf '#!/bin/sh\ntrap "" TERM\nwhile :; do :; done\n' > "$BAD_SLEEP/sleep"; chmod +x "$BAD_SLEEP/sleep"
set +e
bs_out="$(cd "$FI_CLEAN" && "$REAL_PYTHON" "$BOUNDED_RUNNER" 3 env \
  PATH="$BAD_SLEEP:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
bs_rc=$?
set -e
assert_neq "124" "$bs_rc" "PATH sleep shim cannot hang the bootstrap watchdog"
assert_not_contains "$bs_out" "bounded runner health check failed" "trusted bootstrap timer ignores PATH sleep shim"

if python3 "$REPO/tests/test_scan_files.py"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scan-files byte corpus preserves coverage and source parity"
else
  fail "scan-files byte corpus preserves coverage and source parity"
fi

finish
