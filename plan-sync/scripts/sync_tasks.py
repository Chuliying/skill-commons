#!/usr/bin/env python3
"""Synchronize tasks.md from implementation.md using deterministic rules."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from planning_lib import (
    PlanningError,
    Task,
    atomic_write,
    make_section_task,
    now_timestamp,
    parse_implementation,
    parse_tasks,
    plan_dir_from_args,
    read_text,
    render_json,
    render_tasks,
    task_sort_key,
    write_lock,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-dir", required=True)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    return parser.parse_args()


def build_synced_tasks(plan_dir: Path):
    implementation = parse_implementation(read_text(plan_dir / "implementation.md"))
    tasks_path = plan_dir / "tasks.md"
    existing_tasks = parse_tasks(read_text(tasks_path)) if tasks_path.exists() else []
    existing_by_id = {task.task_id: task for task in existing_tasks}

    synced = []
    added = []
    updated = []
    warnings = []
    expected_ids = set()

    for section in implementation.sections:
        task_id = f"T{section.section_id[1:]}"
        expected_ids.add(task_id)
        old_task = existing_by_id.get(task_id)
        new_task = make_section_task(section, old_task)
        synced.append(new_task)
        if old_task is None:
            added.append(task_id)
        elif old_task.status != new_task.status or old_task.source_fingerprints != new_task.source_fingerprints:
            updated.append(task_id)

    for task in existing_tasks:
        if task.task_id in expected_ids:
            continue
        if task.status != "superseded":
            task.status = "superseded"
            updated.append(task.task_id)
        synced.append(task)
        warnings.append(f"{task.task_id} has no matching implementation section and was superseded.")

    synced.sort(key=task_sort_key)
    generated_at = now_timestamp()
    return implementation, synced, added, updated, warnings, generated_at


def main() -> int:
    args = parse_args()
    plan_dir = plan_dir_from_args(args.plan_dir)

    try:
        if args.write:
            with write_lock(plan_dir):
                implementation, tasks, added, updated, warnings, timestamp = build_synced_tasks(plan_dir)
                tasks_path = plan_dir / "tasks.md"
                old_generated = ""
                if tasks_path.exists():
                    for line in read_text(tasks_path).splitlines():
                        if line.startswith("- Generated At:"):
                            old_generated = line.split(":", 1)[1].strip()
                            break
                generated_at = old_generated or timestamp
                content = render_tasks(implementation.plan_name, generated_at, timestamp, tasks)
                atomic_write(tasks_path, content)
        else:
            implementation, tasks, added, updated, warnings, timestamp = build_synced_tasks(plan_dir)
            tasks_path = plan_dir / "tasks.md"
            old_generated = ""
            if tasks_path.exists():
                for line in read_text(tasks_path).splitlines():
                    if line.startswith("- Generated At:"):
                        old_generated = line.split(":", 1)[1].strip()
                        break
            generated_at = old_generated or timestamp
            content = render_tasks(implementation.plan_name, generated_at, timestamp, tasks)

        payload = {
            "plan_dir": str(plan_dir),
            "added_tasks": added,
            "updated_tasks": sorted(set(updated)),
            "superseded_tasks": [task.task_id for task in tasks if task.status == "superseded"],
            "warnings": warnings,
        }
        if args.format == "json":
            print(render_json(payload))
        else:
            print(content)
    except PlanningError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 3
    except FileNotFoundError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
