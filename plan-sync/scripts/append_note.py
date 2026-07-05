#!/usr/bin/env python3
"""Append a single event log entry to notes.md."""

from __future__ import annotations

import argparse
import sys

sys.dont_write_bytecode = True

from planning_lib import (
    PlanningError,
    atomic_write,
    ensure_note_type,
    next_note_id,
    now_timestamp,
    parse_impact_arg,
    parse_implementation,
    parse_notes,
    parse_tasks,
    plan_dir_from_args,
    read_text,
    render_json,
    render_notes,
    write_lock,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-dir", required=True)
    parser.add_argument("--type", required=True)
    parser.add_argument("--impact", required=True)
    parser.add_argument("--message", required=True)
    parser.add_argument("--timestamp")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan_dir = plan_dir_from_args(args.plan_dir)

    try:
        ensure_note_type(args.type)
        impact_ids = parse_impact_arg(args.impact)
        with write_lock(plan_dir):
            implementation = parse_implementation(read_text(plan_dir / "implementation.md"))
            tasks = parse_tasks(read_text(plan_dir / "tasks.md"))
            notes = parse_notes(read_text(plan_dir / "notes.md"))

            valid_ids = {section.section_id for section in implementation.sections}
            valid_ids.update(task.task_id for task in tasks)
            invalid_ids = [item for item in impact_ids if item not in valid_ids]
            if invalid_ids:
                print(render_json({"error": "invalid impact ids", "invalid_ids": invalid_ids}))
                return 2

            event = {
                "note_id": next_note_id(notes.events),
                "timestamp": args.timestamp or now_timestamp(),
                "type": args.type,
                "impact_ids": impact_ids,
                "message": " ".join(args.message.strip().splitlines()),
            }
            notes.events.append(event)

            atomic_write(
                plan_dir / "notes.md",
                render_notes(notes.plan_name or implementation.plan_name, notes.snapshot, notes.events),
            )
    except PlanningError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 3
    except FileNotFoundError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 1

    print(render_json({"appended_note": event["note_id"], "plan_dir": str(plan_dir)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
