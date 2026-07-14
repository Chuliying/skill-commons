#!/usr/bin/env python3
"""Reconcile the skill ownership inventory with repository-owned contracts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


GENERATED_ROOTS = (".claude/skills", ".codex/skills", ".agents/skills")
REQUIRED_CLUSTERS = {
    "requirements",
    "design",
    "develop/debug/verify",
    "Git delivery",
    "onboarding",
    "prototype",
    "frontend",
    "documentation",
    "orchestration",
}
REQUIRED_EDGES = {
    "protocol-artifact-producers",
    "protocol-handoffs",
    "profile-resolution",
    "bootstrap-selection",
    "bootstrap-ownership",
    "generated-mirrors",
    "focused-tests",
    "full-tests",
    "public-docs",
    "consuming-compatibility",
}
REQUIRED_HYPOTHESES = {
    "H-REQ-DESIGN",
    "H-DEVELOP-VERIFY",
    "H-GIT-DELIVERY",
    "H-DEFAULT-PROFILE",
    "H-OPTIONAL-PRODUCT",
}
ALLOWED_CLASSIFICATIONS = {
    "unique capability",
    "conceptual overlap",
    "duplicated control plane",
    "host-specific",
    "optional tooling",
}


class InventoryError(ValueError):
    pass


def split_table_row(line: str) -> list[str]:
    return [cell.strip().strip("`") for cell in line.strip().strip("|").split("|")]


def table_under(text: str, heading: str) -> list[dict[str, str]]:
    lines = text.splitlines()
    marker = f"## {heading}"
    try:
        start = lines.index(marker) + 1
    except ValueError as exc:
        raise InventoryError(f"missing required section: {heading}") from exc
    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break
    block = [line for line in lines[start:end] if line.strip().startswith("|")]
    if len(block) < 3:
        raise InventoryError(f"required table is empty: {heading}")
    headers = split_table_row(block[0])
    separator = split_table_row(block[1])
    if len(headers) != len(separator) or not all(re.fullmatch(r":?-{3,}:?", cell) for cell in separator):
        raise InventoryError(f"malformed table header: {heading}")
    rows: list[dict[str, str]] = []
    for line in block[2:]:
        cells = split_table_row(line)
        if len(cells) != len(headers):
            raise InventoryError(f"malformed table row in {heading}: {line}")
        rows.append(dict(zip(headers, cells)))
    if not rows:
        raise InventoryError(f"required table is empty: {heading}")
    return rows


def section_text(text: str, heading: str) -> str:
    lines = text.splitlines()
    marker = f"## {heading}"
    try:
        start = lines.index(marker) + 1
    except ValueError as exc:
        raise InventoryError(f"missing required section: {heading}") from exc
    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break
    body = "\n".join(lines[start:end]).strip()
    if not body:
        raise InventoryError(f"required section is empty: {heading}")
    return body


def csv_set(value: str) -> set[str]:
    if value in ("", "none"):
        return set()
    return {item.strip().strip("`") for item in value.split(",") if item.strip()}


def role_set(value: str) -> set[str]:
    if value in ("", "none"):
        return set()
    return {item.strip().strip("`") for item in value.split(";") if item.strip()}


def require_columns(
    rows: list[dict[str, str]],
    section: str,
    identity_column: str,
    required_columns: tuple[str, ...],
    errors: list[str],
    allow_none: set[str] | None = None,
) -> None:
    allow_none = allow_none or set()
    for row in rows:
        identity = row.get(identity_column, "").strip() or "<unknown>"
        for column in required_columns:
            value = row.get(column, "").strip()
            if not value or (value == "none" and column not in allow_none):
                errors.append(f"empty required column: {section}.{column} row={identity}")


def active_skills(root: Path) -> set[str]:
    return {
        path.name
        for path in root.iterdir()
        if path.is_dir() and (path / "SKILL.md").is_file()
    }


def parse_profile(name: str, profiles_dir: Path, stack: tuple[str, ...] = ()) -> set[str]:
    if name in stack:
        raise InventoryError(f"profile include cycle: {' -> '.join((*stack, name))}")
    path = profiles_dir / name
    if not path.is_file():
        raise InventoryError(f"profile file missing: {path}")
    result: set[str] = set()
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        token = raw.split("#", 1)[0].strip().replace(" ", "").replace("\t", "")
        if not token:
            continue
        if token.startswith("@"):
            result.update(parse_profile(token[1:], profiles_dir, (*stack, name)))
        else:
            result.add(token)
    return result


def load_registry(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise InventoryError(f"cannot load protocol registry: {exc}") from exc
    if not isinstance(value, dict):
        raise InventoryError("protocol registry root must be an object")
    return value


def file_map(path: Path) -> dict[str, str]:
    if not path.is_dir():
        return {}
    result: dict[str, str] = {}
    for file in sorted(candidate for candidate in path.rglob("*") if candidate.is_file()):
        relative = file.relative_to(path).as_posix()
        result[relative] = hashlib.sha256(file.read_bytes()).hexdigest()
    return result


def validate_references(root: Path, tables: list[list[dict[str, str]]], errors: list[str]) -> None:
    reference_columns = {"Source refs", "Consumer refs", "Evidence refs", "Bounded consumers"}
    checked: set[str] = set()
    for rows in tables:
        for row in rows:
            for column in reference_columns & set(row):
                for reference in csv_set(row[column]):
                    reference = reference.split("#", 1)[0]
                    if reference in checked:
                        continue
                    checked.add(reference)
                    path = Path(reference)
                    if path.is_absolute() or ".." in path.parts or not (root / path).exists():
                        errors.append(f"nonexistent repository reference: {reference}")


def registry_contract(registry: dict, token_owners: dict[str, str]) -> tuple[set[str], dict[str, set[str]]]:
    tokens: set[str] = set()
    roles: dict[str, set[str]] = {}
    modes = registry.get("execution_modes", {})
    if not isinstance(modes, dict):
        raise InventoryError("registry execution_modes must be an object")
    for mode, mode_record in modes.items():
        artifacts = mode_record.get("artifacts", {})
        for artifact, artifact_record in artifacts.items():
            for producer in artifact_record.get("producers", []):
                tokens.add(producer)
                roles.setdefault(producer, set()).add(f"producer:{mode}/{artifact}")
        handoff = mode_record.get("handoff")
        if handoff:
            tokens.add(handoff)
            owner = token_owners.get(handoff)
            if owner:
                role = f"handoff:{mode}" if owner == handoff else f"handoff-alias:{mode}/{handoff}"
                roles.setdefault(owner, set()).add(role)
    return tokens, roles


def check(args: argparse.Namespace) -> tuple[list[str], dict[str, int]]:
    root = args.root.resolve()
    inventory_path = args.inventory.resolve()
    profiles_dir = args.profiles_dir.resolve()
    registry_path = args.registry.resolve()
    generated_base = args.generated_base.resolve()
    errors: list[str] = []

    try:
        text = inventory_path.read_text(encoding="utf-8")
        evidence = section_text(text, "Evidence boundary")
        skills_rows = table_under(text, "Skill ownership inventory")
        cluster_rows = table_under(text, "Responsibility cluster summaries")
        token_rows = table_under(text, "Registry token map")
        edge_rows = table_under(text, "Verified dependency edges")
        hypothesis_rows = table_under(text, "Bounded migration scopes")
        selected_decisions = section_text(text, "T03 decisions applied through T06")
    except (OSError, InventoryError) as exc:
        return [str(exc)], {"active": 0, "workflow": 0, "profiles": 0, "tokens": 0}

    for label in ("Machine extraction", "Direct verification", "Architectural judgment"):
        if label not in evidence:
            errors.append(f"evidence boundary missing class: {label}")
    if not selected_decisions:
        errors.append("selected T03 decisions section is empty")

    require_columns(
        skills_rows,
        "Skill ownership inventory",
        "Skill",
        (
            "Skill",
            "Cluster",
            "Profiles",
            "Classification",
            "Source refs",
            "Consumer refs",
            "Registry roles",
            "Generated disposition",
            "Selected migration disposition",
        ),
        errors,
        allow_none={"Registry roles"},
    )
    require_columns(
        cluster_rows,
        "Responsibility cluster summaries",
        "Group",
        ("Group", "Current owners", "Boundary", "Evidence class", "Evidence refs"),
        errors,
    )
    require_columns(
        token_rows,
        "Registry token map",
        "Token",
        ("Token", "Kind", "Mapped owner", "Source refs", "Consumer refs", "Disposition"),
        errors,
    )
    require_columns(
        edge_rows,
        "Verified dependency edges",
        "ID",
        ("ID", "Kind", "Owner", "Source refs", "Consumer refs", "Direct verification"),
        errors,
    )
    require_columns(
        hypothesis_rows,
        "Bounded migration scopes",
        "ID",
        ("ID", "Scope", "Candidate skills", "Bounded consumers", "Evidence class", "Selected disposition"),
        errors,
    )

    active = active_skills(root)
    workflow = active - {"skill-creator"}
    skill_by_name = {row.get("Skill", ""): row for row in skills_rows}
    if len(skill_by_name) != len(skills_rows):
        errors.append("duplicate or empty skill inventory row")
    for name in sorted(active - set(skill_by_name)):
        errors.append(f"missing active skill row: {name}")
    for name in sorted(set(skill_by_name) - active):
        errors.append(f"inventory row has no active top-level skill: {name}")

    try:
        registry = load_registry(registry_path)
    except InventoryError as exc:
        return [*errors, str(exc)], {"active": len(active), "workflow": len(workflow), "profiles": 0, "tokens": 0}
    profile_names = set(registry.get("profiles", {}))
    resolved_profiles: dict[str, set[str]] = {}
    try:
        for profile in profile_names:
            resolved_profiles[profile] = parse_profile(profile, profiles_dir)
    except InventoryError as exc:
        errors.append(str(exc))
    for profile, names in resolved_profiles.items():
        for name in sorted(names - workflow):
            errors.append(f"profile {profile} has no active workflow skill: {name}")
    covered = set().union(*resolved_profiles.values()) if resolved_profiles else set()
    for name in sorted(workflow - covered):
        errors.append(f"active workflow skill is absent from profiles: {name}")

    expected_membership: dict[str, set[str]] = {name: set() for name in active}
    for profile, names in resolved_profiles.items():
        for name in names:
            expected_membership.setdefault(name, set()).add(profile)
    expected_membership["skill-creator"] = {"maintainer-only"}
    for name in sorted(active & set(skill_by_name)):
        classifications = role_set(skill_by_name[name].get("Classification", ""))
        invalid_classifications = classifications - ALLOWED_CLASSIFICATIONS
        for classification in sorted(invalid_classifications):
            errors.append(f"invalid skill classification: {name} -> {classification}")
        actual = csv_set(skill_by_name[name].get("Profiles", ""))
        expected = expected_membership.get(name, set())
        if actual != expected:
            errors.append(
                f"profile membership mismatch: {name} expected={','.join(sorted(expected))} actual={','.join(sorted(actual))}"
            )
        if f"{name}/SKILL.md" not in csv_set(skill_by_name[name].get("Source refs", "")):
            errors.append(f"skill source reference missing: {name}/SKILL.md")
        generated = skill_by_name[name].get("Generated disposition", "")
        if name == "skill-creator":
            if generated != "maintainer-only:not-generated":
                errors.append("skill-creator generated disposition mismatch")
        elif not all(root_name in generated for root_name in GENERATED_ROOTS):
            errors.append(f"generated disposition missing workflow mirrors: {name}")
    observed_classifications = set().union(
        *(role_set(row.get("Classification", "")) for row in skills_rows)
    ) if skills_rows else set()
    for classification in sorted(ALLOWED_CLASSIFICATIONS - observed_classifications):
        errors.append(f"skill classification is not collectively represented: {classification}")

    token_by_name = {row.get("Token", ""): row for row in token_rows}
    if len(token_by_name) != len(token_rows):
        errors.append("duplicate or empty registry token row")
    token_owners = {token: row.get("Mapped owner", "") for token, row in token_by_name.items()}
    try:
        registry_tokens, expected_roles = registry_contract(registry, token_owners)
    except InventoryError as exc:
        registry_tokens, expected_roles = set(), {}
        errors.append(str(exc))
    for token in sorted(registry_tokens - set(token_by_name)):
        errors.append(f"missing registry token row: {token}")
    for token in sorted(set(token_by_name) - registry_tokens):
        errors.append(f"inventory registry token is not active: {token}")
    for token in sorted(registry_tokens & set(token_by_name)):
        owner = token_owners[token]
        if owner not in active:
            errors.append(f"registry token owner is not an active skill: {token} -> {owner}")
        expected_kind = "handoff" if any(
            mode.get("handoff") == token for mode in registry.get("execution_modes", {}).values()
        ) else "producer"
        if token_by_name[token].get("Kind") != expected_kind:
            errors.append(f"registry token kind mismatch: {token}")
    qa_row = token_by_name.get("qa-validate", {})
    qa_disposition = "accepted T03: retain qa-validate as registry mode token mapped to qa validate"
    if qa_row.get("Mapped owner") != "qa" or qa_row.get("Disposition") != qa_disposition:
        errors.append("qa-validate must map to qa with the accepted retained disposition")
    for name in sorted(active & set(skill_by_name)):
        actual_roles = role_set(skill_by_name[name].get("Registry roles", ""))
        expected = expected_roles.get(name, set())
        if actual_roles != expected:
            errors.append(
                f"registry roles mismatch: {name} expected={';'.join(sorted(expected)) or 'none'} actual={';'.join(sorted(actual_roles)) or 'none'}"
            )

    cluster_by_name = {row.get("Group", ""): row for row in cluster_rows}
    for cluster in sorted(REQUIRED_CLUSTERS - set(cluster_by_name)):
        errors.append(f"missing responsibility cluster: {cluster}")
    inventory_clusters: dict[str, set[str]] = {}
    for name, row in skill_by_name.items():
        inventory_clusters.setdefault(row.get("Cluster", ""), set()).add(name)
    for cluster, names in inventory_clusters.items():
        if cluster not in cluster_by_name:
            errors.append(f"skill cluster lacks summary: {cluster}")
            continue
        declared = csv_set(cluster_by_name[cluster].get("Current owners", ""))
        if declared != names:
            errors.append(f"cluster owner mismatch: {cluster}")

    edge_kinds = {row.get("Kind", "") for row in edge_rows}
    for kind in sorted(REQUIRED_EDGES - edge_kinds):
        errors.append(f"missing dependency edge kind: {kind}")
    hypothesis_ids = {row.get("ID", "") for row in hypothesis_rows}
    for hypothesis in sorted(REQUIRED_HYPOTHESES - hypothesis_ids):
        errors.append(f"missing bounded migration hypothesis: {hypothesis}")
    for row in hypothesis_rows:
        for name in csv_set(row.get("Candidate skills", "")):
            if name not in active:
                errors.append(f"migration hypothesis names inactive skill: {name}")

    validate_references(
        root,
        [skills_rows, cluster_rows, token_rows, edge_rows, hypothesis_rows],
        errors,
    )

    for generated_root in GENERATED_ROOTS:
        target = generated_base / generated_root
        generated_names = {
            path.name for path in target.iterdir() if path.is_dir() and (path / "SKILL.md").is_file()
        } if target.is_dir() else set()
        missing = sorted(workflow - generated_names)
        extra = sorted(generated_names - workflow)
        if missing or extra:
            errors.append(
                f"generated owner set mismatch: {generated_root} missing={','.join(missing) or 'none'} extra={','.join(extra) or 'none'}"
            )
        for name in sorted(workflow):
            source_files = file_map(root / name)
            generated_files = file_map(target / name)
            if set(source_files) != set(generated_files):
                errors.append(f"generated file-set mismatch: {generated_root}/{name}")
                continue
            for relative in sorted(source_files):
                if source_files[relative] != generated_files[relative]:
                    errors.append(f"generated content mismatch: {generated_root}/{name}/{relative}")

    return errors, {
        "active": len(active),
        "workflow": len(workflow),
        "profiles": len(profile_names),
        "tokens": len(registry_tokens),
    }


def main() -> int:
    script_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=script_root)
    parser.add_argument("--profiles-dir", type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--generated-base", type=Path)
    args = parser.parse_args()
    args.profiles_dir = args.profiles_dir or args.root / "profiles"
    args.registry = args.registry or args.root / "protocol-registry.json"
    args.generated_base = args.generated_base or args.root

    errors, counts = check(args)
    print(
        "Skill inventory: "
        f"active={counts['active']} workflow={counts['workflow']} "
        f"profiles={counts['profiles']} registry_tokens={counts['tokens']} fails={len(errors)}"
    )
    if errors:
        for error in errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    print("PASS skill inventory reconciles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
