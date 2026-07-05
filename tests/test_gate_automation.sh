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

finish
