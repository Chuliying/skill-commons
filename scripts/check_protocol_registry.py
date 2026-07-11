#!/usr/bin/env python3
"""Validate the declarative skill-commons protocol registry."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


SCHEMA = "skill-commons/protocol-registry/v1"
REQUIREMENTS = {"required", "optional", "absent"}
PROFILE_KINDS = {"base", "delivery-mode", "capability-pack"}
NON_GOALS = {"runtime-engine", "state-machine", "scheduler"}
FORBIDDEN_RUNTIME_KEYS = {"commands", "handlers", "runtime_steps", "scheduler_config"}
DELIVERY_EVIDENCE_KEYS = {"approval_ref", "pr_url", "merge_sha", "deployment_id"}


def duplicates(values: list[str]) -> set[str]:
    return {value for value in values if values.count(value) > 1}


def walk_keys(value: object) -> list[str]:
    keys: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            keys.append(str(key))
            keys.extend(walk_keys(child))
    elif isinstance(value, list):
        for child in value:
            keys.extend(walk_keys(child))
    return keys


def validate(registry: dict) -> list[str]:
    errors: list[str] = []
    if registry.get("schema_version") != SCHEMA:
        errors.append(f"schema_version must be {SCHEMA}")

    non_goals = registry.get("non_goals")
    if not isinstance(non_goals, list) or not NON_GOALS.issubset(set(non_goals)):
        errors.append("non_goals must include runtime-engine, state-machine, and scheduler")
    if FORBIDDEN_RUNTIME_KEYS.intersection(walk_keys(registry)):
        errors.append("registry must not contain runtime orchestration keys")

    declared_requirements = registry.get("artifact_requirements")
    if not isinstance(declared_requirements, list) or set(declared_requirements) != REQUIREMENTS:
        errors.append("artifact_requirements must define required, optional, and absent exactly once")
    elif duplicates(declared_requirements):
        errors.append("artifact_requirements contains duplicates")

    modes = registry.get("execution_modes")
    if not isinstance(modes, dict) or not modes:
        errors.append("execution_modes must be a non-empty mapping")
        modes = {}
    for mode, record in modes.items():
        if not isinstance(record, dict):
            errors.append(f"execution_modes.{mode} must be a mapping")
            continue
        artifacts = record.get("artifacts")
        if not isinstance(artifacts, dict) or not artifacts:
            errors.append(f"execution_modes.{mode}.artifacts must be non-empty")
            continue
        for name, artifact in artifacts.items():
            if not isinstance(artifact, dict):
                errors.append(f"execution_modes.{mode}.artifacts.{name} must be a mapping")
                continue
            requirement = artifact.get("requirement")
            producers = artifact.get("producers")
            if requirement not in REQUIREMENTS:
                errors.append(f"{mode}.{name} has invalid requirement: {requirement}")
            if not isinstance(producers, list) or any(not isinstance(value, str) or not value for value in producers):
                errors.append(f"{mode}.{name} producers must be a string list")
                continue
            if duplicates(producers):
                errors.append(f"{mode}.{name} producers contains duplicates")
            if requirement == "absent" and producers:
                errors.append(f"{mode}.{name} is absent and must not name producers")
            if requirement in {"required", "optional"} and not producers:
                errors.append(f"{mode}.{name} requires at least one producer")
        if not isinstance(record.get("handoff"), str) or not record["handoff"]:
            errors.append(f"execution_modes.{mode}.handoff must be a non-empty string")
        gates = record.get("human_gates")
        if not isinstance(gates, list) or any(not isinstance(value, str) or not value for value in gates):
            errors.append(f"execution_modes.{mode}.human_gates must be a string list")
        elif duplicates(gates):
            errors.append(f"execution_modes.{mode}.human_gates contains duplicates")

    work_item = registry.get("work_item")
    if not isinstance(work_item, dict):
        errors.append("work_item must be a mapping")
        work_item = {}
    work_statuses = work_item.get("work_statuses")
    if not isinstance(work_statuses, list) or not work_statuses:
        errors.append("work_item.work_statuses must be a non-empty list")
        work_status_set: set[str] = set()
    else:
        work_status_set = set(work_statuses)
        if duplicates(work_statuses):
            errors.append("work_item.work_statuses contains duplicates")
    delivery = work_item.get("delivery_statuses")
    if not isinstance(delivery, dict) or not delivery:
        errors.append("work_item.delivery_statuses must be a non-empty mapping")
        delivery = {}
    evidence_keys: set[str] = set()
    for status, rule in delivery.items():
        if not isinstance(rule, dict):
            errors.append(f"delivery_statuses.{status} must be a mapping")
            continue
        unknown_rule_keys = set(rule) - {
            "allowed_work_statuses",
            "allowed_evidence",
            "required_evidence",
        }
        if unknown_rule_keys:
            errors.append(
                f"delivery_statuses.{status} has unknown keys: {sorted(unknown_rule_keys)}"
            )
        allowed_work = rule.get("allowed_work_statuses")
        allowed_evidence = rule.get("allowed_evidence")
        required_evidence = rule.get("required_evidence")
        if not isinstance(allowed_work, list) or not allowed_work:
            errors.append(f"delivery_statuses.{status}.allowed_work_statuses must be non-empty")
        elif not set(allowed_work).issubset(work_status_set):
            errors.append(f"delivery_statuses.{status} names an unknown work status")
        if not isinstance(allowed_evidence, list) or any(
            not isinstance(value, str) or not value for value in allowed_evidence
        ):
            errors.append(f"delivery_statuses.{status}.allowed_evidence must be a string list")
            allowed_evidence_set: set[str] = set()
        else:
            allowed_evidence_set = set(allowed_evidence)
            if duplicates(allowed_evidence):
                errors.append(f"delivery_statuses.{status}.allowed_evidence contains duplicates")
            unknown_evidence = allowed_evidence_set - DELIVERY_EVIDENCE_KEYS
            if unknown_evidence:
                errors.append(
                    f"delivery_statuses.{status}.allowed_evidence has unknown keys: "
                    f"{sorted(unknown_evidence)}"
                )
            evidence_keys.update(allowed_evidence_set)
        if not isinstance(required_evidence, list) or any(
            not isinstance(value, str) or not value for value in required_evidence
        ):
            errors.append(f"delivery_statuses.{status}.required_evidence must be a string list")
        else:
            if duplicates(required_evidence):
                errors.append(f"delivery_statuses.{status}.required_evidence contains duplicates")
            if not set(required_evidence).issubset(allowed_evidence_set):
                errors.append(
                    f"delivery_statuses.{status}.required_evidence must be allowed"
                )
    if not DELIVERY_EVIDENCE_KEYS.issubset(evidence_keys):
        errors.append("delivery evidence contract is incomplete")

    profiles = registry.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        errors.append("profiles must be a non-empty mapping")
        profiles = {}
    profile_names = set(profiles)
    for name, profile in profiles.items():
        if not isinstance(profile, dict):
            errors.append(f"profiles.{name} must be a mapping")
            continue
        if profile.get("kind") not in PROFILE_KINDS:
            errors.append(f"profiles.{name} has invalid kind")
        for field in ("requires", "conflicts"):
            values = profile.get(field)
            if not isinstance(values, list):
                errors.append(f"profiles.{name}.{field} must be a list")
                continue
            if name in values:
                errors.append(f"profiles.{name}.{field} must not reference itself")
            unknown = set(values) - profile_names
            if unknown:
                errors.append(f"profiles.{name}.{field} names unknown profiles: {sorted(unknown)}")
        for conflict in profile.get("conflicts", []):
            other = profiles.get(conflict, {})
            if name not in other.get("conflicts", []):
                errors.append(f"profile conflict must be symmetric: {name} <-> {conflict}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    default = Path(__file__).resolve().parent.parent / "protocol-registry.json"
    parser.add_argument("registry", nargs="?", type=Path, default=default)
    args = parser.parse_args()
    try:
        payload = json.loads(args.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"cannot load protocol registry: {exc}", file=sys.stderr)
        return 2
    if not isinstance(payload, dict):
        print("protocol registry root must be a mapping", file=sys.stderr)
        return 1
    errors = validate(payload)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"protocol registry valid: {args.registry}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
