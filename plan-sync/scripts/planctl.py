#!/usr/bin/env python3
"""Unified read/check/status surface for canonical Plan Sync."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from planning_lib import (
    canonical_concurrency_limit,
    derive_task_state,
    parse_unified_plan,
    plan_dir_from_args,
    read_text,
    render_json,
)
from validate_consistency import validate_plan_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="validate plan consistency")
    check.add_argument("--plan-dir", required=True)

    status = subparsers.add_parser("status", help="show compact current plan state")
    status.add_argument("--plan-dir", required=True)
    status.add_argument("--json", action="store_true", dest="as_json")
    status.add_argument("--goal-status", action="store_true")

    return parser


def plan_status(plan_dir: Path) -> tuple[dict[str, object], int]:
    validation, return_code = validate_plan_dir(plan_dir)
    stats = validation.get("stats", {})
    mode = str(stats.get("mode", "unknown")) if isinstance(stats, dict) else "unknown"

    tasks: list[object] = []
    next_action = "None"
    concurrency_limit = 1
    if validation.get("pass") and (plan_dir / "plan.md").is_file():
        plan = parse_unified_plan(read_text(plan_dir / "plan.md"))
        tasks = list(plan.tasks)
        concurrency_limit = canonical_concurrency_limit(plan)

    state = derive_task_state(tasks, concurrency_limit)
    active_task = state["active_task"]
    if not validation.get("pass"):
        state["plan_state"] = "invalid"
        state["ready_tasks"] = []
        state["dispatchable_tasks"] = []
        active_task = None
        next_action = "Repair plan consistency errors"
    elif active_task is not None:
        active = next(task for task in tasks if task.task_id == active_task)
        next_action = f"{active.task_id}: {active.title}"

    blocker_details = {
        task.task_id: {
            "reason": getattr(task, "blocker_reason", ""),
            "reference": getattr(task, "blocker_ref", ""),
        }
        for task in tasks
        if getattr(task, "status", "") == "blocked"
    }

    payload: dict[str, object] = {
        "mode": mode,
        "consistency": "PASS" if validation.get("pass") else "FAIL",
        "plan_state": state["plan_state"],
        "host_goal": "unmanaged",
        "active_task": active_task,
        "next_action": next_action,
        "ready_tasks": state["ready_tasks"],
        "in_progress_tasks": state["in_progress_tasks"],
        "dispatchable_tasks": state["dispatchable_tasks"],
        "blockers": state["explicit_blocked"],
        "blocker_details": blocker_details,
        "dependency_blocked": state["dependency_blocked"],
        "remaining_tasks": state["remaining_tasks"],
        "concurrency": state["concurrency"],
        "task_counts": {
            status: sum(1 for task in tasks if getattr(task, "status", "") == status)
            for status in (
                "pending",
                "in_progress",
                "blocked",
                "needs_review",
                "done",
                "superseded",
            )
        },
        "validation_errors": validation.get("errors", []),
        "validation_warnings": validation.get("warnings", []),
    }
    return payload, return_code


def main() -> int:
    args = build_parser().parse_args()
    plan_dir = plan_dir_from_args(args.plan_dir)

    if args.command == "check":
        payload, return_code = validate_plan_dir(plan_dir)
        print(render_json(payload))
        return return_code

    if args.command == "status":
        payload, return_code = plan_status(plan_dir)
        if args.goal_status:
            blockers = ",".join(payload["blockers"]) or "none"
            ready = ",".join(payload["ready_tasks"]) or "none"
            active = payload["active_task"] or "none"
            counts = payload["task_counts"]
            remaining = sum(
                counts[status]
                for status in ("pending", "in_progress", "blocked", "needs_review")
            )
            total = sum(counts.values())
            print(
                f"goal-status mode={payload['mode']} consistency={payload['consistency']} "
                f"plan_state={payload['plan_state']} host_goal=unmanaged "
                f"active={active} ready={ready} blockers={blockers} "
                f"remaining={remaining}/{total}"
            )
        elif args.as_json:
            print(render_json(payload))
        else:
            print(f"Mode: {payload['mode']}")
            print(f"Consistency: {payload['consistency']}")
            print(f"Plan state: {payload['plan_state']}")
            print("Host Goal: unmanaged")
            print(f"Active task: {payload['active_task'] or 'None'}")
            print(f"Ready tasks: {', '.join(payload['ready_tasks']) or 'None'}")
            print(f"Blockers: {', '.join(payload['blockers']) or 'None'}")
            print(f"Next action: {payload['next_action']}")
        return return_code

    raise AssertionError(f"unhandled command: {args.command}")


if __name__ == "__main__":
    sys.exit(main())
