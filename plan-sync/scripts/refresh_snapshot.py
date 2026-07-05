#!/usr/bin/env python3
"""Refresh the Current State Snapshot in notes.md."""

from __future__ import annotations

import argparse
import sys

sys.dont_write_bytecode = True

from planning_lib import (
    PlanningError,
    atomic_write,
    build_snapshot,
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
    parser.add_argument("--write", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan_dir = plan_dir_from_args(args.plan_dir)

    try:
        if args.write:
            with write_lock(plan_dir):
                implementation = parse_implementation(read_text(plan_dir / "implementation.md"))
                tasks = parse_tasks(read_text(plan_dir / "tasks.md"))
                notes = parse_notes(read_text(plan_dir / "notes.md"))
                snapshot = build_snapshot(implementation, tasks)
                content = render_notes(notes.plan_name or implementation.plan_name, snapshot, notes.events)
                atomic_write(plan_dir / "notes.md", content)
        else:
            implementation = parse_implementation(read_text(plan_dir / "implementation.md"))
            tasks = parse_tasks(read_text(plan_dir / "tasks.md"))
            notes = parse_notes(read_text(plan_dir / "notes.md"))
            snapshot = build_snapshot(implementation, tasks)
            content = render_notes(notes.plan_name or implementation.plan_name, snapshot, notes.events)

        print(
            render_json(
                {
                    "plan_dir": str(plan_dir),
                    "snapshot_preview": snapshot,
                    "wrote_file": args.write,
                }
            )
        )
    except PlanningError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 3
    except FileNotFoundError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
