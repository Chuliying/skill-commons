#!/usr/bin/env python3
"""Shared helpers for the plan-sync scripts."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional

ALLOWED_TASK_STATUSES = {
    "pending",
    "in_progress",
    "blocked",
    "done",
    "needs_review",
    "superseded",
}

ALLOWED_NOTE_TYPES = {
    "create",
    "decision",
    "scope_change",
    "execution_feedback",
    "status_change",
    "risk",
}

LEVEL2_HEADING_RE = re.compile(r"^## ([^\n]+)$", re.MULTILINE)
IMPL_HEADING_RE = re.compile(r"^### (I\d+) \| (.+)$", re.MULTILINE)
TASK_HEADING_RE = re.compile(r"^### (T\d+) \| (.+)$", re.MULTILINE)
SUBSECTION_RE = re.compile(r"^#### ([^\n]+)$", re.MULTILINE)
NOTE_LINE_RE = re.compile(
    r"^- (N\d+) \| ([^|]+) \| ([^|]+) \| ((?:\[[^\]]+\])+)\s\| (.+)$"
)


class PlanningError(RuntimeError):
    """Base error for planning scripts."""


class LockError(PlanningError):
    """Raised when a write lock cannot be acquired."""


@dataclass
class ImplementationSection:
    section_id: str
    title: str
    key: str
    status: str
    summary: str
    intent: str
    logic: str
    edge_cases: List[str]
    impact_areas: List[str]
    validation: List[str]
    open_questions: List[str]
    significant_hash: str


@dataclass
class ImplementationPlan:
    plan_name: str
    plan_slug: str
    created_at: str
    updated_at: str
    goal: str
    success_criteria: List[str]
    scope: List[str]
    non_goals: List[str]
    assumptions: List[str]
    decisions: List[str]
    sections: List[ImplementationSection]


@dataclass
class Task:
    task_id: str
    title: str
    source_ids: List[str]
    source_fingerprints: Dict[str, str]
    status: str
    priority: str
    owner: str
    summary: str
    intent: str
    expected_result: str
    execution_checklist: List[str]
    impact_scope: List[str]
    definition_of_done: List[str]
    verification: List[str]
    depends_on: List[str]
    blocks: List[str]
    execution_notes: List[str]


@dataclass
class NotesState:
    plan_name: str
    snapshot: Dict[str, str]
    events: List[Dict[str, object]]


def now_timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M")


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower()).strip("-")
    return slug or "plan"


def short_hash(value: str, length: int = 12) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:length]


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


@contextmanager
def write_lock(plan_dir: Path):
    ensure_directory(plan_dir)
    lock_path = plan_dir / ".plan.lock"
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    try:
        fd = os.open(lock_path, flags)
    except FileExistsError as exc:
        raise LockError(f"Lock already exists: {lock_path}") from exc

    try:
        payload = json.dumps({"pid": os.getpid(), "created_at": now_timestamp()})
        os.write(fd, payload.encode("utf-8"))
        os.close(fd)
        yield lock_path
    finally:
        try:
            lock_path.unlink()
        except FileNotFoundError:
            pass


def atomic_write(path: Path, content: str) -> None:
    ensure_directory(path.parent)
    fd, temp_path = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def section_body(text: str, heading: str) -> str:
    pattern = re.compile(rf"^## {re.escape(heading)}$", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        return ""

    next_match = LEVEL2_HEADING_RE.search(text, match.end())
    end = next_match.start() if next_match else len(text)
    return text[match.end() : end].strip()


def bullet_items(body: str) -> List[str]:
    items = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            items.append(stripped[2:].strip())
    return items


def extract_value_line(body: str) -> str:
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    return " ".join(lines)


def parse_metadata_block(block: str) -> Dict[str, str]:
    metadata = {}
    for line in block.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        payload = stripped[2:]
        if ":" not in payload:
            continue
        key, value = payload.split(":", 1)
        metadata[key.strip()] = value.strip()
    return metadata


def split_named_subsections(block: str) -> Dict[str, str]:
    matches = list(SUBSECTION_RE.finditer(block))
    if not matches:
        return {}

    sections = {}
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(block)
        sections[match.group(1).strip()] = block[start:end].strip()
    return sections


def parse_implementation(text: str) -> ImplementationPlan:
    metadata = parse_metadata_block(section_body(text, "Metadata"))
    goal = extract_value_line(section_body(text, "Goal"))
    success_criteria = bullet_items(section_body(text, "Success Criteria"))
    scope = bullet_items(section_body(text, "Scope"))
    non_goals = bullet_items(section_body(text, "Non-goals"))
    assumptions = bullet_items(section_body(text, "Assumptions"))
    decisions = bullet_items(section_body(text, "Decisions"))

    sections: List[ImplementationSection] = []
    matches = list(IMPL_HEADING_RE.finditer(text))
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        block = text[start:end].strip()
        subsection_start = SUBSECTION_RE.search(block)
        metadata_block = block[: subsection_start.start()] if subsection_start else block
        section_meta = parse_metadata_block(metadata_block)
        named = split_named_subsections(block)

        intent = named.get("Intent", "")
        logic = named.get("Logic", "")
        edge_cases = bullet_items(named.get("Edge Cases", ""))
        impact_areas = bullet_items(named.get("Impact Areas", ""))
        validation = bullet_items(named.get("Validation", ""))
        open_questions = bullet_items(named.get("Open Questions", ""))

        significant_text = "\n".join(
            [
                normalize_text(intent),
                normalize_text(logic),
                "\n".join(impact_areas),
                "\n".join(validation),
                "\n".join(open_questions),
            ]
        )

        sections.append(
            ImplementationSection(
                section_id=match.group(1),
                title=match.group(2).strip(),
                key=section_meta.get("Key", ""),
                status=section_meta.get("Status", "active"),
                summary=section_meta.get("Summary", ""),
                intent=intent,
                logic=logic,
                edge_cases=edge_cases,
                impact_areas=impact_areas,
                validation=validation,
                open_questions=open_questions,
                significant_hash=short_hash(significant_text),
            )
        )

    return ImplementationPlan(
        plan_name=metadata.get("Plan Name", ""),
        plan_slug=metadata.get("Plan Slug", ""),
        created_at=metadata.get("Created At", ""),
        updated_at=metadata.get("Updated At", ""),
        goal=goal,
        success_criteria=success_criteria,
        scope=scope,
        non_goals=non_goals,
        assumptions=assumptions,
        decisions=decisions,
        sections=sections,
    )


def parse_id_list(value: str) -> List[str]:
    stripped = value.strip()
    if not stripped.startswith("[") or not stripped.endswith("]"):
        return []
    inner = stripped[1:-1].strip()
    if not inner:
        return []
    return [item.strip() for item in inner.split(",") if item.strip()]


def parse_fingerprint_map(value: str) -> Dict[str, str]:
    if not value:
        return {}
    mapping = {}
    for part in value.split(";"):
        chunk = part.strip()
        if not chunk or "=" not in chunk:
            continue
        key, fingerprint = chunk.split("=", 1)
        mapping[key.strip()] = fingerprint.strip()
    return mapping


def parse_dependency_items(value: str) -> List[str]:
    return parse_id_list(value)


def parse_tasks(text: str) -> List[Task]:
    tasks: List[Task] = []
    matches = list(TASK_HEADING_RE.finditer(text))
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        block = text[start:end].strip()
        subsection_start = SUBSECTION_RE.search(block)
        metadata_block = block[: subsection_start.start()] if subsection_start else block
        meta = parse_metadata_block(metadata_block)
        named = split_named_subsections(block)
        dependency_block = named.get("Dependency", "")
        dependency_meta = parse_metadata_block(dependency_block)

        tasks.append(
            Task(
                task_id=match.group(1),
                title=match.group(2).strip(),
                source_ids=parse_id_list(meta.get("Source IDs", "[]")),
                source_fingerprints=parse_fingerprint_map(
                    meta.get("Source Fingerprints", "")
                ),
                status=meta.get("Status", "pending"),
                priority=meta.get("Priority", "P1"),
                owner=meta.get("Owner", "ai"),
                summary=meta.get("Summary", ""),
                intent=extract_value_line(named.get("Intent", "")),
                expected_result=extract_value_line(named.get("Expected Result", "")),
                execution_checklist=bullet_items(named.get("Execution Checklist", "")),
                impact_scope=bullet_items(named.get("Impact Scope", "")),
                definition_of_done=bullet_items(named.get("Definition of Done", "")),
                verification=bullet_items(named.get("Verification", "")),
                depends_on=parse_dependency_items(dependency_meta.get("Depends On", "[]")),
                blocks=parse_dependency_items(dependency_meta.get("Blocks", "[]")),
                execution_notes=bullet_items(named.get("Execution Notes", "")),
            )
        )
    return tasks


def parse_notes(text: str) -> NotesState:
    header_match = re.search(r"^# Notes: (.+)$", text, re.MULTILINE)
    plan_name = header_match.group(1).strip() if header_match else ""
    snapshot_body = section_body(text, "Current State Snapshot")
    snapshot_meta = parse_metadata_block(snapshot_body)

    events = []
    for line in section_body(text, "Event Log").splitlines():
        match = NOTE_LINE_RE.match(line.strip())
        if not match:
            continue
        impact_ids = re.findall(r"\[([^\]]+)\]", match.group(4))
        events.append(
            {
                "note_id": match.group(1),
                "timestamp": match.group(2).strip(),
                "type": match.group(3).strip(),
                "impact_ids": impact_ids,
                "message": match.group(5).strip(),
            }
        )

    return NotesState(plan_name=plan_name, snapshot=snapshot_meta, events=events)


def render_implementation(plan: ImplementationPlan) -> str:
    lines = [
        f"# Plan: {plan.plan_name}",
        "",
        "## Metadata",
        f"- Plan Name: {plan.plan_name}",
        f"- Plan Slug: {plan.plan_slug}",
        "- Status: active",
        f"- Created At: {plan.created_at}",
        f"- Updated At: {plan.updated_at}",
        "",
        "## Goal",
        plan.goal,
        "",
        "## Success Criteria",
        *(f"- {item}" for item in plan.success_criteria),
        "",
        "## Scope",
        *(f"- {item}" for item in plan.scope),
        "",
        "## Non-goals",
        *(f"- {item}" for item in plan.non_goals),
        "",
        "## Assumptions",
        *(f"- {item}" for item in plan.assumptions),
        "",
        "## Decisions",
        *(f"- {item}" for item in plan.decisions),
        "",
        "## Implementation Sections",
        "",
    ]

    for section in plan.sections:
        lines.extend(
            [
                f"### {section.section_id} | {section.title}",
                f"- Key: {section.key}",
                f"- Title: {section.title}",
                f"- Status: {section.status}",
                f"- Summary: {section.summary}",
                "",
                "#### Intent",
                section.intent,
                "",
                "#### Logic",
                section.logic,
                "",
                "#### Edge Cases",
                *(f"- {item}" for item in section.edge_cases),
                "",
                "#### Impact Areas",
                *(f"- {item}" for item in section.impact_areas),
                "",
                "#### Validation",
                *(f"- {item}" for item in section.validation),
                "",
                "#### Open Questions",
                *(f"- {item}" for item in section.open_questions),
                "",
            ]
        )

    return "\n".join(lines).rstrip() + "\n"


def render_task(task: Task) -> str:
    fingerprints = "; ".join(
        f"{source_id}={task.source_fingerprints[source_id]}"
        for source_id in task.source_ids
        if source_id in task.source_fingerprints
    )
    lines = [
        f"### {task.task_id} | {task.title}",
        f"- Source IDs: [{', '.join(task.source_ids)}]",
        f"- Source Fingerprints: {fingerprints}",
        f"- Status: {task.status}",
        f"- Priority: {task.priority}",
        f"- Owner: {task.owner}",
        f"- Summary: {task.summary}",
        "",
        "#### Intent",
        task.intent,
        "",
        "#### Expected Result",
        task.expected_result,
        "",
        "#### Execution Checklist",
        *(f"- [ ] {item}" if not item.startswith("[") else f"- {item}" for item in task.execution_checklist),
        "",
        "#### Impact Scope",
        *(f"- {item}" for item in task.impact_scope),
        "",
        "#### Definition of Done",
        *(f"- {item}" for item in task.definition_of_done),
        "",
        "#### Verification",
        *(f"- {item}" for item in task.verification),
        "",
        "#### Dependency",
        f"- Depends On: [{', '.join(task.depends_on)}]",
        f"- Blocks: [{', '.join(task.blocks)}]",
        "",
        "#### Execution Notes",
        *(f"- {item}" for item in task.execution_notes),
        "",
    ]
    return "\n".join(lines)


def render_tasks(plan_name: str, generated_at: str, updated_at: str, tasks: List[Task]) -> str:
    lines = [
        f"# Tasks: {plan_name}",
        "",
        "## Metadata",
        f"- Plan Name: {plan_name}",
        "- Source File: implementation.md",
        f"- Generated At: {generated_at}",
        f"- Updated At: {updated_at}",
        "",
        "## Task List",
        "",
    ]
    for task in tasks:
        lines.append(render_task(task))
    return "\n".join(lines).rstrip() + "\n"


def format_snapshot_items(items: Iterable[str], fallback: str = "None") -> str:
    cleaned = [normalize_text(item) for item in items if normalize_text(item)]
    if not cleaned:
        return fallback
    return "; ".join(cleaned[:3])


def render_notes(plan_name: str, snapshot: Dict[str, str], events: List[Dict[str, object]]) -> str:
    lines = [
        f"# Notes: {plan_name}",
        "",
        "## Current State Snapshot",
        f"- Active Intent: {snapshot.get('Active Intent', 'None')}",
        f"- Current Decisions: {snapshot.get('Current Decisions', 'None')}",
        f"- Current Scope: {snapshot.get('Current Scope', 'None')}",
        f"- Open Risks: {snapshot.get('Open Risks', 'None')}",
        f"- Next Action: {snapshot.get('Next Action', 'None')}",
        f"- Last Updated: {snapshot.get('Last Updated', now_timestamp())}",
        "",
        "## Event Log",
    ]
    for event in events:
        impact = "".join(f"[{item}]" for item in event["impact_ids"])
        lines.append(
            f"- {event['note_id']} | {event['timestamp']} | {event['type']} | {impact} | {event['message']}"
        )
    return "\n".join(lines).rstrip() + "\n"


def make_section_task(section: ImplementationSection, existing: Optional[Task] = None) -> Task:
    task_id = f"T{section.section_id[1:]}"
    title = section.key or section.title
    source_ids = [section.section_id]
    fingerprints = {section.section_id: section.significant_hash}
    status = existing.status if existing else "pending"
    old_fingerprint = existing.source_fingerprints.get(section.section_id) if existing else None
    if existing:
        if existing.status == "superseded":
            status = "needs_review"
        elif old_fingerprint and old_fingerprint != section.significant_hash:
            status = "needs_review"

    summary = section.summary or f"Implement {section.title}"
    expected_result = (
        f"The changes described in `{section.section_id}` are delivered and validated."
    )
    execution_checklist = [
        f"Re-read `{section.section_id}` and confirm the intended behavior.",
        "Break the section into concrete changes and update the affected artifacts.",
        "Verify the work against the section validation and capture evidence.",
    ]
    impact_scope = section.impact_areas or ["File/Artifact: TBD"]
    definition_of_done = section.validation or ["DoD01: Validation items are satisfied."]
    verification = section.validation or ["Verify01: Confirm the section requirements manually."]
    execution_notes = existing.execution_notes if existing else ["None"]

    return Task(
        task_id=task_id,
        title=title,
        source_ids=source_ids,
        source_fingerprints=fingerprints,
        status=status,
        priority=existing.priority if existing else "P1",
        owner=existing.owner if existing else "ai",
        summary=summary,
        intent=normalize_text(section.intent) or "Keep execution aligned with the source section.",
        expected_result=expected_result,
        execution_checklist=execution_checklist,
        impact_scope=impact_scope,
        definition_of_done=definition_of_done,
        verification=verification,
        depends_on=existing.depends_on if existing else [],
        blocks=existing.blocks if existing else [],
        execution_notes=execution_notes,
    )


def build_snapshot(plan: ImplementationPlan, tasks: List[Task]) -> Dict[str, str]:
    open_risks = [
        task.summary
        for task in tasks
        if task.status in {"blocked", "needs_review"}
    ]
    if not open_risks:
        open_risks = plan.sections[0].open_questions if plan.sections else []

    next_actions = []
    for desired_status in ("in_progress", "needs_review", "pending"):
        for task in tasks:
            if task.status == desired_status:
                next_actions.append(f"{task.task_id}: {task.summary}")
        if next_actions:
            break

    return {
        "Active Intent": normalize_text(plan.goal) or "None",
        "Current Decisions": format_snapshot_items(plan.decisions),
        "Current Scope": format_snapshot_items(plan.scope),
        "Open Risks": format_snapshot_items(open_risks),
        "Next Action": format_snapshot_items(next_actions, fallback="None"),
        "Last Updated": now_timestamp(),
    }


def next_note_id(events: List[Dict[str, object]]) -> str:
    if not events:
        return "N001"
    last_number = max(int(event["note_id"][1:]) for event in events)
    return f"N{last_number + 1:03d}"


def ensure_note_type(note_type: str) -> None:
    if note_type not in ALLOWED_NOTE_TYPES:
        raise PlanningError(f"Unsupported note type: {note_type}")


def parse_impact_arg(value: str) -> List[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def plan_dir_from_args(value: str) -> Path:
    return Path(value).expanduser().resolve()


def task_sort_key(task: Task) -> int:
    return int(task.task_id[1:])


def render_json(data: object) -> str:
    return json.dumps(data, ensure_ascii=True, indent=2)
