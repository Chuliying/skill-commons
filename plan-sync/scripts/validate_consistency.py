#!/usr/bin/env python3
"""Validate consistency across implementation/tasks/notes artifacts."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from planning_lib import (
    ALLOWED_NOTE_TYPES,
    ALLOWED_TASK_STATUSES,
    parse_implementation,
    parse_notes,
    parse_tasks,
    plan_dir_from_args,
    read_text,
    render_json,
)


FIXED_PLACEHOLDERS = {
    "一句話描述這份規劃要完成什麼。",
    "Capture the first stable implementation direction.",
    "Describe the problem to solve and the intended outcome.",
    "Describe the current implementation logic, constraints, or workflow.",
    "Convert the initial implementation section into executable work.",
    "Keep task execution aligned to the source section.",
    "The changes described in `I01` are delivered and verified.",
    "Initialized the first planning artifacts.",
}
BRACE_PLACEHOLDER_RE = re.compile(r"\{[a-z][a-z0-9-]*\}")
ANGLE_PLACEHOLDER_RE = re.compile(r"<[^>\n]+>")
ELLIPSIS_PLACEHOLDER_RE = re.compile(r"(?:^|:\s)(?:\.\.\.|…)$")
LITE_TASK_RE = re.compile(r"^### (T\d+) \| (.+)$", re.MULTILINE)
LITE_SUBSECTION_RE = re.compile(r"^#### ([^\n]+)$", re.MULTILINE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-dir", required=True)
    return parser.parse_args()


def placeholder_errors(path: Path, text: str) -> list[str]:
    errors = []
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip().removeprefix("- ").strip()
        reasons = []
        if BRACE_PLACEHOLDER_RE.search(line):
            reasons.append("template variable")
        if ANGLE_PLACEHOLDER_RE.search(line):
            reasons.append("angle-bracket value")
        if ELLIPSIS_PLACEHOLDER_RE.search(stripped):
            reasons.append("ellipsis value")
        if "Replace this placeholder" in line:
            reasons.append("replacement instruction")
        if re.search(r"\b(?:TBD|TODO)\b", line):
            reasons.append("unfinished marker")
        if stripped in FIXED_PLACEHOLDERS:
            reasons.append("template default")
        if reasons:
            preview = line.strip()[:120]
            errors.append(
                f"{path.name}:{line_number}: placeholder ({', '.join(reasons)}): {preview}"
            )
    return errors


def section_body(text: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}$", text, re.MULTILINE)
    if not match:
        return ""
    next_heading = re.search(r"^## [^\n]+$", text[match.end() :], re.MULTILINE)
    end = match.end() + next_heading.start() if next_heading else len(text)
    return text[match.end() : end].strip()


def subsection_body(block: str, heading: str) -> str:
    matches = list(LITE_SUBSECTION_RE.finditer(block))
    for index, match in enumerate(matches):
        if match.group(1).strip() != heading:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(block)
        return block[match.end() : end].strip()
    return ""


def validate_lite(plan_dir: Path) -> tuple[list[str], list[str], dict[str, int | str]]:
    path = plan_dir / "plan.md"
    text = read_text(path)
    errors = placeholder_errors(path, text)
    warnings: list[str] = []

    plan_body = section_body(text, "Plan")
    tasks_body = section_body(text, "Tasks")
    change_log = section_body(text, "Change Log")
    for heading, body in (("Plan", plan_body), ("Tasks", tasks_body), ("Change Log", change_log)):
        if not body:
            errors.append(f"plan.md is missing non-empty `## {heading}`")

    plan_fields = {}
    for line in plan_body.splitlines():
        match = re.match(r"^- (Intent|Scope|Non-goals):\s*(.+)$", line.strip())
        if match:
            plan_fields[match.group(1)] = match.group(2).strip()
    for field in ("Intent", "Scope", "Non-goals"):
        if not plan_fields.get(field):
            errors.append(f"plan.md Plan section is missing `{field}`")

    task_matches = list(LITE_TASK_RE.finditer(tasks_body))
    if not task_matches:
        errors.append("plan.md has no Lite tasks")
    seen_tasks = set()
    for index, match in enumerate(task_matches):
        task_id = match.group(1)
        start = match.end()
        end = task_matches[index + 1].start() if index + 1 < len(task_matches) else len(tasks_body)
        block = tasks_body[start:end].strip()
        if task_id in seen_tasks:
            errors.append(f"duplicate Lite task: {task_id}")
        seen_tasks.add(task_id)
        status_match = re.search(r"^- Status:\s*(\S+)\s*$", block, re.MULTILINE)
        if not status_match:
            errors.append(f"{task_id} is missing Status")
        elif status_match.group(1) not in ALLOWED_TASK_STATUSES:
            errors.append(f"{task_id} uses invalid status `{status_match.group(1)}`")
        for heading in ("Intent", "Expected Result", "Verification"):
            if not subsection_body(block, heading):
                errors.append(f"{task_id} is missing {heading}")

    return errors, warnings, {"mode": "lite", "tasks": len(task_matches)}


def main() -> int:
    args = parse_args()
    plan_dir = plan_dir_from_args(args.plan_dir)

    errors = []
    warnings = []

    lite_path = plan_dir / "plan.md"
    three_file_paths = [
        plan_dir / "implementation.md",
        plan_dir / "tasks.md",
        plan_dir / "notes.md",
    ]
    has_lite = lite_path.is_file()
    has_three_file = any(path.is_file() for path in three_file_paths)

    if has_lite and has_three_file:
        payload = {
            "pass": False,
            "errors": ["plan directory mixes Lite plan.md with three-file artifacts"],
            "warnings": [],
            "stats": {"mode": "mixed"},
        }
        print(render_json(payload))
        return 2
    elif has_lite:
        try:
            errors, warnings, stats = validate_lite(plan_dir)
        except FileNotFoundError as exc:
            print(render_json({"pass": False, "errors": [str(exc)], "warnings": []}))
            return 2
        payload = {
            "pass": not errors,
            "errors": errors,
            "warnings": warnings,
            "stats": stats,
        }
        print(render_json(payload))
        if errors:
            return 2
        if warnings:
            return 1
        return 0

    try:
        implementation_text = read_text(three_file_paths[0])
        tasks_text = read_text(three_file_paths[1])
        notes_text = read_text(three_file_paths[2])
        for path, text in zip(three_file_paths, (implementation_text, tasks_text, notes_text)):
            errors.extend(placeholder_errors(path, text))
        implementation = parse_implementation(implementation_text)
        tasks = parse_tasks(tasks_text)
        notes = parse_notes(notes_text)
    except FileNotFoundError as exc:
        print(render_json({"pass": False, "errors": [str(exc)], "warnings": []}))
        return 2

    if not implementation.sections:
        errors.append("implementation.md has no implementation sections")

    section_ids = {section.section_id for section in implementation.sections}
    section_keys = set()
    for section in implementation.sections:
        if not section.key:
            errors.append(f"{section.section_id} is missing Key")
        if section.key in section_keys:
            errors.append(f"duplicate implementation key: {section.key}")
        section_keys.add(section.key)
        if not section.validation:
            errors.append(f"{section.section_id} is missing Validation items")
        if not section.impact_areas:
            warnings.append(f"{section.section_id} has no Impact Areas")

    referenced_section_ids = set()
    section_by_id = {section.section_id: section for section in implementation.sections}
    task_ids = {task.task_id for task in tasks}
    for task in tasks:
        if task.status not in ALLOWED_TASK_STATUSES:
            errors.append(f"{task.task_id} uses invalid status `{task.status}`")
        if not task.source_ids:
            errors.append(f"{task.task_id} is missing Source IDs")
        for source_id in task.source_ids:
            if source_id not in section_ids:
                errors.append(f"{task.task_id} references missing source id `{source_id}`")
            else:
                referenced_section_ids.add(source_id)
        if not task.definition_of_done:
            errors.append(f"{task.task_id} is missing Definition of Done")
        if not task.verification:
            errors.append(f"{task.task_id} is missing Verification")
        for source_id in task.source_ids:
            if source_id not in task.source_fingerprints and task.status != "superseded":
                errors.append(f"{task.task_id} is missing fingerprint for `{source_id}`")
            elif source_id in section_by_id and task.status not in {"needs_review", "superseded"}:
                expected_hash = section_by_id[source_id].significant_hash
                actual_hash = task.source_fingerprints.get(source_id)
                if actual_hash != expected_hash:
                    errors.append(
                        f"{task.task_id} fingerprint for `{source_id}` is stale; re-sync tasks or mark it needs_review"
                    )

    missing_tasks = sorted(section_ids - referenced_section_ids)
    if missing_tasks:
        errors.append(f"missing tasks for sections: {', '.join(missing_tasks)}")

    required_snapshot_keys = {
        "Active Intent",
        "Current Decisions",
        "Current Scope",
        "Open Risks",
        "Next Action",
        "Last Updated",
    }
    missing_snapshot = sorted(required_snapshot_keys - set(notes.snapshot.keys()))
    if missing_snapshot:
        errors.append(f"notes.md snapshot missing keys: {', '.join(missing_snapshot)}")

    snapshot_lines = [
        notes.snapshot.get("Active Intent", ""),
        notes.snapshot.get("Current Decisions", ""),
        notes.snapshot.get("Current Scope", ""),
        notes.snapshot.get("Open Risks", ""),
        notes.snapshot.get("Next Action", ""),
        notes.snapshot.get("Last Updated", ""),
    ]
    if len(snapshot_lines) > 6:
        errors.append("snapshot contains too many lines")

    for event in notes.events:
        if event["type"] not in ALLOWED_NOTE_TYPES:
            errors.append(f"{event['note_id']} uses invalid note type `{event['type']}`")
        if not event["impact_ids"]:
            errors.append(f"{event['note_id']} is missing impact ids")
        for impact_id in event["impact_ids"]:
            if impact_id not in section_ids and impact_id not in task_ids:
                errors.append(f"{event['note_id']} references unknown impact id `{impact_id}`")

    payload = {
        "pass": not errors,
        "errors": errors,
        "warnings": warnings,
        "stats": {
            "implementation_sections": len(implementation.sections),
            "tasks": len(tasks),
            "notes": len(notes.events),
        },
    }
    print(render_json(payload))
    if errors:
        return 2
    if warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
