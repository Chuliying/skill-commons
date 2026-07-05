#!/usr/bin/env python3
"""Initialize a new plan directory with implementation/tasks/notes artifacts."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from planning_lib import (
    ImplementationPlan,
    ImplementationSection,
    PlanningError,
    atomic_write,
    build_snapshot,
    ensure_directory,
    normalize_text,
    now_timestamp,
    render_implementation,
    render_json,
    render_notes,
    render_tasks,
    short_hash,
    slugify,
    task_sort_key,
    write_lock,
    make_section_task,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="plans")
    parser.add_argument("--name", required=True)
    parser.add_argument("--slug")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).expanduser().resolve()
    slug = args.slug or slugify(args.name)
    plan_dir = root / slug

    if plan_dir.exists() and any(plan_dir.iterdir()) and not args.force:
        print(render_json({"error": "target exists", "plan_dir": str(plan_dir)}))
        return 2

    ensure_directory(plan_dir)
    timestamp = now_timestamp()

    try:
        with write_lock(plan_dir):
            section = ImplementationSection(
                section_id="I01",
                title="initial-intent",
                key="initial-intent",
                status="active",
                summary="Capture the first stable implementation direction.",
                intent="Describe the problem to solve and the intended outcome.",
                logic="Describe the current implementation logic, constraints, or workflow.",
                edge_cases=["EC01: Replace this placeholder with a real edge case."],
                impact_areas=["File/Artifact: TBD", "Workflow/Area: TBD"],
                validation=["V01: Replace this placeholder with a real validation step."],
                open_questions=["Q01: Replace this placeholder with a real open question."],
                significant_hash="",
            )
            section.significant_hash = short_hash(
                "\n".join(
                    [
                        normalize_text(section.intent),
                        normalize_text(section.logic),
                        "\n".join(section.impact_areas),
                        "\n".join(section.validation),
                        "\n".join(section.open_questions),
                    ]
                )
            )

            plan = ImplementationPlan(
                plan_name=args.name,
                plan_slug=slug,
                created_at=timestamp,
                updated_at=timestamp,
                goal="一句話描述這份規劃要完成什麼。",
                success_criteria=["SC01: Replace this placeholder with a success criterion."],
                scope=["In: Replace this placeholder with in-scope work."],
                non_goals=["Out: Replace this placeholder with out-of-scope work."],
                assumptions=["A01: Replace this placeholder with an assumption."],
                decisions=["D01: Replace this placeholder with an active decision."],
                sections=[section],
            )

            implementation_path = plan_dir / "implementation.md"
            task = make_section_task(section)
            tasks_path = plan_dir / "tasks.md"
            notes_path = plan_dir / "notes.md"

            snapshot = build_snapshot(plan, [task])
            events = [
                {
                    "note_id": "N001",
                    "timestamp": timestamp,
                    "type": "create",
                    "impact_ids": ["I01", "T01"],
                    "message": "Initialized the first planning artifacts.",
                }
            ]

            atomic_write(implementation_path, render_implementation(plan))
            atomic_write(
                tasks_path,
                render_tasks(args.name, timestamp, timestamp, sorted([task], key=task_sort_key)),
            )
            atomic_write(notes_path, render_notes(args.name, snapshot, events))
    except PlanningError as exc:
        print(render_json({"error": str(exc), "plan_dir": str(plan_dir)}))
        return 3

    print(
        render_json(
            {
                "plan_dir": str(plan_dir),
                "created": [
                    str(plan_dir / "implementation.md"),
                    str(plan_dir / "tasks.md"),
                    str(plan_dir / "notes.md"),
                ],
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
