#!/usr/bin/env python3
"""List and validate work-item metadata without a YAML dependency."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import execution_modes  # noqa: E402  (path set above so the CLI runs from any cwd)


LEGACY_WORK_ITEM_STATUSES = {"active", "shipped", "abandoned"}


# ADR-R3 I-M1: the registry is reached through the shared accessor so this module and
# grade_journey.py cannot hold divergent copies of the same stage contract.
PROTOCOL_REGISTRY = execution_modes.REGISTRY
WORK_ITEM_CONTRACT = PROTOCOL_REGISTRY["work_item"]
WORK_STATUSES = set(WORK_ITEM_CONTRACT["work_statuses"])
DELIVERY_RULES = WORK_ITEM_CONTRACT["delivery_statuses"]
DELIVERY_STATUSES = set(DELIVERY_RULES)
EXECUTION_MODES = set(PROTOCOL_REGISTRY["execution_modes"])
STAGE_STATUSES = {
    "pending",
    "ready",
    "in_progress",
    "awaiting-approval",
    "approved",
    "blocked",
    "done",
    "validated",
    "skipped",
    "superseded",
}
INCOMPLETE_STAGE_STATUSES = {"pending", "ready", "in_progress", "blocked"}
UNSUCCESSFUL_REQUIRED_STAGE_STATUSES = {"skipped", "superseded"}
ARTIFACT_STAGES = execution_modes.ARTIFACT_STAGES
LEGACY_REQUIRED_FIELDS = {
    "slug",
    "title",
    "created_at",
    "updated_at",
    "status",
    "stages",
    "inputs",
}
V3_REQUIRED_FIELDS = {
    "schema_version",
    "slug",
    "title",
    "created_at",
    "updated_at",
    "execution_mode",
    "work_status",
    "delivery_status",
    "stages",
    "inputs",
}
CONTAINER_FIELDS = {"stages", "inputs", "delivery_evidence"}
LEGACY_ALLOWED_FIELDS = LEGACY_REQUIRED_FIELDS | {"schema_version"}
V3_ALLOWED_FIELDS = V3_REQUIRED_FIELDS | {"delivery_evidence", "documentation_impact"}
DOCUMENTATION_IMPACT_FORMS = "doc:<project-document> or n/a:<bounded reason>"
DOCUMENTATION_IMPACT_MAX_REASON = 200
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
STAGE_RE = re.compile(r"^  ([a-z0-9]+(?:-[a-z0-9]+)*):\s*\{(.*)\}\s*$")
OPAQUE_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/#@+\-]{2,}$")
DEPLOYMENT_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/\-]{5,}$")
# The date v3 became mandatory IN THIS REPOSITORY. It was 2026-07-10 in the release
# lineage, but dev main forked before v3 existed and kept creating items on the legacy
# schema until the two lines were reconciled on 2026-07-25. Items authored in a lineage
# that had no v3 could not have declared it, so holding them to 07-10 would report a
# defect that was never possible to avoid -- and the fix would be to backfill a
# schema_version onto metadata that was not written against that contract.
#
# Forward-only, as ARTIFACTS.md's adoption stance requires: every item created from the
# reconciliation onward must declare work-item/v3, and pre-reconciliation items stay
# valid under the legacy schema (which is still fully validated) until each is migrated
# on purpose. Migration is real work, not a field rename: those items carry three-file
# plans that canonical-v2 replaced, so it converts planning documents, not metadata.
V3_ADOPTION_TIME = datetime.fromisoformat("2026-07-25T00:00:00+08:00")
# The date the documentation-impact rule became mandatory. Same forward-only stance as
# above and as ARTIFACTS.md's adoption section: a shape gate applies to work edited from
# its adoption onward, never retroactively, because a repository-wide sweep is a
# deliberate migration rather than a default check. The trigger is updated_at, not
# created_at, so work that was already open when the rule landed still has to record a
# documentation-impact result at the moment it is completed.
D3_ADOPTION_TIME = datetime.fromisoformat("2026-07-27T00:00:00+08:00")
REPO_ROOT = Path(__file__).resolve().parent.parent


def skill_roster(repo_root: Path = REPO_ROOT) -> set[str]:
    """Top-level skill folders, which are the only valid owners of a stage.

    Derived from the tree rather than a hand-kept list so the roster cannot rot.
    An empty roster disables the check instead of failing every stage, so a
    checkout without skill folders stays usable.
    """
    if not repo_root.is_dir():
        return set()
    return {
        child.name
        for child in repo_root.iterdir()
        if child.is_dir()
        and not child.name.startswith((".", "_"))
        and (child / "SKILL.md").is_file()
    }


@dataclass
class Stage:
    name: str
    skill: str
    file: str
    status: str


@dataclass
class WorkItem:
    path: Path
    fields: dict[str, str]
    stages: list[Stage]
    inputs: list[str]
    delivery_evidence: dict[str, str]


def clean_value(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def parse_inline_map(
    payload: str, allowed_fields: set[str]
) -> tuple[dict[str, str], list[str]]:
    fields: dict[str, str] = {}
    errors: list[str] = []
    for chunk in payload.split(","):
        if ":" not in chunk:
            errors.append(f"malformed stage field: {chunk.strip() or '<empty>'}")
            continue
        key, value = chunk.split(":", 1)
        key = key.strip()
        value = clean_value(value)
        if not key or not value:
            errors.append(f"malformed stage field: {chunk.strip() or '<empty>'}")
            continue
        if key in fields:
            errors.append(f"duplicate stage field: {key}")
            continue
        if key not in allowed_fields:
            errors.append(f"unknown stage field: {key}")
            continue
        fields[key] = value
    return fields, errors


def parse_meta(path: Path) -> tuple[WorkItem, list[str]]:
    fields: dict[str, str] = {}
    stages: list[Stage] = []
    inputs: list[str] = []
    delivery_evidence: dict[str, str] = {}
    errors: list[str] = []
    section = ""

    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw.startswith((" ", "\t")) and ":" in raw:
            key, value = raw.split(":", 1)
            key = key.strip()
            if key in fields:
                errors.append(f"line {line_number}: duplicate field: {key}")
            if key in CONTAINER_FIELDS and value.strip():
                errors.append(
                    f"line {line_number}: container field {key} must not have a scalar value"
                )
            fields[key] = clean_value(value)
            section = key if key in CONTAINER_FIELDS else ""
            continue
        if section == "stages":
            match = STAGE_RE.match(raw)
            if not match:
                errors.append(f"line {line_number}: stage must use inline mapping syntax")
                continue
            stage_fields, stage_errors = parse_inline_map(
                match.group(2), {"skill", "file", "status"}
            )
            errors.extend(f"line {line_number}: {error}" for error in stage_errors)
            missing = sorted({"skill", "file", "status"} - set(stage_fields))
            if missing:
                errors.append(
                    f"line {line_number}: stage {match.group(1)} missing fields: {', '.join(missing)}"
                )
                continue
            stages.append(
                Stage(
                    name=match.group(1),
                    skill=stage_fields["skill"],
                    file=stage_fields["file"],
                    status=stage_fields["status"],
                )
            )
        elif section == "inputs" and raw.startswith("  - "):
            inputs.append(clean_value(raw[4:]))
        elif section == "delivery_evidence" and raw.startswith("  ") and ":" in raw:
            key, value = raw.strip().split(":", 1)
            if key in delivery_evidence:
                errors.append(f"line {line_number}: duplicate delivery evidence: {key}")
            delivery_evidence[key] = clean_value(value)
        else:
            errors.append(f"line {line_number}: unsupported metadata syntax")

    return WorkItem(
        path=path,
        fields=fields,
        stages=stages,
        inputs=inputs,
        delivery_evidence=delivery_evidence,
    ), errors


def parse_timestamp(value: str) -> datetime:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def validate(item: WorkItem) -> list[str]:
    errors: list[str] = []
    schema_version = item.fields.get("schema_version", "legacy-v1")
    if schema_version not in {"legacy-v1", "work-item/v3"}:
        errors.append(f"unsupported schema_version: {schema_version}")
    required = V3_REQUIRED_FIELDS if schema_version == "work-item/v3" else LEGACY_REQUIRED_FIELDS
    allowed = V3_ALLOWED_FIELDS if schema_version == "work-item/v3" else LEGACY_ALLOWED_FIELDS
    known_but_forbidden = {"status"} if schema_version == "work-item/v3" else set()
    missing = sorted(key for key in required if key not in item.fields)
    errors.extend(f"missing required field: {key}" for key in missing)
    unknown = sorted(set(item.fields) - allowed - known_but_forbidden)
    errors.extend(f"unknown top-level field: {key}" for key in unknown)

    slug = item.fields.get("slug", "")
    if slug and not SLUG_RE.fullmatch(slug):
        errors.append(f"invalid slug: {slug}")
    if slug and slug != item.path.parent.name:
        errors.append(f"slug does not match directory: {slug} != {item.path.parent.name}")
    if not item.fields.get("title", "").strip() and "title" not in missing:
        errors.append("title must not be empty")

    if schema_version == "work-item/v3":
        if "status" in item.fields:
            errors.append("work-item/v3 must use work_status and delivery_status, not status")
        work_status = item.fields.get("work_status", "")
        delivery_status = item.fields.get("delivery_status", "")
        execution_mode = item.fields.get("execution_mode", "")
        if work_status and work_status not in WORK_STATUSES:
            errors.append(f"invalid work status: {work_status}")
        if delivery_status and delivery_status not in DELIVERY_STATUSES:
            errors.append(f"invalid delivery status: {delivery_status}")
        if execution_mode and execution_mode not in EXECUTION_MODES:
            errors.append(f"invalid execution mode: {execution_mode}")
        errors.extend(validate_delivery(item, work_status, delivery_status))
    else:
        status = item.fields.get("status", "")
        if status and status not in LEGACY_WORK_ITEM_STATUSES:
            errors.append(f"invalid work-item status: {status}")

    timestamps: dict[str, datetime] = {}
    for key in ("created_at", "updated_at"):
        value = item.fields.get(key)
        if not value:
            continue
        try:
            timestamps[key] = parse_timestamp(value)
        except ValueError:
            errors.append(f"invalid {key} timestamp: {value}")
    if set(timestamps) == {"created_at", "updated_at"}:
        if timestamps["updated_at"] < timestamps["created_at"]:
            errors.append("updated_at precedes created_at")
    if (
        schema_version == "legacy-v1"
        and timestamps.get("created_at", datetime.min.replace(tzinfo=timezone.utc))
        >= V3_ADOPTION_TIME
    ):
        errors.append("metadata created after work-item/v3 adoption must declare schema_version")
    if schema_version == "work-item/v3":
        errors.extend(
            validate_documentation_impact(
                item, item.fields.get("work_status", ""), timestamps
            )
        )

    if "stages" in item.fields and not item.stages:
        errors.append("stages must contain at least one stage")
    seen_stages: set[str] = set()
    item_root = item.path.parent.resolve()
    roster = skill_roster()
    for stage in item.stages:
        if stage.name in seen_stages:
            errors.append(f"duplicate stage: {stage.name}")
        seen_stages.add(stage.name)
        if not stage.skill:
            errors.append(f"stage {stage.name} has empty skill")
        elif roster and stage.skill not in roster:
            errors.append(f"stage {stage.name} names an unknown skill: {stage.skill}")
        if stage.status not in STAGE_STATUSES:
            errors.append(f"invalid stage status for {stage.name}: {stage.status}")
        artifact = Path(stage.file)
        if artifact.is_absolute() or ".." in artifact.parts:
            errors.append(f"stage {stage.name} file escapes work item: {stage.file}")
            continue
        resolved = (item_root / artifact).resolve()
        if not resolved.is_relative_to(item_root):
            errors.append(f"stage {stage.name} file escapes work item: {stage.file}")
        elif not resolved.is_file():
            errors.append(f"stage {stage.name} artifact does not exist: {stage.file}")

    if schema_version == "work-item/v3":
        errors.extend(validate_execution_artifacts(item, execution_mode, work_status))

    if "inputs" in item.fields and not item.inputs:
        errors.append("inputs must contain at least one entry")
    return errors


def validate_execution_artifacts(
    item: WorkItem, execution_mode: str, work_status: str
) -> list[str]:
    """Check a v3 work item's stages against its declarative mode contract."""

    errors: list[str] = []
    mode = PROTOCOL_REGISTRY["execution_modes"].get(execution_mode)
    if not isinstance(mode, dict):
        return errors
    stages = {stage.name: stage for stage in item.stages}
    for artifact_name, record in mode["artifacts"].items():
        stage_name, canonical_file = ARTIFACT_STAGES[artifact_name]
        stage = stages.get(stage_name)
        requirement = record["requirement"]
        if requirement == "required" and work_status == "completed" and stage is None:
            errors.append(f"{execution_mode} completed work requires stage: {stage_name}")
            continue
        if requirement == "absent" and stage is not None:
            errors.append(f"{execution_mode} forbids stage: {stage_name}")
            continue
        if stage is None:
            continue
        if stage.file != canonical_file:
            errors.append(
                f"stage {stage_name} must use canonical artifact: {canonical_file}"
            )
        if stage.skill not in record["producers"]:
            errors.append(
                f"stage {stage_name} skill {stage.skill} is not a producer for {artifact_name}"
            )
        if (
            requirement == "required"
            and work_status == "completed"
            and stage.status in UNSUCCESSFUL_REQUIRED_STAGE_STATUSES
        ):
            errors.append(f"required stage {stage_name} must not be {stage.status}")

    if work_status == "completed":
        for stage in item.stages:
            if stage.status in INCOMPLETE_STAGE_STATUSES:
                errors.append(
                    f"completed work item stage {stage.name} must not remain {stage.status}"
                )
    return errors


@lru_cache(maxsize=None)
def _git_toplevel(directory: str) -> str:
    """The Git working-tree top level containing `directory`, or "" if there is none.

    Cached on the directory because every item under one work root shares the same
    answer, so a repository-wide check spawns one `git` process, not one per item.
    """
    try:
        proc = subprocess.run(
            ["git", "-C", directory, "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        return ""
    return proc.stdout.strip() if proc.returncode == 0 else ""


def workspace_root(work_root: Path) -> Path | None:
    """The workspace a `doc:` result is resolved against, or None if there is none.

    `<workspace>/docs/work` is only ARTIFACTS.md's default layout and `--work-root` is
    a public option, so the workspace cannot be a fixed number of levels above the work
    root: `.work/` at the workspace top level would anchor two directories too high.
    The Git working tree holding the work root is the workspace anchor the rest of the
    repository already uses (scripts/export-public.sh, the journey grader), and it holds
    at any depth. Returning None where there is no working tree lets the caller fail
    closed instead of guessing a base directory.
    """
    top = _git_toplevel(str(work_root))
    return Path(top).resolve() if top else None


def validate_documentation_impact(
    item: WorkItem, work_status: str, timestamps: dict[str, datetime]
) -> list[str]:
    """Check the single documentation-impact result a completed work item carries.

    Exactly one result, in exactly two legal forms: a named project document, or a
    bounded N/A reason. The field is a scalar, so "exactly one" needs no counting -- a
    second line is already rejected as a duplicate field.

    A path inside the work item is refused: reports, journals, and plans record what
    happened, and treating them as the documentation-impact result would let every item
    satisfy the rule with the artifact it was going to write anyway.

    A named document must also exist, because a path that resolves to nothing proves no
    document was updated. Existence is the whole bound: content is never inspected and
    no hash is taken, since a hash proves an artifact's identity, never its semantics.
    This stays a shape, location, and existence check; it never proves the named
    document was actually updated.
    """

    errors: list[str] = []
    value = item.fields.get("documentation_impact", "").strip()
    if not value:
        updated = timestamps.get("updated_at", datetime.min.replace(tzinfo=timezone.utc))
        if work_status == "completed" and updated >= D3_ADOPTION_TIME:
            errors.append(
                "completed work requires exactly one documentation_impact result: "
                f"record {DOCUMENTATION_IMPACT_FORMS}"
            )
        return errors

    kind, separator, detail = value.partition(":")
    kind = kind.strip()
    detail = detail.strip()
    if not separator or kind not in {"doc", "n/a"}:
        errors.append(
            f"invalid documentation_impact: {value}; use {DOCUMENTATION_IMPACT_FORMS}"
        )
        return errors

    if kind == "n/a":
        if not detail:
            errors.append(
                f"documentation_impact n/a needs a bounded reason; use {DOCUMENTATION_IMPACT_FORMS}"
            )
        elif len(detail) > DOCUMENTATION_IMPACT_MAX_REASON:
            errors.append(
                "documentation_impact n/a reason must be at most "
                f"{DOCUMENTATION_IMPACT_MAX_REASON} characters"
            )
        return errors

    if not detail:
        errors.append(
            f"documentation_impact doc needs a document; use {DOCUMENTATION_IMPACT_FORMS}"
        )
        return errors
    document = Path(detail)
    if document.is_absolute() or ".." in document.parts:
        errors.append(
            f"documentation_impact doc must be a workspace-relative path: {detail}"
        )
        return errors
    # Two ways to name the work item's own history: relative to the item
    # (`implement-report.md`) or from the workspace (`docs/work/<slug>/plan/plan.md`).
    # The workspace form is matched on the adjacent pair <work-root>/<slug> rather than
    # on the slug alone, so a project document that merely sits in a directory sharing
    # the item's name stays a legal result.
    item_root = item.path.parent
    location = (item_root.parent.name, item_root.name)
    parts = document.parts
    inside_work_item = any(parts[index : index + 2] == location for index in range(len(parts)))
    if (item_root / document).exists() or inside_work_item:
        errors.append(
            f"documentation_impact names work-history inside the work item: {detail}; "
            "name a canonical project document outside it"
        )
        return errors
    # `doc:` is workspace-relative (ARTIFACTS.md), so the result is resolved against the
    # workspace holding the work root at whatever depth `--work-root` puts it.
    work_root = item_root.parent
    workspace = workspace_root(work_root)
    if workspace is None:
        errors.append(
            f"documentation_impact cannot be verified: the work root {work_root} is not "
            "inside a Git working tree, so there is no workspace to resolve "
            f"{detail} against; run the check inside a Git working tree and "
            f"record {DOCUMENTATION_IMPACT_FORMS}"
        )
        return errors
    # The resolved target has to stay in the workspace, not just be reachable from it: a
    # symlink inside the workspace pointing outside it is a path the project does not
    # own, so following it would accept a document the project never updated.
    resolved = (workspace / document).resolve()
    if not resolved.is_relative_to(workspace):
        errors.append(
            f"documentation_impact names a document outside the workspace: {detail} "
            f"resolves to {resolved}, outside {workspace}"
            "; name a project document inside the workspace and "
            f"record {DOCUMENTATION_IMPACT_FORMS}"
        )
        return errors
    # The lexical work-history match above cannot see a symlink whose target is the
    # work item itself, so the resolved target is held to the same rule.
    if resolved.is_relative_to(item_root.resolve()):
        errors.append(
            f"documentation_impact resolves to work-history inside the work item: "
            f"{detail} resolves to {resolved}; name a canonical project document "
            "outside it"
        )
        return errors
    if not resolved.is_file():
        errors.append(
            f"documentation_impact names a document that does not exist: {detail}; "
            f"record {DOCUMENTATION_IMPACT_FORMS}"
        )
    return errors


def validate_delivery(item: WorkItem, work_status: str, delivery_status: str) -> list[str]:
    errors: list[str] = []
    evidence = item.delivery_evidence
    globally_allowed_evidence = {
        key
        for rule in DELIVERY_RULES.values()
        for key in rule["allowed_evidence"]
    }
    for key in sorted(set(evidence) - globally_allowed_evidence):
        errors.append(f"unsupported delivery evidence: {key}")

    rule = DELIVERY_RULES.get(delivery_status, {})
    required_evidence = rule.get("required_evidence", [])
    allowed_evidence = set(rule.get("allowed_evidence", []))
    for key in required_evidence:
        if not evidence.get(key, "").strip():
            errors.append(f"{delivery_status} requires delivery evidence: {key}")

    if delivery_status and not required_evidence and evidence:
        errors.append(f"{delivery_status} must not carry delivery evidence")
    elif delivery_status:
        for key in sorted((set(evidence) & globally_allowed_evidence) - allowed_evidence):
            errors.append(f"{delivery_status} does not allow delivery evidence: {key}")
    allowed_work_statuses = set(rule.get("allowed_work_statuses", []))
    if delivery_status and work_status and work_status not in allowed_work_statuses:
        if allowed_work_statuses == {"completed"}:
            errors.append(f"delivery status {delivery_status} requires work_status completed")
        else:
            errors.append(f"delivery status {delivery_status} does not allow work_status {work_status}")
    if work_status == "abandoned" and delivery_status and delivery_status != "not_requested":
        errors.append("abandoned work requires delivery_status not_requested")

    pr_url = evidence.get("pr_url", "")
    if pr_url and not re.fullmatch(r"https://[^\s]+", pr_url):
        errors.append(f"invalid delivery evidence pr_url: {pr_url}")
    merge_sha = evidence.get("merge_sha", "")
    if merge_sha and not re.fullmatch(r"[0-9a-f]{40}", merge_sha):
        errors.append(f"invalid delivery evidence merge_sha: {merge_sha}")
    approval_ref = evidence.get("approval_ref", "")
    if approval_ref:
        reference_type, separator, value = approval_ref.partition(":")
        valid_typed_ref = bool(
            separator
            and reference_type in {"user", "local", "external"}
            and (
                OPAQUE_REF_RE.fullmatch(value)
                or (reference_type == "external" and re.fullmatch(r"https://[^\s]+", value))
            )
        )
        if not valid_typed_ref:
            errors.append(f"invalid delivery evidence approval_ref: {approval_ref}")
    deployment_id = evidence.get("deployment_id", "")
    if deployment_id and not DEPLOYMENT_ID_RE.fullmatch(deployment_id):
        errors.append(f"invalid delivery evidence deployment_id: {deployment_id}")
    return errors


def normalized_work_status(item: WorkItem) -> str:
    if item.fields.get("schema_version") == "work-item/v3":
        return item.fields.get("work_status", "<invalid>")
    legacy = item.fields.get("status", "<invalid>")
    return "completed" if legacy == "shipped" else legacy


def normalized_delivery_status(item: WorkItem) -> str:
    if item.fields.get("schema_version") == "work-item/v3":
        return item.fields.get("delivery_status", "<invalid>")
    return "legacy_shipped" if item.fields.get("status") == "shipped" else "legacy_unrecorded"


def metadata_files(work_root: Path) -> list[Path]:
    if not work_root.is_dir():
        raise ValueError(f"work root does not exist: {work_root}")
    return sorted(
        child / "meta.yml"
        for child in work_root.iterdir()
        if child.is_dir() and child.name != "_archive" and (child / "meta.yml").is_file()
    )


def load_items(work_root: Path) -> list[tuple[WorkItem, list[str]]]:
    loaded = []
    for path in metadata_files(work_root):
        item, parse_errors = parse_meta(path)
        loaded.append((item, parse_errors + validate(item)))
    return loaded


def render_item(item: WorkItem, extra: str = "") -> str:
    fields = item.fields
    columns = [
        normalized_work_status(item),
        normalized_delivery_status(item),
        fields.get("updated_at", "<missing>"),
        fields.get("slug", item.path.parent.name),
        fields.get("title", "<missing>"),
        str(item.path),
    ]
    if extra:
        columns.append(extra)
    return "\t".join(columns)


def command_list(args: argparse.Namespace) -> int:
    allowed_filters = WORK_STATUSES | LEGACY_WORK_ITEM_STATUSES
    if args.status and args.status not in allowed_filters:
        print(f"invalid status filter: {args.status}", file=sys.stderr)
        return 2
    print("work_status\tdelivery_status\tupdated_at\tslug\ttitle\tmeta")
    items = sorted(load_items(args.work_root), key=lambda pair: render_item(pair[0]))
    for item, _ in items:
        expected = "completed" if args.status == "shipped" else args.status
        if expected and normalized_work_status(item) != expected:
            continue
        print(render_item(item))
    return 0


def command_stale(args: argparse.Namespace) -> int:
    now = parse_timestamp(args.now) if args.now else datetime.now(timezone.utc)
    print("work_status\tdelivery_status\tupdated_at\tslug\ttitle\tmeta\tage_days")
    for item, _ in load_items(args.work_root):
        if normalized_work_status(item) != "active":
            continue
        try:
            updated = parse_timestamp(item.fields["updated_at"])
        except (KeyError, ValueError):
            continue
        age_days = (now - updated.astimezone(timezone.utc)).days
        if age_days > args.days:
            print(render_item(item, str(age_days)))
    return 0


def command_check(args: argparse.Namespace) -> int:
    failures = 0
    items = load_items(args.work_root)
    for item, errors in items:
        if not errors:
            print(f"PASS {item.path}")
            continue
        failures += 1
        for error in errors:
            print(f"FAIL {item.path}: {error}")
    if failures:
        print(f"work-item check failed: {failures}/{len(items)} invalid")
        return 1
    print(f"work-item check passed: {len(items)} valid")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--work-root",
        type=Path,
        default=Path("docs/work"),
        help="directory containing one subdirectory per work item",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="list work items grouped by status")
    list_parser.add_argument("--status")
    list_parser.set_defaults(handler=command_list)

    stale_parser = subparsers.add_parser("stale", help="list old active work items")
    stale_parser.add_argument("--days", type=int, default=30)
    stale_parser.add_argument("--now", help=argparse.SUPPRESS)
    stale_parser.set_defaults(handler=command_stale)

    check_parser = subparsers.add_parser("check", help="validate metadata and artifact paths")
    check_parser.set_defaults(handler=command_check)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "days", 0) < 0:
        parser.error("--days must be zero or greater")
    args.work_root = args.work_root.expanduser().resolve()
    try:
        return args.handler(args)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
