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

work_items = (repo / "scripts/work_items.py").read_text(encoding="utf-8")
if "load_protocol_registry" not in work_items:
    errors.append("work-item validator does not consume registry constraints")

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

finish
