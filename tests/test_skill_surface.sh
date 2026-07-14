#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

CHECKER="$REPO/scripts/measure-skill-surface.py"
REPORT="$REPO/docs/work/skill-bundle-convergence/surface-inventory.md"
assert_file "$CHECKER" "skill surface checker exists"
assert_file "$REPORT" "skill surface report exists"

if [ -f "$CHECKER" ] && [ -f "$REPORT" ]; then
  if output="$(python3 "$CHECKER" --root "$REPO" --check --format json 2>&1)"; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: current T07 final surface passes strict thresholds"
  else
    printf '%s\n' "$output"
    fail "current T07 final surface passes strict thresholds"
  fi

  if printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
b = d["baseline"]
t04 = d["t04_checkpoint"]
c = d["current"]
assert b["default_installed_skills"] == 13
assert b["router_bytes"] == 6747
assert b["micro_route_bytes"] == 17411
assert b["default_skill_bytes"] == 82468
assert b["physical"]["files"] == 231
assert b["physical"]["bytes"] == 1320279
assert t04["default_installed_skills"] == 8
assert t04["router_bytes"] == 6722
assert t04["micro_route_bytes"] == 17386
assert t04["default_skill_bytes"] == 55344
assert t04["support"] == {"files": 62, "lines": 10499, "bytes": 483900}
assert t04["physical"] == {"files": 176, "lines": 29086, "bytes": 1103600}
assert c["default_installed_skills"] == 7
assert c["personal_installed_skills"] == 7
assert c["team_sprint_installed_skills"] == 12
assert c["optional_capabilities"] == 10
assert c["router_bytes"] < b["router_bytes"]
assert c["micro_route_bytes"] < b["micro_route_bytes"]
assert c["default_skill_bytes"] < b["default_skill_bytes"]
assert c["generated_core"] == {k: c["core_source"][k] * 3 for k in ("files", "lines", "bytes")}
parts = (c["core_source"], c["generated_core"], c["support"], c["profile_registry"])
assert c["physical"] == {k: sum(part[k] for part in parts) for k in ("files", "lines", "bytes")}
assert c["physical"]["files"] <= b["physical"]["files"]
assert c["physical"]["bytes"] < b["physical"]["bytes"]
'; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: surface JSON reproduces frozen baseline and current aggregate"
  else
    fail "surface JSON reproduces frozen baseline and current aggregate"
  fi

  if printf '%s' "$output" | python3 -c '
import json, sys
t04 = json.load(sys.stdin)["t04_checkpoint"]
assert t04["core_source"] == {"files": 28, "lines": 4570, "bytes": 153354}
'; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: T04 checkpoint freezes core source files lines and bytes"
  else
    fail "T04 checkpoint freezes core source files lines and bytes"
  fi

  if printf '%s' "$output" | python3 -c '
import json, sys
t04 = json.load(sys.stdin)["t04_checkpoint"]
assert t04["generated_core"] == {"files": 84, "lines": 13710, "bytes": 460062}
'; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: T04 checkpoint freezes generated core files lines and bytes"
  else
    fail "T04 checkpoint freezes generated core files lines and bytes"
  fi

  if printf '%s' "$output" | python3 -c '
import json, sys
t05 = json.load(sys.stdin)["t05_checkpoint"]
assert t05 == {
    "default_installed_skills": 8,
    "router_bytes": 6708,
    "micro_route_bytes": 17372,
    "default_skill_bytes": 58966,
    "core_source": {"files": 28, "lines": 4616, "bytes": 156976},
    "generated_core": {"files": 84, "lines": 13848, "bytes": 470928},
    "support": {"files": 62, "lines": 10688, "bytes": 493154},
    "profile_registry": {"files": 2, "lines": 307, "bytes": 6284},
    "physical": {"files": 176, "lines": 29459, "bytes": 1127342},
}
'; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: T05 checkpoint is frozen for T06 contraction"
  else
    fail "T05 checkpoint is frozen for T06 contraction"
  fi

  if printf '%s' "$output" | python3 -c '
import json, sys
t06 = json.load(sys.stdin)["t06_checkpoint"]
assert t06 == {
    "default_installed_skills": 7,
    "router_bytes": 6708,
    "micro_route_bytes": 17372,
    "default_skill_bytes": 48542,
    "core_source": {"files": 25, "lines": 4132, "bytes": 140886},
    "generated_core": {"files": 75, "lines": 12396, "bytes": 422658},
    "support": {"files": 62, "lines": 10774, "bytes": 498365},
    "profile_registry": {"files": 2, "lines": 306, "bytes": 6253},
    "physical": {"files": 164, "lines": 27608, "bytes": 1068162},
}
'; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: accepted T06 checkpoint is frozen for T07 final reporting"
  else
    fail "accepted T06 checkpoint is frozen for T07 final reporting"
  fi

  generated_report="$(python3 "$CHECKER" --root "$REPO" --format markdown)"
  assert_eq "$(cat "$REPORT")" "$generated_report" "checked-in surface report matches deterministic output"
  assert_contains "$generated_report" "# T07 final deterministic surface inventory" "surface report advances to the T07 final phase"
  assert_contains "$generated_report" "| Metric | Frozen baseline | T07 final current | Delta |" "surface report preserves the baseline to T07 comparison"
  assert_contains "$generated_report" "## Accepted T06 checkpoint → T07 final" "surface report renders the accepted T06 to T07 comparison"
  assert_not_contains "$generated_report" "T07 has not begun" "surface report removes the stale pre-T07 statement"

  printf '%s' "$output" > "$TMP/surface.json"
  printf '%s' "$generated_report" > "$TMP/generated-report.md"
  if python3 - "$TMP/surface.json" "$TMP/generated-report.md" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
report = Path(sys.argv[2]).read_text()
t06 = data["t06_checkpoint"]
current = data["current"]

def signed(value):
    return f"{value:+,d}"

def row(label, key):
    old = t06[key]
    new = current[key]
    return (
        f"| {label} | {old['files']:,} / {old['lines']:,} / {old['bytes']:,} | "
        f"{new['files']:,} / {new['lines']:,} / {new['bytes']:,} | "
        f"{signed(new['files'] - old['files'])} files / "
        f"{signed(new['lines'] - old['lines'])} lines / "
        f"{signed(new['bytes'] - old['bytes'])} bytes |"
    )

for label, key in (
    ("Core source", "core_source"),
    ("Three generated core mirrors", "generated_core"),
    ("Tests + scripts", "support"),
    ("Core profile + registry", "profile_registry"),
    ("Physical aggregate", "physical"),
):
    assert row(label, key) in report, row(label, key)
PY
  then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: surface report renders exact accepted T06 to T07 batch deltas"
  else
    fail "surface report renders exact accepted T06 to T07 batch deltas"
  fi

  cp "$REPO/profiles/core" "$TMP/core"
  printf '%s\n' brainstorming caveman-review finishing-a-development-branch grilling shared-skill-onboarder to-prd >> "$TMP/core"
  if python3 "$CHECKER" --root "$REPO" --core-profile "$TMP/core" --check >/dev/null 2>&1; then
    fail "surface checker rejects restored 13-owner default"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: surface checker rejects restored 13-owner default"
  fi
fi

finish
