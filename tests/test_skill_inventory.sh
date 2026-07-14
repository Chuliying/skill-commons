#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

CHECK="$REPO/scripts/check-skill-inventory.py"
INVENTORY="$REPO/docs/work/skill-bundle-convergence/ownership-inventory.md"

if [ ! -f "$CHECK" ]; then
  fail "skill inventory checker exists"
  finish
  exit 1
fi
if [ ! -f "$INVENTORY" ]; then
  fail "ownership inventory exists"
  finish
  exit 1
fi

run_check() {
  python3 "$CHECK" --inventory "$1" "${@:2}"
}

if real_output="$(run_check "$INVENTORY" 2>&1)"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: real ownership inventory reconciles current repository"
else
  echo "$real_output"
  fail "real ownership inventory reconciles current repository"
fi
assert_contains "$real_output" "PASS skill inventory reconciles" "real checker reports PASS"
assert_contains "$real_output" "active=24 workflow=23" "T06 inventory records the contracted active owner counts"
inventory_text="$(cat "$INVENTORY")"
assert_contains "$inventory_text" "| Git delivery | sync-work |" "Git delivery cluster has one current owner"
assert_contains "$inventory_text" "## T03 decisions applied through T06" "inventory advances the selected-decision checkpoint to T06"
assert_contains "$inventory_text" "## T06 retired old-owner residue classification" "inventory records the T06 residue classes"
inventory_intro="$(python3 - "$INVENTORY" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
intro = text.split("## Skill ownership inventory", 1)[1].split("| Skill |", 1)[0]
print(intro.strip())
PY
)"
assert_contains "$inventory_intro" "T06 has 7 core/personal owners" "current inventory intro states the T06 core/personal count"
assert_contains "$inventory_intro" "12 team-sprint owners" "current inventory intro states the T06 team-sprint count"
assert_contains "$inventory_intro" "10 optional capabilities" "current inventory intro states the T06 optional count"
assert_contains "$inventory_intro" "All 23 workflow skills fan out" "current inventory intro states the T06 workflow count"
assert_not_contains "$inventory_intro" "T04 has" "current inventory intro rejects the stale T04 checkpoint"
assert_not_contains "$inventory_intro" "eight core/personal owners" "current inventory intro rejects the stale eight-owner count"
assert_not_contains "$inventory_intro" "13 team-sprint owners" "current inventory intro rejects the stale 13-owner count"
assert_not_contains "$inventory_intro" "All 24 workflow skills fan out" "current inventory intro rejects the stale 24-workflow count"

expect_failure() {
  local label="$1" needle="$2" inventory="$3"
  shift 3
  set +e
  output="$(run_check "$inventory" "$@" 2>&1)"
  rc=$?
  set -e
  assert_neq "0" "$rc" "$label exits nonzero"
  assert_contains "$output" "$needle" "$label reports the contract drift"
  assert_not_contains "$output" "Traceback" "$label reports without traceback"
}

# Inventory row mutation: current active source still exists, but its owner row is gone.
python3 - "$INVENTORY" "$TMP/missing-skill.md" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
lines = [line for line in text.splitlines() if not line.startswith("| brainstorming |")]
Path(sys.argv[2]).write_text("\n".join(lines) + "\n")
PY
expect_failure "missing active skill row" "missing active skill row: brainstorming" "$TMP/missing-skill.md"

# Required per-skill consumer mapping cannot disappear behind an otherwise valid row.
python3 - "$INVENTORY" "$TMP/empty-skill-consumers.md" <<'PY'
from pathlib import Path
import sys

lines = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith("| brainstorming |"):
        cells = line.split("|")
        cells[6] = " "
        line = "|".join(cells)
    lines.append(line)
Path(sys.argv[2]).write_text("\n".join(lines) + "\n")
PY
expect_failure "empty skill consumer list" "empty required column: Skill ownership inventory.Consumer refs row=brainstorming" "$TMP/empty-skill-consumers.md"

# Profile mutation: make markdown part of core while keeping the frozen inventory.
mkdir -p "$TMP/profiles"
cp "$REPO"/profiles/* "$TMP/profiles/"
printf '\nmarkdown\n' >> "$TMP/profiles/core"
expect_failure "profile membership drift" "profile membership mismatch: markdown" "$INVENTORY" \
  --profiles-dir "$TMP/profiles"

# Registry mutation: add a new producer role that the inventory does not claim.
python3 - "$REPO/protocol-registry.json" "$TMP/registry.json" <<'PY'
from pathlib import Path
import json
import sys

registry = json.loads(Path(sys.argv[1]).read_text())
registry["execution_modes"]["refactor"]["artifacts"]["plan"]["producers"].append("security")
Path(sys.argv[2]).write_text(json.dumps(registry))
PY
expect_failure "registry role drift" "registry roles mismatch: security" "$INVENTORY" \
  --registry "$TMP/registry.json"

# The accepted qa-validate decision cannot regress to an undecided disposition.
python3 - "$INVENTORY" "$TMP/undecided-qa-validate.md" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
text = text.replace(
    "accepted T03: retain qa-validate as registry mode token mapped to qa validate",
    "undecided",
    1,
)
Path(sys.argv[2]).write_text(text)
PY
expect_failure "qa-validate retained disposition" \
  "qa-validate must map to qa with the accepted retained disposition" \
  "$TMP/undecided-qa-validate.md"

# Generated ownership mutations use copies; repository adapter roots stay untouched.
mkdir -p "$TMP/generated/.claude" "$TMP/generated/.codex" "$TMP/generated/.agents"
cp -R "$REPO/.claude/skills" "$TMP/generated/.claude/skills"
cp -R "$REPO/.codex/skills" "$TMP/generated/.codex/skills"
cp -R "$REPO/.agents/skills" "$TMP/generated/.agents/skills"
rm "$TMP/generated/.agents/skills/brainstorming/SKILL.md"
expect_failure "missing generated ownership" "generated file-set mismatch: .agents/skills/brainstorming" "$INVENTORY" \
  --generated-base "$TMP/generated"

cp "$REPO/brainstorming/SKILL.md" "$TMP/generated/.agents/skills/brainstorming/SKILL.md"
printf '\ndivergent fixture\n' >> "$TMP/generated/.codex/skills/brainstorming/SKILL.md"
expect_failure "divergent generated ownership" "generated content mismatch: .codex/skills/brainstorming/SKILL.md" "$INVENTORY" \
  --generated-base "$TMP/generated"

# Reference mutation: machine-readable source/consumer references must resolve.
python3 - "$INVENTORY" "$TMP/bad-reference.md" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
text = text.replace("tests/test_brainstorming.sh", "tests/no-such-consumer.sh", 1)
Path(sys.argv[2]).write_text(text)
PY
expect_failure "nonexistent consumer reference" "nonexistent repository reference: tests/no-such-consumer.sh" "$TMP/bad-reference.md"

# Every merge/removal hypothesis must retain its bounded migration consumer set.
python3 - "$INVENTORY" "$TMP/empty-hypothesis-consumers.md" <<'PY'
from pathlib import Path
import sys

lines = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith("| H-REQ-DESIGN |"):
        cells = line.split("|")
        cells[4] = " "
        line = "|".join(cells)
    lines.append(line)
Path(sys.argv[2]).write_text("\n".join(lines) + "\n")
PY
expect_failure "empty hypothesis consumer list" "empty required column: Bounded migration scopes.Bounded consumers row=H-REQ-DESIGN" "$TMP/empty-hypothesis-consumers.md"

finish
