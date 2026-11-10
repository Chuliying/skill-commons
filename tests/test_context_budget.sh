#!/usr/bin/env bash
# Focused context meter, ratchet, and lossless frontend disclosure checks.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

METER="$REPO/scripts/context-budget.sh"
METER_JSON="$TMP/context-budget.json"
CEILINGS="$REPO/tests/fixtures/context-budget/ceilings.json"
SECTIONS="$REPO/tests/fixtures/context-budget/frontend-sections.json"

assert_file "$METER" "context budget meter exists"
assert_file "$REPO/scripts/context-budget.py" "context budget parser exists"
assert_file "$CEILINGS" "context budget ceilings fixture exists"
assert_file "$SECTIONS" "frontend section preservation fixture exists"

if bash -n "$METER" && python3 -m py_compile "$REPO/scripts/context-budget.py"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: context budget meter syntax"
else
  fail "context budget meter syntax"
fi

# The entry point resolves its own repository root, so invocation does not
# depend on the caller's current working directory.
if (cd "$REPO/.." && bash "$METER" > "$TMP/from-parent.txt") &&
   grep -q '^Repository: ' "$TMP/from-parent.txt"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: meter runs from outside the repository"
else
  fail "meter runs from outside the repository"
fi

if bash "$METER" --json > "$METER_JSON"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: meter JSON output is available"
else
  fail "meter JSON output is available"
fi

if python3 - "$METER_JSON" "$REPO" <<'PY'
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
root = Path(sys.argv[2])
assert report["schema_version"] == "context-budget/v1"
assert "token values are intentionally not claimed" in report["units"]
rows = report["rows"]
assert len(rows) == 27, len(rows)
assert {row["harness"] for row in rows} == {"claude-code", "codex", "cursor"}
assert sum(row["class"] == "maintainer-ceiling" for row in rows) == 3
assert all(row["selection"] == "all" for row in rows if row["class"] == "maintainer-ceiling")
assert all("skill-creator" not in row["skills"] for row in rows)

expected_entries = {
    "claude-code": "CLAUDE.md",
    "codex": "AGENTS.md",
    "cursor": "bootstrap/directive.md",
}
for row in rows:
    assert row["entry"]["path"] == expected_entries[row["harness"]]
    assert row["required_router"]["reads"] == "once"
    assert row["linked_on_demand"]["reads"] == "separate"
    assert row["required_router"]["path"] == "skill-router/SKILL.md"
    assert row["linked_on_demand"]["path"] == "protocol-registry.json"
    assert row["required_read_bytes"] == sum(
        row["components"][name]
        for name in ("entry_bytes", "descriptions_bytes", "router_bytes")
    )
    assert row["total_with_on_demand_bytes"] == row["required_read_bytes"] + row["components"]["linked_registry_bytes"]
    if row["harness"] == "cursor":
        assert row["skill_fan_out"] is False
        assert row["descriptions"] == {"count": 0, "bytes": 0, "values": []}
        assert row["entry"]["kind"] == "template"
    else:
        assert row["skill_fan_out"] is True
        assert row["descriptions"]["count"] == len(row["skills"])
        assert row["descriptions"]["bytes"] > 0

inventory = report["inventory"]
assert len(inventory) == 24, len(inventory)
assert [item["bytes"] for item in inventory] == sorted(
    (item["bytes"] for item in inventory), reverse=True
)
assert "skill-creator" in {item["name"] for item in inventory}
assert all(not item["path"].startswith((".claude/", ".codex/", ".agents/", "_archive/")) for item in inventory)
assert all(isinstance(item["candidate_mandate_count"], int) for item in inventory)
assert len(report["excluded"]) == 4
assert {item["path"] for item in report["excluded"]} == {"_archive/", ".claude/", ".codex/", ".agents/"}

# A multiline description must include every block line. This catches the
# visualizer's historical first-line-only parser regression without a fixture
# repository or a new dependency.
parser_spec = importlib.util.spec_from_file_location(
    "context_budget_parser", root / "scripts/context-budget.py"
)
parser = importlib.util.module_from_spec(parser_spec)
parser_spec.loader.exec_module(parser)
with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
    handle.write("---\ndescription: |\n  first line\n  second line\nsource: fixture\n---\n")
    description_path = Path(handle.name)
try:
    parsed = parser.parse_frontmatter_description(description_path)
    assert parsed == "first line\nsecond line\n", repr(parsed)
    assert len(parsed.encode("utf-8")) == len("first line\nsecond line\n".encode("utf-8"))
finally:
    description_path.unlink()
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: profile/platform matrix and 24-skill inventory are bounded"
else
  fail "profile/platform matrix and 24-skill inventory are bounded"
fi

human_output="$(bash "$METER")"
assert_eq "27" "$(printf '%s\n' "$human_output" | grep -c '^ROW ')" "human meter prints all profile/harness rows"
assert_eq "1" "$(printf '%s\n' "$human_output" | grep -c '^Excluded:')" "human meter names exclusions once"
assert_contains "$human_output" "class=maintainer-ceiling" "human meter labels PROFILE=all as maintainer ceiling"
assert_contains "$human_output" "harness=cursor" "human meter reports Cursor separately"
assert_contains "$human_output" "installed_descriptions count=0 bytes=0 skill_fan_out=false" "Cursor description total is zero"
assert_contains "$human_output" "required_router path=skill-router/SKILL.md" "router is counted once per row"
assert_contains "$human_output" "linked_on_demand path=protocol-registry.json" "registry is separate on-demand material"

# --triage is content keyed. A stale quote is an ordinary nonzero result with a
# bounded count, not a parser traceback.
if bash "$METER" --triage "$REPO/tests/fixtures/context-budget/triage-valid.md" > "$TMP/triage-valid.txt"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: valid content-keyed triage resolves"
else
  fail "valid content-keyed triage resolves"
fi
valid_triage="$(cat "$TMP/triage-valid.txt")"
assert_contains "$valid_triage" "class=drop count=1" "triage reports drop count"
assert_contains "$valid_triage" "class=keep count=1" "triage reports keep count"
assert_contains "$valid_triage" "class=gate count=1" "triage reports gate count"
assert_contains "$valid_triage" "unresolved_count=0" "valid triage has no unresolved quote"

set +e
bash "$METER" --triage "$REPO/tests/fixtures/context-budget/triage-stale.md" > "$TMP/triage-stale.txt" 2>&1
stale_rc=$?
set -e
assert_neq "0" "$stale_rc" "stale content-keyed triage exits nonzero"
stale_triage="$(cat "$TMP/triage-stale.txt")"
assert_contains "$stale_triage" "unresolved_count=1" "stale triage reports unresolved count"
assert_not_contains "$stale_triage" "Traceback" "stale triage does not crash"

ratchet_check() {
  python3 - "$METER_JSON" "$CEILINGS" "${CONTEXT_BUDGET_CEILING:-}" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
fixture = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
override = int(sys.argv[3]) if sys.argv[3] else None
expected_rows = fixture["rows"]
actual_rows = {row["id"]: row for row in report["rows"]}
errors = []
if set(actual_rows) != set(expected_rows):
    errors.append(f"row-set mismatch actual={len(actual_rows)} ceiling={len(expected_rows)}")
for row_id, limits in expected_rows.items():
    row = actual_rows.get(row_id)
    if row is None:
        continue
    actual = dict(row["components"])
    actual["required_read_bytes"] = row["required_read_bytes"]
    actual["total_with_on_demand_bytes"] = row["total_with_on_demand_bytes"]
    for component in fixture["components"]:
        ceiling = override if override is not None else limits[component]
        if actual[component] > ceiling:
            errors.append(
                f"row={row_id} component={component} actual={actual[component]} "
                f"ceiling={ceiling} excess={actual[component] - ceiling}"
            )
        if len(errors) >= 8:
            break
    if len(errors) >= 8:
        break
if errors:
    print("context budget ceiling failure:", file=sys.stderr)
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print(f"context budget ceilings pass rows={len(actual_rows)} components={len(fixture['components'])}")
PY
}

if ratchet_output="$(ratchet_check 2>&1)"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: measured per-row ceilings hold"
else
  echo "$ratchet_output"
  fail "measured per-row ceilings hold"
fi

set +e
negative_output="$(CONTEXT_BUDGET_CEILING=1 ratchet_check 2>&1)"
negative_rc=$?
set -e
assert_neq "0" "$negative_rc" "CONTEXT_BUDGET_CEILING=1 fails"
assert_contains "$negative_output" "row=claude-code|personal" "ceiling failure names the row"
assert_contains "$negative_output" "component=entry_bytes" "ceiling failure names the component"
assert_contains "$negative_output" "excess=" "ceiling failure names the excess"

router_lines="$(wc -l < "$REPO/skill-router/SKILL.md" | tr -d ' ')"
router_bytes="$(wc -c < "$REPO/skill-router/SKILL.md" | tr -d ' ')"
# 6747 -> 6800 (2026-10-31, T09): the English router restores rule wording a byte-squeezed
# translation had weakened; see router_budget_amendments in the ceilings fixture.
if [ "$router_lines" -le 180 ] && [ "$router_bytes" -lt 6800 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: context budget suite owns router 180-line/6800-byte gate"
else
  fail "context budget suite owns router 180-line/6800-byte gate"
fi

if python3 - "$REPO" "$SECTIONS" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
fixture = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
main = root / fixture["source"]
main_text = main.read_text(encoding="utf-8")
assert main.stat().st_size < 30000
assert fixture["baseline_bytes"] == 87327
assert len(fixture["baseline_sha256"]) == 64

retained = [item for item in fixture["sections"] if item["disposition"] == "retained"]
moved = [item for item in fixture["sections"] if item["disposition"] == "moved"]
files = [main] + sorted((root / "design-taste-frontend/references").glob("*.md"))
combined = "\n".join(path.read_text(encoding="utf-8") for path in files)

# The original upstream preamble/frontmatter survives verbatim exactly once, either
# at the top of the entry or in a reference that holds the upstream core.
preamble_owner = root / fixture.get("preamble_location", fixture["source"])
owner_bytes = preamble_owner.read_bytes()
pre_start = owner_bytes.index(b"---\nname: design-taste-frontend\n")
preamble = owner_bytes[pre_start:pre_start + fixture["preamble_bytes"]]
assert hashlib.sha256(preamble).hexdigest() == fixture["preamble_sha256"]
assert combined.count(preamble.decode("utf-8")) == 1
for item in fixture["sections"]:
    assert combined.count(item["heading"]) == 1, item["heading"]

def section_chunk(text, heading, headings):
    start = text.index(heading)
    ends = [position for candidate in headings if candidate != heading
            for position in [text.find(candidate, start + len(heading))]
            if position >= 0]
    end = min(ends) if ends else len(text)
    return text[start:end].encode("utf-8")

for item in retained:
    chunk = section_chunk(main_text, item["heading"], [x["heading"] for x in retained])
    assert len(chunk) == item["baseline_bytes"], item["heading"]
    assert hashlib.sha256(chunk).hexdigest() == item["baseline_sha256"], item["heading"]

for item in moved:
    owners = [path for path in files if item["heading"] in path.read_text(encoding="utf-8")]
    assert len(owners) == 1, item["heading"]
    owner_text = owners[0].read_text(encoding="utf-8")
    chunk = section_chunk(owner_text, item["heading"], [x["heading"] for x in moved])
    assert len(chunk) == item["baseline_bytes"], item["heading"]
    assert hashlib.sha256(chunk).hexdigest() == item["baseline_sha256"], item["heading"]

# Every new local Markdown reference is linked by the main skill and resolves.
links = set(re.findall(r"\]\((references/[^)#]+\.md)\)", main_text))
expected = {f"references/{path.name}" for path in files[1:]}
assert links == expected, (links, expected)
for href in links:
    assert (main.parent / href).is_file(), href
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: frontend sections and preamble match durable hashes"
else
  fail "frontend sections and preamble match durable hashes"
fi

finish
