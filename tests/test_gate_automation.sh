#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

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

finish
