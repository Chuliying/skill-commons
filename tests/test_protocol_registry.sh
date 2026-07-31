#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

protocol_conformance() {
python3 - "$REPO" "$1" <<'PY'
import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
path = Path(sys.argv[2])
errors = []
try:
    registry = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"cannot load protocol registry: {exc}")
    raise SystemExit(1)

if registry.get("schema_version") != "skill-commons/protocol-registry/v1":
    errors.append("unexpected protocol registry schema")

non_goals = set(registry.get("non_goals", []))
for expected in ("runtime-engine", "state-machine", "scheduler"):
    if expected not in non_goals:
        errors.append(f"registry non-goals missing {expected}")

expected_modes = {
    "team-feature": {
        "artifacts": {
            "prd": "required",
            "spec": "required",
            "qa-plan": "required",
            "plan": "required",
            "implement-report": "required",
            "qa-report": "required",
        },
        "handoff": "qa-validate",
        "human_gates": ["prd", "team-design", "release"],
    },
    "personal-feature": {
        "artifacts": {
            "prd": "optional",
            "spec": "absent",
            "qa-plan": "absent",
            "plan": "optional",
            "implement-report": "required",
            "qa-report": "absent",
        },
        "handoff": "verification-before-completion",
        "human_gates": ["release"],
    },
    "bug-fix": {
        "artifacts": {
            "prd": "absent",
            "spec": "absent",
            "qa-plan": "absent",
            "plan": "optional",
            "implement-report": "required",
            "qa-report": "absent",
        },
        "handoff": "verification-before-completion",
        "human_gates": ["release"],
    },
    "refactor": {
        "artifacts": {
            "prd": "required",
            "spec": "optional",
            "qa-plan": "absent",
            "plan": "optional",
            "implement-report": "required",
            "qa-report": "absent",
        },
        "handoff": "verification-before-completion",
        "human_gates": ["release"],
    },
}

modes = registry.get("execution_modes", {})
if set(modes) != set(expected_modes):
    errors.append(f"execution mode set mismatch: {sorted(modes)}")
for mode, expected in expected_modes.items():
    actual = modes.get(mode, {})
    requirements = {
        name: record.get("requirement")
        for name, record in actual.get("artifacts", {}).items()
    }
    if requirements != expected["artifacts"]:
        errors.append(f"{mode} artifact requirements mismatch: {requirements}")
    if actual.get("handoff") != expected["handoff"]:
        errors.append(f"{mode} handoff mismatch")
    if actual.get("human_gates") != expected["human_gates"]:
        errors.append(f"{mode} human gates mismatch")
    for name, record in actual.get("artifacts", {}).items():
        producers = record.get("producers", [])
        if record.get("requirement") != "absent" and not producers:
            errors.append(f"{mode}.{name} lacks a producer")

work_item = registry.get("work_item", {})
if work_item.get("schema_version") != "work-item/v3":
    errors.append("work-item schema mismatch")
if work_item.get("work_statuses") != ["active", "completed", "abandoned"]:
    errors.append("work status contract mismatch")
expected_evidence = {
    "not_requested": [],
    "awaiting_approval": [],
    "approved": ["approval_ref"],
    "pr_created": ["approval_ref", "pr_url"],
    "merged": ["approval_ref", "merge_sha"],
    "deployed": ["approval_ref", "merge_sha", "deployment_id"],
}
delivery = work_item.get("delivery_statuses", {})
if {key: value.get("required_evidence") for key, value in delivery.items()} != expected_evidence:
    errors.append("delivery evidence contract mismatch")
if {key: value.get("allowed_evidence") for key, value in delivery.items()} != expected_evidence:
    errors.append("delivery allowed-evidence contract mismatch")

profiles = registry.get("profiles", {})
expected_profiles = {"core", "team-sprint", "personal", "optional", "frontend"}
if set(profiles) != expected_profiles:
    errors.append(f"profile contract set mismatch: {sorted(profiles)}")
if profiles.get("team-sprint", {}).get("conflicts") != ["personal"]:
    errors.append("team-sprint/profile conflict missing")
if profiles.get("personal", {}).get("conflicts") != ["team-sprint"]:
    errors.append("personal/profile conflict missing")

for value in (registry,):
    encoded = json.dumps(value, sort_keys=True)
    for forbidden in ('"commands"', '"handlers"', '"scheduler_config"', '"runtime_steps"'):
        if forbidden in encoded:
            errors.append(f"registry contains runtime orchestration key {forbidden}")

router = (repo / "skill-router/SKILL.md").read_text(encoding="utf-8")
implement = (repo / "implement/SKILL.md").read_text(encoding="utf-8")
for name, text in (("router", router), ("implement", implement)):
    if "../protocol-registry.json" not in text:
        errors.append(f"{name} does not reference the protocol registry")
if re.search(r"(?m)^\| `(?:team-feature|personal-feature|bug-fix|refactor)` \|", implement):
    errors.append("implement duplicates the execution-mode matrix")

# ADR-R3 I-M1: consumers reach the registry through scripts/execution_modes.py. This
# used to require work_items.py to load the registry itself, which is now the thing to
# forbid -- a second loader is a second place the contract can be read differently.
work_items = (repo / "scripts/work_items.py").read_text(encoding="utf-8")
grader = (repo / "journey-evals/scripts/grade_journey.py").read_text(encoding="utf-8")
for name, text in (("work-item validator", work_items), ("journey grader", grader)):
    if "execution_modes" not in text:
        errors.append(f"{name} does not consume the shared execution-mode accessor")
    if "json.loads" in text and "protocol-registry.json" in text:
        errors.append(f"{name} loads the registry directly instead of via the accessor")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print("protocol registry conformance ok")
PY
}

if protocol_conformance "$REPO/protocol-registry.json"
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: protocol registry is the declarative contract owner"
else
  fail "protocol registry is the declarative contract owner"
fi

python3 - "$REPO/protocol-registry.json" "$TMP/extra-profile.json" <<'PY'
import copy
import json
import sys
from pathlib import Path

registry = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
mutant = copy.deepcopy(registry)
mutant["profiles"]["extra-profile"] = {
    "kind": "capability-pack",
    "requires": ["core"],
    "conflicts": [],
}
Path(sys.argv[2]).write_text(json.dumps(mutant), encoding="utf-8")
PY
if protocol_conformance "$TMP/extra-profile.json" >/dev/null 2>&1; then
  fail "protocol conformance rejects undeclared extra profile names"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: protocol conformance rejects undeclared extra profile names"
fi

if python3 "$REPO/scripts/check_protocol_registry.py" "$REPO/protocol-registry.json" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: protocol registry machine checker accepts the canonical contract"
else
  fail "protocol registry machine checker accepts the canonical contract"
fi

python3 - "$REPO/protocol-registry.json" "$TMP" <<'PY'
import copy
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])

bad_requirement = copy.deepcopy(source)
bad_requirement["execution_modes"]["personal-feature"]["artifacts"]["prd"]["requirement"] = "sometimes"
(root / "bad-requirement.json").write_text(json.dumps(bad_requirement))

bad_producer = copy.deepcopy(source)
bad_producer["execution_modes"]["team-feature"]["artifacts"]["prd"]["producers"] = []
(root / "bad-producer.json").write_text(json.dumps(bad_producer))

bad_conflict = copy.deepcopy(source)
bad_conflict["profiles"]["personal"]["conflicts"] = []
(root / "bad-conflict.json").write_text(json.dumps(bad_conflict))

runtime_engine = copy.deepcopy(source)
runtime_engine["runtime_steps"] = ["execute-the-agent"]
(root / "runtime-engine.json").write_text(json.dumps(runtime_engine))

bad_allowed_evidence = copy.deepcopy(source)
bad_allowed_evidence["work_item"]["delivery_statuses"]["approved"]["allowed_evidence"] = []
(root / "bad-allowed-evidence.json").write_text(json.dumps(bad_allowed_evidence))
PY

for case_name in bad-requirement bad-producer bad-conflict runtime-engine bad-allowed-evidence; do
  set +e
  invalid_output="$(python3 "$REPO/scripts/check_protocol_registry.py" "$TMP/$case_name.json" 2>&1)"
  invalid_rc=$?
  set -e
  assert_neq "0" "$invalid_rc" "protocol checker rejects $case_name"
  assert_not_contains "$invalid_output" "Traceback" "protocol checker reports $case_name without a traceback"
done

mkdir -p "$TMP/.codex/skills" "$TMP/.claude/skills"
if PROFILE=all bash "$REPO/bootstrap/generate.sh" "$TMP/.claude/skills" "$TMP/.codex/skills" >/dev/null &&
   [ -f "$TMP/.claude/skills/protocol-registry.json" ] &&
   [ -f "$TMP/.codex/skills/protocol-registry.json" ] &&
   [ -f "$TMP/.claude/skills/scripts/check_protocol_registry.py" ] &&
   [ -f "$TMP/.codex/skills/scripts/check_protocol_registry.py" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: fan-out publishes the protocol registry"
else
  fail "fan-out publishes the protocol registry"
fi

# ADR-R3 I-M1: exactly one stage-requirement source. Both work_items.py and
# grade_journey.py must reach the contract through the shared accessor rather than
# carrying their own per-mode artifact lists -- a second list is how the grader and
# the validator drift apart while both look correct.
assert_file "$REPO/scripts/execution_modes.py" "execution-mode accessor module exists"
modes_source="$(cat "$REPO/scripts/execution_modes.py" 2>/dev/null || true)"
assert_contains "$modes_source" "protocol-registry.json" "accessor derives modes from the registry, not its own table"

work_items_source="$(cat "$REPO/scripts/work_items.py")"
grader_source="$(cat "$REPO/journey-evals/scripts/grade_journey.py")"
assert_contains "$work_items_source" "execution_modes" "work-item validator imports the shared accessor"
assert_contains "$grader_source" "execution_modes" "journey grader imports the shared accessor"

# I-M1: no hardcoded per-mode artifact list anywhere in the grader. An earlier version
# of this gate grepped for the exact string '"qa-plan.md",' WITH a trailing comma, so it
# matched only the one historical spelling and missed three surviving tuples written
# without it. Match the filename in any quoted form instead, and allow only the lines
# that define the registry-derived helper.
if python3 - "$REPO/journey-evals/scripts/grade_journey.py" <<'PY'; then
import re, sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
offenders = []
for number, line in enumerate(source.splitlines(), 1):
    if "execution_modes" in line or "canonical_file" in line:
        continue          # the derivation itself, not a restatement
    if line.lstrip().startswith("#"):
        continue
    # A violation is a LITERAL COLLECTION of artifact names -- two quoted names with
    # only a comma between them, as in `for name in ("prd.md", "spec.md")`. Passing two
    # separate paths as arguments (`f(work / "prd.md", work / "qa-plan.md")`) is not a
    # per-mode list, so requiring adjacency keeps the gate precise instead of noisy.
    pairs = re.findall(
        r'"(?:prd|spec|qa-plan|qa-report|plan)\.md"\s*,\s*"(?:prd|spec|qa-plan|qa-report|plan)\.md"',
        line,
    )
    if pairs:
        offenders.append("line %d: %s" % (number, line.strip()[:80]))
if offenders:
    print("\n".join(offenders))
    raise SystemExit(1)
print("no hardcoded per-mode artifact list")
PY
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: grader carries no hardcoded per-mode artifact list"
else
  fail "grader carries no hardcoded per-mode artifact list"
fi

# I-M2: the accessor and the registry must agree on the mode roster, checked by
# machine rather than by two documents being edited together.
if python3 - "$REPO" <<'PY'; then
import json, sys
from pathlib import Path
repo = Path(sys.argv[1])
sys.path.insert(0, str(repo / "scripts"))
import execution_modes
registry = json.loads((repo / "protocol-registry.json").read_text(encoding="utf-8"))
if set(execution_modes.mode_names()) != set(registry["execution_modes"]):
    raise SystemExit("accessor mode roster diverges from the registry")
for mode in registry["execution_modes"]:
    declared = {
        name: spec["requirement"]
        for name, spec in registry["execution_modes"][mode]["artifacts"].items()
    }
    if execution_modes.stage_requirements(mode) != declared:
        raise SystemExit(f"accessor requirements diverge for {mode}")
PY
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: accessor and registry agree on every mode contract"
else
  fail "accessor and registry agree on every mode contract"
fi

# T04 Foundation consumer drift-check, kept as an invariant rather than a one-time
# cleanup. Foundation owns the Artifact Ref shape; a consumer PRD that restates the
# field list will drift from it silently, because both documents keep reading
# plausibly. The consumer must reference foundation/schema.py instead.
orchestration_prd="$REPO/docs/work/cross-repo-task-orchestration/prd.md"
if [ -f "$orchestration_prd" ]; then
  if python3 - "$REPO" "$orchestration_prd" <<'PY'; then
import re, sys
from pathlib import Path

repo, prd_path = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(repo))
from foundation import schema

prd = prd_path.read_text(encoding="utf-8")
errors = []

# The consumer must point at the owner of the shape.
for marker in ("foundation/schema.py", "validate_artifact_ref"):
    if marker not in prd:
        errors.append(f"consumer PRD does not reference {marker}")

# A restatement is a line that enumerates most of the owned field set in prose. Two
# or more field names outside a reference line is how the previous duplication read.
owned = [f for f in schema.ARTIFACT_REF_FIELDS if f not in ("repo_id",)]
prose_names = {"commit OID": "commit_oid", "content digest": "digest",
               "artifact kind": "artifact_kind", "repo-relative path": "path"}
for line_number, line in enumerate(prd.splitlines(), 1):
    if "foundation/schema.py" in line or "ARTIFACT_REF_FIELDS" in line:
        continue
    hits = [prose for prose in prose_names if prose in line]
    if len(hits) >= 2:
        errors.append(
            f"line {line_number}: restates Foundation-owned Artifact Ref fields {hits}"
        )

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print(f"consumer drift-check ok (owned fields: {', '.join(owned)})")
PY
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: orchestration PRD references Foundation instead of restating it"
  else
    fail "orchestration PRD references Foundation instead of restating it"
  fi
fi

# Program T06 system convergence, as an invariant. Two consumers sit on Foundation and
# meet at exactly one contract: ADR-004 makes InitiativeScope the only integration
# point between Product Scope and Orchestration. Convergence found them disagreeing --
# the orchestration PRD did not mention InitiativeScope at all, so a projected scope
# had no declared consumer. This keeps both ends naming the same contract, with the
# producer owning its shape.
product_prd="$REPO/docs/work/product-scope-graph/prd.md"
if [ -f "$orchestration_prd" ] && [ -f "$product_prd" ]; then
  if python3 - "$orchestration_prd" "$product_prd" <<'PY'; then
import sys
from pathlib import Path

orch = Path(sys.argv[1]).read_text(encoding="utf-8")
prod = Path(sys.argv[2]).read_text(encoding="utf-8")
errors = []

for name, text in (("orchestration", orch), ("product-scope", prod)):
    if "InitiativeScope" not in text:
        errors.append(f"{name} PRD does not name the InitiativeScope integration contract")

# Both source kinds must be declared on both ends, otherwise one side silently
# supports a path the other never produces.
for kind in ("accepted-scope-delta", "manual-initiative-scope"):
    for name, text in (("orchestration", orch), ("product-scope", prod)):
        if kind not in text:
            errors.append(f"{name} PRD does not declare source_kind {kind}")

# The producer owns the field list; the consumer must reference it rather than restate.
if "requirement_topology" in orch and "product-scope-graph/prd.md" not in orch:
    errors.append("orchestration restates InitiativeScope fields without referencing the owner")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print("consumer convergence ok (single integration contract: InitiativeScope v1)")
PY
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: both consumers converge on one integration contract"
  else
    fail "both consumers converge on one integration contract"
  fi
fi

finish
