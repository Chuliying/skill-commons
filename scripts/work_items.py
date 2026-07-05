#!/usr/bin/env python3
"""List and validate work-item metadata without a YAML dependency."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


WORK_ITEM_STATUSES = {"active", "shipped", "abandoned"}
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
REQUIRED_FIELDS = {"slug", "title", "created_at", "updated_at", "status", "stages", "inputs"}
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
STAGE_RE = re.compile(r"^  ([a-z0-9]+(?:-[a-z0-9]+)*):\s*\{(.*)\}\s*$")


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


def clean_value(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def parse_inline_map(payload: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for chunk in payload.split(","):
        if ":" not in chunk:
            continue
        key, value = chunk.split(":", 1)
        fields[key.strip()] = clean_value(value)
    return fields


def parse_meta(path: Path) -> tuple[WorkItem, list[str]]:
    fields: dict[str, str] = {}
    stages: list[Stage] = []
    inputs: list[str] = []
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
            fields[key] = clean_value(value)
            section = key if key in {"stages", "inputs"} else ""
            continue
        if section == "stages":
            match = STAGE_RE.match(raw)
            if not match:
                errors.append(f"line {line_number}: stage must use inline mapping syntax")
                continue
            stage_fields = parse_inline_map(match.group(2))
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
        else:
            errors.append(f"line {line_number}: unsupported metadata syntax")

    return WorkItem(path=path, fields=fields, stages=stages, inputs=inputs), errors


def parse_timestamp(value: str) -> datetime:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def validate(item: WorkItem) -> list[str]:
    errors: list[str] = []
    missing = sorted(key for key in REQUIRED_FIELDS if key not in item.fields)
    errors.extend(f"missing required field: {key}" for key in missing)

    slug = item.fields.get("slug", "")
    if slug and not SLUG_RE.fullmatch(slug):
        errors.append(f"invalid slug: {slug}")
    if slug and slug != item.path.parent.name:
        errors.append(f"slug does not match directory: {slug} != {item.path.parent.name}")
    if not item.fields.get("title", "").strip() and "title" not in missing:
        errors.append("title must not be empty")

    status = item.fields.get("status", "")
    if status and status not in WORK_ITEM_STATUSES:
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

    if "stages" in item.fields and not item.stages:
        errors.append("stages must contain at least one stage")
    seen_stages: set[str] = set()
    item_root = item.path.parent.resolve()
    for stage in item.stages:
        if stage.name in seen_stages:
            errors.append(f"duplicate stage: {stage.name}")
        seen_stages.add(stage.name)
        if not stage.skill:
            errors.append(f"stage {stage.name} has empty skill")
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

    if "inputs" in item.fields and not item.inputs:
        errors.append("inputs must contain at least one entry")
    return errors


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
        fields.get("status", "<invalid>"),
        fields.get("updated_at", "<missing>"),
        fields.get("slug", item.path.parent.name),
        fields.get("title", "<missing>"),
        str(item.path),
    ]
    if extra:
        columns.append(extra)
    return "\t".join(columns)


def command_list(args: argparse.Namespace) -> int:
    if args.status and args.status not in WORK_ITEM_STATUSES:
        print(f"invalid status filter: {args.status}", file=sys.stderr)
        return 2
    print("status\tupdated_at\tslug\ttitle\tmeta")
    items = sorted(load_items(args.work_root), key=lambda pair: render_item(pair[0]))
    for item, _ in items:
        if args.status and item.fields.get("status") != args.status:
            continue
        print(render_item(item))
    return 0


def command_stale(args: argparse.Namespace) -> int:
    now = parse_timestamp(args.now) if args.now else datetime.now(timezone.utc)
    print("status\tupdated_at\tslug\ttitle\tmeta\tage_days")
    for item, _ in load_items(args.work_root):
        if item.fields.get("status") != "active":
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
