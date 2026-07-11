#!/usr/bin/env python3
"""Shared helpers for the canonical plan-sync data shape."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path


ALLOWED_TASK_STATUSES = {
    "pending",
    "in_progress",
    "blocked",
    "done",
    "needs_review",
    "superseded",
}

LEVEL2_HEADING_RE = re.compile(r"^## ([^\n]+)$", re.MULTILINE)
TASK_HEADING_RE = re.compile(r"^### (T\d+) \| (.+)$", re.MULTILINE)
SUBSECTION_RE = re.compile(r"^#### ([^\n]+)$", re.MULTILINE)


@dataclass
class UnifiedTask:
    task_id: str
    title: str
    status: str
    depends_on: list[str]
    intent: str
    expected_result: str
    definition_of_done: list[str]
    verification: list[str]
    verification_evidence: list[str]
    blocker_reason: str
    blocker_ref: str
    unblocked_ref: str


@dataclass
class UnifiedPlan:
    plan_name: str
    format_version: str
    concurrency: str
    intent: str
    scope: str
    non_goals: str
    sources: list[str]
    tasks: list[UnifiedTask]
    change_log: list[str]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def section_body(text: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}$", text, re.MULTILINE)
    if not match:
        return ""
    next_match = LEVEL2_HEADING_RE.search(text, match.end())
    end = next_match.start() if next_match else len(text)
    return text[match.end() : end].strip()


def bullet_items(body: str) -> list[str]:
    items: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            items.append(stripped[2:].strip())
        elif items and stripped and line.startswith(("  ", "\t")):
            items[-1] = f"{items[-1]} {stripped}"
    return items


def extract_value_line(body: str) -> str:
    return " ".join(line.strip() for line in body.splitlines() if line.strip())


def parse_metadata_block(block: str) -> dict[str, str]:
    metadata: dict[str, str] = {}
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


def split_named_subsections(block: str) -> dict[str, str]:
    matches = list(SUBSECTION_RE.finditer(block))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(block)
        sections[match.group(1).strip()] = block[start:end].strip()
    return sections


def parse_id_list(value: str) -> list[str]:
    stripped = value.strip()
    if not stripped.startswith("[") or not stripped.endswith("]"):
        return []
    inner = stripped[1:-1].strip()
    return [item.strip() for item in inner.split(",") if item.strip()] if inner else []


def parse_unified_plan(text: str) -> UnifiedPlan:
    header_match = re.search(r"^# Plan: (.+)$", text, re.MULTILINE)
    plan_meta = parse_metadata_block(section_body(text, "Plan"))
    tasks_body = section_body(text, "Tasks")
    task_matches = list(TASK_HEADING_RE.finditer(tasks_body))
    tasks: list[UnifiedTask] = []

    for index, match in enumerate(task_matches):
        start = match.end()
        end = (
            task_matches[index + 1].start()
            if index + 1 < len(task_matches)
            else len(tasks_body)
        )
        block = tasks_body[start:end].strip()
        subsection_start = SUBSECTION_RE.search(block)
        metadata_block = block[: subsection_start.start()] if subsection_start else block
        metadata = parse_metadata_block(metadata_block)
        named = split_named_subsections(block)
        tasks.append(
            UnifiedTask(
                task_id=match.group(1),
                title=match.group(2).strip(),
                status=metadata.get("Status", ""),
                depends_on=parse_id_list(metadata.get("Depends On", "[]")),
                intent=extract_value_line(named.get("Intent", "")),
                expected_result=extract_value_line(named.get("Expected Result", "")),
                definition_of_done=bullet_items(named.get("Definition of Done", "")),
                verification=bullet_items(named.get("Verification", "")),
                verification_evidence=bullet_items(
                    named.get("Verification Evidence", "")
                ),
                blocker_reason=metadata.get("Blocker Reason", ""),
                blocker_ref=metadata.get("Blocker Ref", ""),
                unblocked_ref=metadata.get("Unblocked Ref", ""),
            )
        )

    return UnifiedPlan(
        plan_name=header_match.group(1).strip() if header_match else "",
        format_version=plan_meta.get("Format", ""),
        concurrency=plan_meta.get("Concurrency", "1"),
        intent=plan_meta.get("Intent", ""),
        scope=plan_meta.get("Scope", ""),
        non_goals=plan_meta.get("Non-goals", ""),
        sources=bullet_items(section_body(text, "Sources")),
        tasks=tasks,
        change_log=bullet_items(section_body(text, "Change Log")),
    )


def canonical_concurrency_limit(plan: UnifiedPlan) -> int:
    return int(plan.concurrency) if re.fullmatch(r"[1-9][0-9]*", plan.concurrency) else 1


def derive_task_state(tasks: list[object], concurrency_limit: int = 1) -> dict[str, object]:
    task_by_id = {str(task.task_id): task for task in tasks}
    remaining = [
        str(task.task_id)
        for task in tasks
        if getattr(task, "status", "") not in {"done", "superseded"}
    ]
    in_progress = [
        str(task.task_id)
        for task in tasks
        if getattr(task, "status", "") == "in_progress"
    ]
    explicit_blocked = [
        str(task.task_id)
        for task in tasks
        if getattr(task, "status", "") == "blocked"
    ]
    dependency_blocked: dict[str, list[str]] = {}
    ready: list[str] = []

    for task in tasks:
        task_id = str(task.task_id)
        status = getattr(task, "status", "")
        if status in {"done", "superseded"}:
            continue
        unmet = [
            dependency
            for dependency in getattr(task, "depends_on", [])
            if dependency not in task_by_id
            or getattr(task_by_id[dependency], "status", "") != "done"
        ]
        if unmet:
            dependency_blocked[task_id] = unmet
        elif status in {"pending", "needs_review"}:
            ready.append(task_id)

    available_slots = max(0, concurrency_limit - len(in_progress))
    dispatchable = ready[:available_slots]
    selected = in_progress or dispatchable
    if not remaining:
        plan_state = "complete"
    elif in_progress:
        plan_state = "running"
    elif dispatchable:
        plan_state = "ready"
    else:
        plan_state = "blocked"

    return {
        "plan_state": plan_state,
        "remaining_tasks": remaining,
        "in_progress_tasks": in_progress,
        "ready_tasks": ready,
        "dispatchable_tasks": dispatchable,
        "explicit_blocked": explicit_blocked,
        "dependency_blocked": dependency_blocked,
        "active_task": selected[0] if selected else None,
        "concurrency": {
            "limit": concurrency_limit,
            "in_progress": len(in_progress),
            "available": available_slots,
        },
    }


def plan_dir_from_args(value: str) -> Path:
    return Path(value).expanduser().resolve()


def render_json(data: object) -> str:
    return json.dumps(data, ensure_ascii=True, indent=2)
