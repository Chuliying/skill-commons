#!/usr/bin/env python3
"""project-status (M1 / FR-001): read-only, deterministic, no-LLM state entry.

Aggregates bootstrap health, work-item metadata validity, active-plan
consistency, the git working tree, and multi-active ambiguity into a single
four-state judgment (PASS / attention / unknown / invalid) plus a rule-based
next action.

Design (see docs/work/project-status/spec.md):
- Reuse, do not rewrite parsers: `work_items` is imported for structured items;
  `planctl.py` and `bootstrap/check.sh` are invoked as subprocesses.
- Output carries no wall-clock, no absolute paths, and every list is sorted, so
  the same inputs always produce byte-identical output (AC-001).
- Four states aggregate by fixed precedence invalid > attention > unknown > PASS.
  M1 feeds work-items/plan/bootstrap/ambiguity; M2's baseline probe plugs into
  the same aggregator without changing it.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# project_status.py lives in <repo>/scripts, next to work_items.py.
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
# Read-only command: never leave __pycache__ residue from the work_items import.
sys.dont_write_bytecode = True
sys.path.insert(0, str(SCRIPT_DIR))

from work_items import (  # noqa: E402  (path set above)
    load_items,
    normalized_delivery_status,
    normalized_work_status,
)

CHECK_SH = REPO_ROOT / "bootstrap" / "check.sh"
PLANCTL_PY = REPO_ROOT / "plan-sync" / "scripts" / "planctl.py"

SCHEMA_VERSION = 2

# Fixed four-state precedence. Higher wins.
PRECEDENCE = {"invalid": 3, "attention": 2, "unknown": 1, "PASS": 0}

# Stage statuses that need no further agent action. `ready` means the stage's
# artifact is produced (done for work purposes) and is terminal for orientation;
# treating it as pending caused a false "continue plan" on `plan: ready`.
FINISHED_STAGE_STATUSES = {"ready", "approved", "done", "validated", "skipped", "superseded"}


def precedence_max(states: list[str | None]) -> str:
    """Return the highest-precedence state, ignoring None. Empty -> PASS."""
    present = [s for s in states if s]
    if not present:
        return "PASS"
    return max(present, key=lambda s: PRECEDENCE[s])


# ── probes ──────────────────────────────────────────────────────────────────


def probe_bootstrap(project_root: Path) -> dict:
    """Harvest bootstrap health from bootstrap/check.sh.

    Pin --platform text so the output format is environment-independent (the
    script otherwise formats per detected agent). check.sh always exits 0 and
    prefixes each warning with a warning glyph; we classify by content:
    no warnings -> PASS, stamp drift -> attention, otherwise -> unknown
    (not onboarded / not applicable, per the "don't force attention" rule).

    The skill-commons source repo itself is not a consuming repo, so its
    bootstrap is N/A -> unknown (not a silent PASS); check.sh separately exempts
    it from the session-hook nag.
    """
    if project_root == REPO_ROOT:
        return {"state": "unknown", "warnings": [],
                "detail": "skill-commons source repo (bootstrap N/A — not a consuming repo)"}
    if not CHECK_SH.is_file():
        return {"state": "unknown", "warnings": [], "detail": "bootstrap/check.sh not found"}
    try:
        proc = subprocess.run(
            ["bash", str(CHECK_SH), "--platform", "text", "--project-root", str(project_root)],
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        return {"state": "unknown", "warnings": [], "detail": f"bootstrap check failed: {exc}"}

    warnings = []
    for line in proc.stdout.splitlines():
        if "⚠" in line:  # ⚠ warning marker
            warnings.append(line.split("⚠", 1)[1].lstrip("️").strip())

    if not warnings:
        state = "PASS"
        detail = "bootstrap configuration consistent"
    elif any("≠" in w for w in warnings):
        state = "attention"
        detail = "bootstrap configuration is stale (stamp drift)"
    else:
        state = "unknown"
        detail = "bootstrap not configured for this project root"
    return {"state": state, "warnings": warnings, "detail": detail}


def probe_git(project_root: Path) -> dict:
    """Report the git working tree. Informational only (not in precedence)."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(project_root), "--no-optional-locks", "status", "--porcelain"],
            capture_output=True,
            text=True,
        )
    except OSError:
        return {"tracked": False, "clean": True, "changed_files": 0}
    if proc.returncode != 0:
        return {"tracked": False, "clean": True, "changed_files": 0}
    changed = [line for line in proc.stdout.splitlines() if line.strip()]
    return {"tracked": True, "clean": not changed, "changed_files": len(changed)}


def probe_plan(item_dir: Path, assess: bool = True) -> dict:
    """Assess canonical-v2 plan state through planctl.

    Historical completed/abandoned items are detected but not assessed, so a
    stale historical plan cannot change current orientation. Consistent blocked
    plans contribute attention; invalid plans contribute invalid.
    """
    plan_dir = item_dir / "plan"
    canonical = plan_dir / "plan.md"
    retired = [plan_dir / name for name in ("implementation.md", "tasks.md", "notes.md")]
    present = canonical.is_file() or any(path.is_file() for path in retired)
    mode = "canonical" if canonical.is_file() else ("retired" if present else "none")
    empty = {
        "present": present,
        "mode": mode,
        "state": "unknown",
        "assessed": False,
        "consistency": "unknown",
        "plan_state": "unknown",
        "active_task": None,
        "next_action": None,
        "errors": [],
        "warnings": [],
    }
    if not present:
        return empty
    if not assess or not PLANCTL_PY.is_file():
        return empty
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(PLANCTL_PY),
                "status",
                "--plan-dir",
                str(plan_dir),
                "--json",
            ],
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        return {**empty, "errors": [str(exc)]}

    payload = {}
    if proc.stdout.strip():
        try:
            payload = json.loads(proc.stdout)
        except json.JSONDecodeError:
            payload = {}
    consistency = str(payload.get("consistency", "unknown"))
    plan_state = str(payload.get("plan_state", "unknown"))
    if proc.returncode == 0 and consistency == "PASS":
        state = "attention" if plan_state == "blocked" else "PASS"
    elif consistency == "FAIL" or proc.returncode == 2:
        state = "invalid"
    else:
        state = "unknown"
    return {
        "present": True,
        "mode": mode,
        "state": state,
        "assessed": True,
        "consistency": consistency,
        "plan_state": plan_state,
        "active_task": payload.get("active_task"),
        "next_action": payload.get("next_action"),
        "errors": sorted(payload.get("validation_errors", [])),
        "warnings": sorted(payload.get("validation_warnings", [])),
    }


# ── work items ────────────────────────────────────────────────────────────


def next_stage(stages: list[dict]) -> dict | None:
    for stage in stages:
        if stage["status"] not in FINISHED_STAGE_STATUSES:
            return {"name": stage["name"], "status": stage["status"]}
    return None


def collect_work_items(work_root: Path) -> list[dict]:
    """Structured, slug-sorted view of every work item under work_root."""
    collected = []
    if not work_root.is_dir():
        return collected
    for item, errors in load_items(work_root):
        slug = item.fields.get("slug", item.path.parent.name)
        work_status = normalized_work_status(item)
        delivery_status = normalized_delivery_status(item)
        is_active = work_status == "active"
        stages = [
            {"name": s.name, "skill": s.skill, "file": s.file, "status": s.status}
            for s in item.stages
        ]
        meta_valid = not errors
        # Only assess plans for active items — historical plans must not affect
        # current orientation.
        plan = probe_plan(item.path.parent, assess=is_active)
        next_stg = next_stage(stages)
        # Active with no pending stage: meta has no stage that needs work.
        # Whether it is "delivered" cannot be inferred from stages (the next
        # stage may simply not be appended yet, and `implement: done` alone is
        # not release evidence for a team flow), so it is reported neutrally as
        # "advance or close out", never as "delivery complete". It is an action,
        # not a health problem, so it does not inflate the four-state.
        no_pending_stage = is_active and next_stg is None
        contrib = ["invalid" if not meta_valid else "PASS"]
        # Every active plan state contributes. An absent or unassessable plan is
        # unknown, not a silent PASS; historical items remain unassessed below.
        if is_active:
            contrib.append(plan["state"])
        state = precedence_max(contrib)
        collected.append(
            {
                "slug": slug,
                "work_status": work_status,
                "delivery_status": delivery_status,
                "state": state,
                "meta_valid": meta_valid,
                "meta_errors": sorted(errors),
                "stages": stages,
                "plan": plan,
                "no_pending_stage": no_pending_stage,
                "next_stage": next_stg,
            }
        )
    collected.sort(key=lambda entry: entry["slug"])
    return collected


# ── next action ─────────────────────────────────────────────────────────────


def compute_next_action(status: str, ambiguity: dict, focus: dict | None,
                        invalid_sources: list[str], attention_sources: list[str],
                        unknown_sources: list[str]) -> str:
    if status == "invalid":
        return f"resolve invalid: {', '.join(invalid_sources)}"
    if ambiguity["multiple_active"]:
        first = ambiguity["active_slugs"][0]
        return f"multiple active work items; re-run with --slug {first}"
    # Blocking / uncertain states are decided BEFORE any action hint — never tell
    # the agent to continue or close out on top of an attention/unknown condition.
    if status == "attention":
        return f"review attention: {', '.join(attention_sources)}"
    if status == "unknown":
        return f"insufficient signal (unknown): {', '.join(unknown_sources)}"
    if focus and focus.get("next_stage"):
        stage = focus["next_stage"]
        return f"continue {focus['slug']}: {stage['name']} ({stage['status']})"
    if focus and focus.get("no_pending_stage"):
        return (f"no pending stage for {focus['slug']}: advance (add the next stage) "
                f"or close out (complete or abandon the work item)")
    return "no pending action; project state is PASS"


# ── assembly ──────────────────────────────────────────────────────────────


def relativize(path: Path, base: Path) -> str:
    try:
        rel = path.relative_to(base)
        return str(rel)
    except ValueError:
        return str(path)


def strip_root(text: str, project_root: Path) -> str:
    """Normalize absolute project-root paths to relative, so probe-sourced
    strings never leak machine/tmp paths into the output (D-006/D-007)."""
    root = str(project_root)
    return text.replace(root + "/", "").replace(root, ".")


def build_payload(work_root: Path, project_root: Path, slug: str | None) -> tuple[dict, int]:
    work_items = collect_work_items(work_root)
    by_slug = {entry["slug"]: entry for entry in work_items}

    active_items = [e for e in work_items if e["work_status"] == "active"]
    active_slugs = sorted(e["slug"] for e in active_items)
    selected = None
    slug_error = None
    if slug is not None:
        selected = by_slug.get(slug)
        if selected is None:
            slug_error = f"--slug '{slug}' does not match any work item under {relativize(work_root, project_root)}"
        elif selected.get("work_status") != "active":
            slug_error = (f"--slug '{slug}' is {selected['work_status']} (not active); project-status "
                          f"orients on active work — use scripts/work-items.sh to inspect history")

    # Only an ACTIVE --slug selection resolves orientation. Selecting a
    # Completed/abandoned history must not clear ambiguity
    # among active work items (D-008).
    focus_is_active = selected is not None and selected.get("work_status") == "active"
    multiple_active = not focus_is_active and len(active_slugs) > 1
    ambiguity = {
        "multiple_active": multiple_active,
        "active_slugs": active_slugs,
        "hint": "specify --slug <slug>" if multiple_active else None,
    }

    # State-contributing probes.
    invalid_items = sorted(e["slug"] for e in work_items if not e["meta_valid"])
    wi_probe = {
        "state": "invalid" if invalid_items else "PASS",
        "total": len(work_items),
        "invalid_slugs": invalid_items,
        "detail": f"{len(work_items) - len(invalid_items)}/{len(work_items)} meta valid",
    }
    bootstrap = probe_bootstrap(project_root)
    git = probe_git(project_root)

    # Normalize absolute paths out of every probe-sourced string (D-006/D-007).
    bootstrap["warnings"] = [strip_root(w, project_root) for w in bootstrap["warnings"]]
    bootstrap["detail"] = strip_root(bootstrap["detail"], project_root)
    for entry in work_items:
        entry["meta_errors"] = [strip_root(x, project_root) for x in entry["meta_errors"]]
        entry["plan"]["errors"] = [strip_root(x, project_root) for x in entry["plan"]["errors"]]
        entry["plan"]["warnings"] = [strip_root(x, project_root) for x in entry["plan"]["warnings"]]

    # Orientation is scoped to active items (or an active --slug selection);
    # Completed/abandoned items are listed but never drive status or next action.
    scoped_items = [selected] if focus_is_active else active_items
    item_states = [e["state"] for e in scoped_items if e]

    ambiguity_state = "attention" if multiple_active else None
    overall = precedence_max(
        [wi_probe["state"], bootstrap["state"], ambiguity_state, *item_states]
    )

    # An unknown --slug is a usage error: force invalid rather than report PASS.
    if slug_error:
        overall = "invalid"

    # Reason sources for next_action, per state, sorted & deduped.
    invalid_sources = sorted(set(
        invalid_items
        + ([f"slug:{slug}"] if slug_error else [])
        + [e["slug"] for e in scoped_items if e and e["plan"]["state"] == "invalid"]
    ))
    attention_sources = []
    if multiple_active:
        attention_sources.append("ambiguity")
    if bootstrap["state"] == "attention":
        attention_sources.append("bootstrap")
    attention_sources += [e["slug"] for e in scoped_items if e and e["plan"]["state"] == "attention"]
    attention_sources = sorted(set(attention_sources))
    unknown_sources = sorted(set(
        (["bootstrap"] if bootstrap["state"] == "unknown" else [])
        + [e["slug"] for e in scoped_items if e and e["state"] == "unknown"]
    ))

    focus = selected if focus_is_active else (active_items[0] if len(active_items) == 1 else None)
    next_action = compute_next_action(
        overall, ambiguity, focus,
        invalid_sources, attention_sources, unknown_sources,
    )

    payload = {
        "schema_version": SCHEMA_VERSION,
        "status": overall,
        "selected_slug": selected["slug"] if selected else None,
        "work_root": relativize(work_root, project_root),
        "ambiguity": ambiguity,
        "probes": {
            "bootstrap": bootstrap,
            "work_items": wi_probe,
            "git": git,
        },
        "work_items": work_items,
        "next_action": next_action,
    }
    if slug_error:
        payload["slug_error"] = slug_error
    exit_code = 2 if slug_error else 0
    return payload, exit_code


# ── rendering ─────────────────────────────────────────────────────────────


def render_json(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=False)


def render_text(payload: dict) -> str:
    lines = [
        f"status: {payload['status']}",
        f"work_root: {payload['work_root']}",
        f"selected: {payload['selected_slug'] or '(none)'}",
    ]
    amb = payload["ambiguity"]
    if amb["multiple_active"]:
        lines.append(f"ambiguity: multiple active [{', '.join(amb['active_slugs'])}] — {amb['hint']}")
    boot = payload["probes"]["bootstrap"]
    wi = payload["probes"]["work_items"]
    git = payload["probes"]["git"]
    lines.append(f"bootstrap: {boot['state']} ({boot['detail']})")
    lines.append(f"work-items: {wi['state']} ({wi['detail']})")
    if git["tracked"]:
        tree = "clean" if git["clean"] else f"{git['changed_files']} changed"
        lines.append(f"git: {tree}")
    else:
        lines.append("git: (not a tracked repo)")
    lines.append("items:")
    for entry in payload["work_items"]:
        plan = entry["plan"]
        plan_note = plan["mode"] if plan["present"] else "no-plan"
        stage = entry["next_stage"]
        if stage:
            stage_note = f"{stage['name']}:{stage['status']}"
        elif entry.get("no_pending_stage"):
            stage_note = "no-pending-stage"
        else:
            stage_note = "-"
        lines.append(
            f"  - {entry['slug']} [work={entry['work_status']} delivery={entry['delivery_status']}] "
            f"state={entry['state']} "
            f"plan={plan_note} next_stage={stage_note}"
        )
    lines.append(f"next_action: {payload['next_action']}")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Deterministic, read-only project-state entry (M1 / FR-001)."
    )
    parser.add_argument("--work-root", type=Path, default=None,
                        help="work-item root (default: <project-root>/docs/work)")
    parser.add_argument("--project-root", type=Path, default=Path("."),
                        help="repo root used for the git and bootstrap probes")
    parser.add_argument("--slug", help="focus on a single work item (resolves multi-active ambiguity)")
    parser.add_argument("--json", action="store_true", help="emit the JSON contract instead of text")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    project_root = args.project_root.expanduser().resolve()
    if args.work_root is not None:
        work_root = args.work_root.expanduser().resolve()
    else:
        work_root = (project_root / "docs" / "work").resolve()
    if args.work_root is not None and not work_root.is_dir():
        print("work root does not exist (explicit --work-root)", file=sys.stderr)
        return 2
    try:
        work_root.relative_to(project_root)
    except ValueError:
        print("work root must be inside project root", file=sys.stderr)
        return 2
    payload, exit_code = build_payload(work_root, project_root, args.slug)
    if args.json:
        print(render_json(payload))
    else:
        print(render_text(payload))
    if exit_code == 2 and "slug_error" in payload:
        print(payload["slug_error"], file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
