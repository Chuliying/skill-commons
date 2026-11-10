#!/usr/bin/env python3
"""List and validate work-item metadata without a YAML dependency."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import execution_modes  # noqa: E402  (path set above so the CLI runs from any cwd)
try:
    import activity  # noqa: E402
except ImportError:  # an older or partial install: commands still work, the log is skipped
    activity = None


def _log(item_dir: Path, event: str, result: str = "ok", **extra) -> None:
    if activity is None:
        print("warning: activity.py is missing; activity.jsonl was not written", file=sys.stderr)
        return
    activity.try_append(item_dir, event, result, **extra)


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
# allowed_paths and base_commit (T12): the paths a work item may change, and the commit it
# started from. Both optional; verify.sh --work-item checks the scope when allowed_paths is set.
V3_ALLOWED_FIELDS = V3_REQUIRED_FIELDS | {"delivery_evidence", "documentation_impact", "allowed_paths", "base_commit"}
BASE_COMMIT_RE = re.compile(r"^[0-9a-f]{7,64}$")
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
        if "allowed_paths" in item.fields:
            value = item.fields["allowed_paths"]
            if not [part for part in value.split(",") if part.strip()]:
                errors.append("allowed_paths must be a comma-separated list of paths or globs on one line")
            elif any(ch in value for ch in "#\"'"):
                errors.append("allowed_paths must not contain quotes or a # comment; list paths separated by commas")
        if "base_commit" in item.fields and not BASE_COMMIT_RE.fullmatch(item.fields["base_commit"]):
            errors.append(f"invalid base_commit: {item.fields['base_commit']}")
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
def head_commit(directory: Path) -> str | None:
    """HEAD of the repository holding `directory`, or None (no Git, no commits yet)."""
    try:
        proc = subprocess.run(["git", "-C", str(directory), "rev-parse", "--verify", "-q", "HEAD"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=False)
    except OSError:
        return None
    value = proc.stdout.strip()
    return value if proc.returncode == 0 and BASE_COMMIT_RE.fullmatch(value) else None


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

    Work-history prose is refused: reports, journals, and plans record what happened,
    and treating them as the documentation-impact result would let every item satisfy
    the rule with the artifact it was going to write anyway. The boundary is the work
    root, not the item's own directory -- another item's report is work-history too, so
    the legal result is stated positively: a project document outside the work root.

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
    # Work-history is bounded by the work root, not by this item's directory. Stating
    # the rule as "not mine" let another item's report pass as a project document,
    # which is a plausible thing to record by mistake; the positive form -- a project
    # document outside the work root -- has no such gap.
    item_root = item.path.parent
    work_root = item_root.parent
    work_history_hint = "; name a canonical project document outside the work root"
    # `implement-report.md` names history relative to the item rather than the workspace.
    if (item_root / document).exists():
        errors.append(
            "documentation_impact names work-history under the work root: "
            f"{detail}{work_history_hint}"
        )
        return errors
    # `doc:` is workspace-relative (ARTIFACTS.md), so the result is resolved against the
    # workspace holding the work root at whatever depth `--work-root` puts it.
    workspace = workspace_root(work_root)
    if workspace is None:
        errors.append(
            f"documentation_impact cannot be verified: the work root {work_root} is not "
            "inside a Git working tree, so there is no workspace to resolve "
            f"{detail} against; run the check inside a Git working tree and "
            f"record {DOCUMENTATION_IMPACT_FORMS}"
        )
        return errors
    # The workspace-relative form of any path under the work root. Matching the work
    # root's own prefix keeps a project document that merely sits in a directory sharing
    # a work item's name legal, because that directory is not under the work root.
    try:
        work_root_parts = work_root.resolve().relative_to(workspace).parts
    except ValueError:
        work_root_parts = None
    if work_root_parts and document.parts[: len(work_root_parts)] == work_root_parts:
        errors.append(
            "documentation_impact names work-history under the work root: "
            f"{detail}{work_history_hint}"
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
    # The lexical matches above cannot see a symlink whose target is under the work
    # root, so the resolved target is held to the same rule.
    if resolved.is_relative_to(work_root.resolve()):
        errors.append(
            "documentation_impact resolves to work-history under the work root: "
            f"{detail} resolves to {resolved}{work_history_hint}"
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


def require_work_root(work_root: Path) -> None:
    if not work_root.is_dir():
        raise ValueError(f"work root does not exist: {work_root}")


def metadata_files(work_root: Path) -> list[Path]:
    require_work_root(work_root)
    return sorted(
        child / "meta.yml"
        for child in work_root.iterdir()
        if child.is_dir() and child.name != "_archive" and (child / "meta.yml").is_file()
    )


def load_item(path: Path) -> tuple[WorkItem, list[str]]:
    item, parse_errors = parse_meta(path)
    return item, parse_errors + validate(item)


def load_items(work_root: Path) -> list[tuple[WorkItem, list[str]]]:
    return [load_item(path) for path in metadata_files(work_root)]


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
        if normalized_work_status(item) not in {"active", "queued"}:
            continue
        try:
            updated = parse_timestamp(item.fields["updated_at"])
        except (KeyError, ValueError):
            continue
        age_days = (now - updated.astimezone(timezone.utc)).days
        if age_days > args.days:
            print(render_item(item, str(age_days)))
    return 0


def orphaned_work_items(work_root: Path) -> list[Path]:
    """Folders holding a lifecycle artifact but no meta.yml.

    Each work item has exactly one meta.yml (ARTIFACTS.md). A folder that already
    carries a stage file is a work item the metadata check would otherwise skip;
    folders with only supporting notes are not work items.
    """
    stage_files = {file for _, file in execution_modes.ARTIFACT_STAGES.values()}
    return sorted(
        child
        for child in work_root.iterdir()
        if child.is_dir()
        and child.name != "_archive"
        and not (child / "meta.yml").is_file()
        and any((child / file).is_file() for file in stage_files)
    )


def item_slug(value: str) -> str:
    """`check --item` names one work-item directory under the work root, never a path.

    The value must have the kebab-case slug shape ARTIFACTS.md gives every work item,
    so `..`, `.`, separators, absolute paths and the empty string are refused before
    any path is built and cannot reach outside the work root.
    """
    if not SLUG_RE.fullmatch(value):
        raise argparse.ArgumentTypeError(
            f"{value!r} is not a work-item slug; name one <slug> directory under the "
            "work root (kebab-case, no path separators)"
        )
    return value


class SingleItem(argparse.Action):
    """Refuse a repeated `--item`, which would otherwise keep only the last value."""

    def __call__(self, parser, namespace, values, option_string=None):
        if getattr(namespace, self.dest, None) is not None:
            parser.error(f"{option_string} names one work item; run check once per work item")
        setattr(namespace, self.dest, values)


def command_check(args: argparse.Namespace) -> int:
    work_root = args.work_root
    require_work_root(work_root)
    # The work root holds <slug>/meta.yml. A root holding meta.yml itself is a work item:
    # its children are not work items, so scanning it would pass with nothing checked.
    if os.path.lexists(work_root / "meta.yml"):
        raise ValueError(
            "work root is a work item, not the directory that holds work items: "
            f"{work_root} contains meta.yml; pass its parent as --work-root, or check this "
            f"work item with --work-root {work_root.parent} check --item {work_root.name}"
        )
    if args.item is None:
        items = load_items(work_root)
        missing = [
            (orphan, "lifecycle artifact present but meta.yml is missing")
            for orphan in orphaned_work_items(work_root)
        ]
    else:
        # Scoped to the named work item: sibling folders, orphans included, are the
        # whole-root check's concern. The named item itself must have its meta.yml.
        meta = work_root / args.item / "meta.yml"
        if meta.is_file():
            items, missing = [load_item(meta)], []
        else:
            items, missing = [], [(meta, "work item metadata is missing")]
    failures = 0
    for path, reason in missing:
        failures += 1
        print(f"FAIL {path}: {reason}")
    for item, errors in items:
        if not errors:
            print(f"PASS {item.path}")
            continue
        failures += 1
        for error in errors:
            print(f"FAIL {item.path}: {error}")
    if failures:
        print(f"work-item check failed: {failures}/{len(items) + len(missing)} invalid")
        return 1
    print(f"work-item check passed: {len(items)} valid")
    return 0


def prd_skeleton(template: str, title: str, tier: str = "core") -> str:
    """A PRD skeleton from prd-template.md. Placeholders stay, so check-prd.py fails until
    they are filled. For the core tier, a `<!-- tier: team -->` marker removes only the
    block it marks: up to the next heading, the next `**Label**:` line or `---`."""
    lines = template.splitlines()
    first = next((i for i, line in enumerate(lines) if line.startswith("# ")), -1)
    if tier == "team":
        return "\n".join([f"# {title}", *lines[first + 1:]]).rstrip() + "\n"
    out: list[str] = [f"# {title}", ""]
    section: list[str] = []
    keep_section = False
    skipping = False
    started = False

    def flush() -> None:
        while section and not section[-1].strip():
            section.pop()
        if section and keep_section:
            out.extend([*section, ""])

    for line in lines:
        if line.startswith("## "):
            flush()
            section, keep_section, skipping, started = [line], False, False, True
            continue
        if not started:
            continue
        marker = re.match(r"^<!-- tier: (core|team) -->$", line.strip())
        if marker:
            if marker.group(1) == "core":
                keep_section, skipping = True, False
                continue
            skipping = True
            # The heading or label that introduces a team-only block goes with it.
            while section and not section[-1].strip():
                section.pop()
            if section and (section[-1].startswith("### ") or re.fullmatch(r"\*\*[^*]+\*\*:\s*", section[-1])):
                section.pop()
            continue
        if skipping and (line.startswith("#") or line.startswith("**") or line.strip() == "---"):
            skipping = False
        if skipping:
            continue
        if section and section[0].startswith("## ") and "Gate 1" in section[0] and "NFR" in line:
            continue  # The core tier has no NFR section.
        section.append(line)
    flush()
    return "\n".join(out).rstrip() + "\n"


def _producer(mode: dict, artifact: str, roster: set[str]) -> str | None:
    for skill in mode["artifacts"][artifact]["producers"]:
        if not roster or skill in roster:
            return skill
    return None


def command_new(args: argparse.Namespace) -> int:
    """Create a valid work item: meta.yml, a PRD skeleton when the mode has a PRD and a PRD
    skill is installed, and an implement-report stub. Other required stages are listed, not
    stubbed: their skills write them, and an empty plan would fail the plan check."""
    work_root = args.work_root
    work_root.mkdir(parents=True, exist_ok=True)
    item_root = work_root / args.slug
    if os.path.lexists(item_root):
        raise ValueError(f"work item already exists: {item_root}")
    mode = PROTOCOL_REGISTRY["execution_modes"][args.mode]
    roster = skill_roster()
    template = REPO_ROOT / "prd-template.md"
    prd_requirement = mode["artifacts"]["prd"]["requirement"]
    prd_skill = _producer(mode, "prd", roster)
    tier = "team" if args.mode == "team-feature" else "core"
    warnings: list[str] = []
    wants_prd = not args.no_prd and prd_requirement in {"required", "optional"}
    if wants_prd and (prd_skill is None or not template.is_file()):
        wants_prd = False
        if prd_requirement == "required":
            warnings.append(f"{args.mode} requires a PRD, but no PRD skill or template is installed")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    title = args.title or args.slug.replace("-", " ").capitalize()
    stages: list[str] = []
    files: dict[str, str] = {}
    if wants_prd:
        stages.append(f"  prd: {{ skill: {prd_skill}, file: prd.md, status: in_progress }}")
        files["prd.md"] = prd_skeleton(template.read_text(encoding="utf-8"), title, tier)
    stages.append("  implement: { skill: implement, file: implement-report.md, status: pending }")
    files["implement-report.md"] = f"# Implement report: {title}\n\n<!-- The implement skill fills this in. -->\n"
    inputs = args.input or ["user:request"]
    meta = "\n".join([
        "schema_version: work-item/v3",
        f"slug: {args.slug}",
        f"title: {title}",
        f"created_at: {now}",
        f"updated_at: {now}",
        f"execution_mode: {args.mode}",
        f"work_status: {'queued' if args.queued else 'active'}",
        "delivery_status: not_requested",
        *([f"base_commit: {base}"] if (base := head_commit(work_root)) else []),
        "stages:",
        *stages,
        "inputs:",
        *[f"  - {value}" for value in inputs],
        "",
    ])
    item_root.mkdir()
    try:
        for name, text in files.items():
            (item_root / name).write_text(text, encoding="utf-8")
        (item_root / "meta.yml").write_text(meta, encoding="utf-8")
        _item, errors = load_item(item_root / "meta.yml")
        if errors:
            raise ValueError("generated work item is invalid: " + "; ".join(errors))
    except BaseException:
        shutil.rmtree(item_root, ignore_errors=True)
        raise
    _log(item_root, "new", mode=args.mode, work_status="queued" if args.queued else "active")
    relative = os.path.relpath(item_root)
    scripts = os.path.relpath(REPO_ROOT / "scripts")
    print(f"created {relative}/ ({args.mode}{', queued' if args.queued else ''}): {', '.join(['meta.yml', *files])}")
    if args.queued:
        print(f"queued: start it with bash {os.path.relpath(REPO_ROOT / 'scripts')}/work-items.sh start {args.slug}")
    for warning in warnings:
        print(f"warning: {warning}")
    if wants_prd:
        print(f"next: fill {relative}/prd.md, then run python3 {scripts}/check-prd.py --prd {relative}/prd.md --tier {tier}")
    later = [
        f"{execution_modes.stage_name(artifact)} ({' or '.join(mode['artifacts'][artifact]['producers'])})"
        for artifact in sorted(mode["artifacts"])
        if mode["artifacts"][artifact]["requirement"] == "required"
        and artifact not in {"implement-report"} and not (artifact == "prd" and wants_prd)
    ]
    if later:
        print(f"before completion this mode also needs: {', '.join(later)}")
    if not args.input:
        print("inputs: replace user:request in meta.yml with what started this work, or pass --input")
    print(f"when done: bash {scripts}/work-items.sh complete {args.slug} --na \"<reason>\" (or --doc <path>), then verify")
    return 0


def command_start(args: argparse.Namespace) -> int:
    """queued -> active. Refuses any other status and leaves meta.yml unchanged on failure."""
    meta_path = args.work_root / args.slug / "meta.yml"
    if not meta_path.is_file():
        raise ValueError(f"work item metadata is missing: {meta_path}")
    item, _errors = parse_meta(meta_path)
    status = item.fields.get("work_status", "")
    if status != "queued":
        raise ValueError(f"start needs a queued work item; {args.slug} is {status or 'without work_status'}")
    original = meta_path.read_text(encoding="utf-8")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = []
    base = head_commit(meta_path.parent)
    for line in original.splitlines():
        if line.startswith("work_status:"):
            line = "work_status: active"
        elif line.startswith("updated_at:"):
            line = f"updated_at: {now}"
        elif line.startswith("base_commit:"):
            continue  # a queued item's scope starts when it starts (T12)
        lines.append(line)
        if line == "delivery_status: not_requested" and base:
            lines.append(f"base_commit: {base}")
    if base and not any(line.startswith("base_commit:") for line in lines):
        lines.append(f"base_commit: {base}")
    meta_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    _item, errors = load_item(meta_path)
    if errors:
        meta_path.write_text(original, encoding="utf-8")
        for error in errors:
            print(f"FAIL {meta_path}: {error}")
        print("start refused; meta.yml is unchanged")
        return 1
    _log(meta_path.parent, "start")
    print(f"started {os.path.relpath(meta_path.parent)}: work_status active")
    return 0


def command_complete(args: argparse.Namespace) -> int:
    """Close out a work item: unfinished stages become done, work_status completed,
    updated_at now, one documentation_impact. Refuses and leaves meta.yml unchanged when
    the result does not pass check."""
    meta_path = args.work_root / args.slug / "meta.yml"
    if not meta_path.is_file():
        raise ValueError(f"work item metadata is missing: {meta_path}")
    if bool(args.doc) == bool(args.na):
        raise ValueError("complete needs exactly one of --doc <project document> or --na <reason>")
    impact = f"doc:{args.doc}" if args.doc else f"n/a:{args.na}"
    original = meta_path.read_text(encoding="utf-8")
    item, parse_errors = parse_meta(meta_path)
    status = item.fields.get("work_status", "")
    if status == "completed":
        print(f"{os.path.relpath(meta_path.parent)} is already completed; nothing changed")
        return 0
    if status != "active":
        raise ValueError(f"complete needs an active work item; {args.slug} is {status or 'without work_status'}"
                         + ("; run work-items.sh start first" if status == "queued" else ""))
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = []
    has_impact = False
    for line in original.splitlines():
        if line.startswith("work_status:"):
            line = "work_status: completed"
        elif line.startswith("updated_at:"):
            line = f"updated_at: {now}"
        elif line.startswith("documentation_impact:"):
            line, has_impact = f"documentation_impact: {impact}", True
        else:
            line = re.sub(r"(status:\s*)(pending|ready|in_progress)(\s*})", r"\1done\3", line)
        lines.append(line)
    if not has_impact:
        at = next((i for i, line in enumerate(lines) if line.startswith(("delivery_status:", "work_status:"))), None)
        if at is None:
            raise ValueError(f"meta.yml has no work_status or delivery_status line: {meta_path}")
        lines.insert(at + 1, f"documentation_impact: {impact}")
    meta_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    _item, errors = load_item(meta_path)
    if errors:
        meta_path.write_text(original, encoding="utf-8")
        for error in errors:
            print(f"FAIL {meta_path}: {error}")
        print("complete refused; meta.yml is unchanged")
        return 1
    _log(meta_path.parent, "complete", documentation_impact=impact)
    print(f"completed {os.path.relpath(meta_path.parent)}: work_status completed, documentation_impact {impact}")
    print(f"next: bash verify.sh --work-item {args.slug} records evidence for the finished state")
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
    check_parser.add_argument(
        "--item",
        action=SingleItem,
        type=item_slug,
        metavar="SLUG",
        help="check only the work item <work-root>/SLUG/meta.yml",
    )
    check_parser.set_defaults(handler=command_check)

    new_parser = subparsers.add_parser("new", help="create a valid work item skeleton")
    new_parser.add_argument("slug", type=item_slug)
    new_parser.add_argument("--mode", choices=sorted(EXECUTION_MODES), default="personal-feature")
    new_parser.add_argument("--title")
    new_parser.add_argument("--no-prd", action="store_true", help="skip the PRD skeleton")
    new_parser.add_argument("--input", action="append", help="what started this work (typed reference or path); repeatable")
    new_parser.add_argument("--queued", action="store_true", help="add to the backlog without starting it")
    new_parser.set_defaults(handler=command_new)

    start_parser = subparsers.add_parser("start", help="move a queued work item to active")
    start_parser.add_argument("slug", type=item_slug)
    start_parser.set_defaults(handler=command_start)

    complete_parser = subparsers.add_parser("complete", help="close out a work item and check it")
    complete_parser.add_argument("slug", type=item_slug)
    complete_parser.add_argument("--doc", help="the project document this work updated")
    complete_parser.add_argument("--na", help="why no project document changed (one line)")
    complete_parser.set_defaults(handler=command_complete)
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
