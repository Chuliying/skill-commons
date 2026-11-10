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
from datetime import datetime
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
    parse_timestamp,
)
from verification_evidence import assess as assess_verification  # noqa: E402
from verification_evidence import assess_approval, scope_check  # noqa: E402
from verification_evidence import EVIDENCE_FILE  # noqa: E402
from verification_evidence import manifest_value  # noqa: E402
import activity  # noqa: E402

# Completed work must carry verification evidence bound to content (D-015). Items
# whose meta was last updated before this date are reported as unbound, not stale,
# so history does not flood attention.
VERIFICATION_SINCE = parse_timestamp("2026-10-30T00:00:00Z")
DELIVERED_STATUSES = {"merged", "deployed"}
VERIFICATION_ATTENTION = {"stale", "failed", "unknown"}
_REGISTRY = json.loads((Path(__file__).resolve().parent.parent / "protocol-registry.json").read_text(encoding="utf-8"))
PLAN_REQUIREMENT = {
    mode: spec["artifacts"]["plan"]["requirement"]
    for mode, spec in _REGISTRY["execution_modes"].items()
}

CHECK_SH = REPO_ROOT / "bootstrap" / "check.sh"
PLANCTL_PY = REPO_ROOT / "plan-sync" / "scripts" / "planctl.py"

SCHEMA_VERSION = 3

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
    script otherwise formats per detected agent). check.sh prefixes each warning
    with a warning glyph; consumer warnings retain their existing classification
    (no warnings -> PASS, stamp drift -> attention, otherwise -> unknown).
    The source checkout runs the same probe: maintainer generated-root,
    ownership-ledger, content, and retired-output warnings are attention, while
    a failed subprocess or an operational health-check warning is unknown.
    """
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

    if proc.returncode != 0:
        return {
            "state": "unknown",
            "warnings": warnings,
            "detail": f"bootstrap check failed (exit status {proc.returncode})",
        }

    if project_root == REPO_ROOT:
        # The source health check is advisory, but a failed expected-payload
        # build/temp allocation is not evidence of a healthy generated tree.
        if any("could not" in warning.lower() for warning in warnings):
            return {
                "state": "unknown",
                "warnings": warnings,
                "detail": "maintainer source health check failed operationally",
            }
        if not warnings:
            return {
                "state": "PASS",
                "warnings": [],
                "detail": "maintainer source health consistent",
            }
        return {
            "state": "attention",
            "warnings": warnings,
            "detail": "maintainer source health requires attention",
        }

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

    Participants are the one exception to "not assessed": a declared `repo:`
    Source is the work item's identity, not its current state, so finished
    cross-repo work stays visible in one place. An unassessed item reports its
    participants and, when one of them cannot be resolved, why — and nothing
    else: no plan state, no active task, no plan-consistency errors. So for an
    unassessed item `errors` carries participant reporting only, which is what
    lets the text renderer surface it without reviving plan assessment.
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
        "participants": [],
        "errors": [],
        "warnings": [],
    }
    if not present:
        return empty
    if not PLANCTL_PY.is_file():
        return empty
    # Retired three-file plans predate the Sources contract and declare no
    # participants, so an unassessed retired plan is not probed at all.
    if not assess and mode != "canonical":
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
        return {**empty, "errors": [str(exc)]} if assess else empty

    payload = {}
    if proc.stdout.strip():
        try:
            payload = json.loads(proc.stdout)
        except json.JSONDecodeError:
            payload = {}
    participants = sorted(payload.get("participants", []))
    participant_errors = sorted(payload.get("participant_errors", []))
    if not assess:
        return {**empty, "participants": participants, "errors": participant_errors}
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
        "participants": participants,
        "errors": sorted(payload.get("validation_errors", [])),
        "warnings": sorted(payload.get("validation_warnings", [])),
    }


# ── work items ────────────────────────────────────────────────────────────


def next_stage(stages: list[dict]) -> dict | None:
    for stage in stages:
        if stage["status"] not in FINISHED_STAGE_STATUSES:
            return {"name": stage["name"], "status": stage["status"]}
    return None


def collect_work_items(work_root: Path, project_root: Path | None = None) -> list[dict]:
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
        # current orientation. A historical canonical plan still yields its
        # declared participants (see probe_plan).
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
        verification = {"state": "n/a"}
        if work_status == "completed" and delivery_status not in DELIVERED_STATUSES:
            try:
                bound = parse_timestamp(str(item.fields.get("updated_at", ""))) >= VERIFICATION_SINCE
            except ValueError:
                bound = True  # An unreadable time must not hide the item as history.
            if bound and project_root is not None:
                verification = assess_verification(project_root, item.path.parent)
            else:
                verification = {"state": "unbound", "detail": "completed before content-bound evidence"}
        elif (work_status == "active" and project_root is not None
              and (item.path.parent / EVIDENCE_FILE).is_file()):
            # Recorded evidence is assessed whatever the work status: an item left active after
            # its run must not hide a change (competitor test rerun 3). No evidence yet is fine.
            verification = assess_verification(project_root, item.path.parent)
        # Every active plan state contributes. An absent or unassessable plan is
        # unknown, not a silent PASS; historical items remain unassessed. One exception
        # (T08): an active item whose mode does not require a plan and whose recorded
        # verification is current has a signal, so the absent plan does not make it unknown.
        if is_active:
            plan_optional = PLAN_REQUIREMENT.get(str(item.fields.get("execution_mode", "")), "required") != "required"
            if not plan["present"] and plan_optional and verification.get("state") not in {"n/a", "unknown"}:
                contrib.append("PASS")
            else:
                contrib.append(plan["state"])
        state = precedence_max(contrib)
        # An approval binds the segments it approved until the item is delivered (T05).
        approval = {"state": "n/a"}
        if work_status != "abandoned" and delivery_status not in DELIVERED_STATUSES:
            approval = assess_approval(item.path.parent)
            # The quote is the agent's claim of the person's words; only the JSON ledger shows it (T11).
            approval = {key: value for key, value in approval.items() if key not in ("quote", "basis")}
        # T12: recomputed at read time like the fingerprint, so a commit after the last run
        # still shows. The list a run recorded is kept to show a later widening.
        scope = None
        if project_root is not None and work_status != "abandoned" and delivery_status not in DELIVERED_STATUSES \
                and work_status in {"active", "completed"}:
            try:
                scope = scope_check(project_root, item.path.parent)
            except (OSError, ValueError):
                scope = {"allowed_paths": [], "range": "unknown", "notes": ["scope could not be checked"], "violations": []}
            if scope is not None:
                try:
                    recorded = json.loads((item.path.parent / EVIDENCE_FILE).read_text()).get("scope") or {}
                except (OSError, ValueError):
                    recorded = {}
                if recorded.get("allowed_paths") and recorded["allowed_paths"] != scope["allowed_paths"]:
                    scope["recorded_allowed_paths"] = recorded["allowed_paths"]
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
                "verification": verification,
                "approval": approval,
                "scope": scope,
            }
        )
    collected.sort(key=lambda entry: entry["slug"])
    # T12: base_commit..HEAD is one range per branch. With more than one scoped item on it
    # (active or completed and undelivered), each item would list the others' commits, so the
    # lists are shown but are not attention on their own.
    scoped = [entry for entry in collected if entry.get("scope")]
    if len(scoped) > 1:
        for entry in scoped:
            entry["scope"]["shared_range"] = True
            entry["scope"].setdefault("notes", []).append(
                "several items with allowed_paths share this branch; the list is shown, not attention")
    mark_covered(collected)
    return collected


def mark_covered(items: list[dict]) -> None:
    """A stale item is covered when newer passing evidence over the same scope is current.
    Covered means the current checks pass on the current content, not that the checks that
    first verified the item still exist. A newer run over fewer files than the item's run
    does not cover it: a deleted test could otherwise hide a broken item. A test weakened
    in place is not detected. Without covered, every earlier completed item would go stale
    as soon as the next task edits a file."""
    current = [
        entry["verification"] for entry in items
        if entry["verification"].get("state") == "current"
    ]
    for entry in items:
        evidence = entry["verification"]
        # Newer code evidence cannot vouch for an edited acceptance segment.
        if evidence.get("state") != "stale" or evidence.get("stale_kind") != "files":
            continue
        for newer in current:
            if newer.get("scope") != evidence.get("scope"):
                continue
            if str(newer.get("recorded_at")) <= str(evidence.get("recorded_at")):
                continue
            if int(newer.get("files") or 0) < int(evidence.get("files") or 0):
                entry["verification"] = {
                    **evidence,
                    "detail": (f"files changed; newer passing evidence ({newer.get('recorded_at')}) "
                               "covers fewer files than this item's run, so it does not cover it"),
                }
                continue
            entry["verification"] = {
                **evidence,
                "state": "covered",
                "detail": f"files changed, but newer passing evidence ({newer.get('recorded_at')}) covers the same scope",
            }
            break


# ── next action ─────────────────────────────────────────────────────────────


def compute_next_action(status: str, ambiguity: dict, focus: dict | None,
                        invalid_sources: list[str], attention_sources: list[str],
                        unknown_sources: list[str], queued: int = 0) -> str:
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
    if focus:
        plan = focus.get("plan") or {}
        plan_action = plan.get("next_action")
        # planctl uses the string sentinel "None" for a plan without an
        # executable task; do not turn that sentinel into a continuation hint.
        if plan_action and plan_action != "None":
            return f"continue {focus['slug']}: {plan_action}"
    if focus and focus.get("next_stage"):
        stage = focus["next_stage"]
        return f"continue {focus['slug']}: {stage['name']} ({stage['status']})"
    if focus and focus.get("no_pending_stage"):
        return (f"no pending stage for {focus['slug']}: advance (add the next stage) "
                f"or close out (complete or abandon the work item)")
    if queued:
        return f"no active work; {queued} queued: start one with work-items.sh start <slug>"
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
    work_items = collect_work_items(work_root, project_root)
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
    # D-015: a completed, undelivered item whose evidence is stale, failed or missing
    # needs attention even though it no longer drives the next stage (D-008).
    verification_attention = sorted(
        [f"{e['slug']} (verification {e['verification']['state']})"
         for e in work_items if e["verification"]["state"] in VERIFICATION_ATTENTION]
        + [f"{e['slug']} (approval {e['approval']['state']})"
           for e in work_items if e["approval"]["state"] in VERIFICATION_ATTENTION]
        # T12: the range check assumes one active item per branch, so with several active
        # items the changes are shown on each item but are not attention on their own.
        + [f"{e['slug']} (scope: {len(e['scope']['violations'])} outside allowed_paths)"
           for e in work_items if (e.get("scope") or {}).get("violations")
           and not e["scope"].get("shared_range") and not multiple_active]
    )
    # Stale history always shows in the status. An active item in focus (an active --slug,
    # or the only active item) keeps the next action, with the verification note appended.
    orienting = focus_is_active or (not multiple_active and len(active_items) == 1)
    verification_state = "attention" if verification_attention else None
    base_states = [wi_probe["state"], bootstrap["state"], ambiguity_state, *item_states]
    overall = precedence_max([*base_states, verification_state])
    orientation_status = precedence_max(base_states) if orienting else overall

    # An unknown --slug is a usage error: force invalid rather than report PASS.
    if slug_error:
        overall = orientation_status = "invalid"

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
    if not orienting:
        attention_sources += verification_attention
    attention_sources = sorted(set(attention_sources))
    unknown_sources = sorted(set(
        (["bootstrap"] if bootstrap["state"] == "unknown" else [])
        + [e["slug"] for e in scoped_items if e and e["state"] == "unknown"]
    ))

    focus = selected if focus_is_active else (active_items[0] if len(active_items) == 1 else None)
    next_action = compute_next_action(
        orientation_status, ambiguity, focus,
        invalid_sources, attention_sources, unknown_sources,
        queued=0 if active_items else sum(1 for e in work_items if e["work_status"] == "queued"),
    )
    if orienting and verification_attention:
        next_action += f"; verification needs attention: {', '.join(verification_attention)}"

    # Shown state only, after orientation is decided: an item whose verification or approval
    # needs attention is not PASS on its own line either (competitor test round 2:
    # `state=PASS` next to `verify=stale` read as done). It is already in the status above.
    for entry in work_items:
        if (entry["verification"].get("state") in VERIFICATION_ATTENTION
                or entry["approval"].get("state") in VERIFICATION_ATTENTION
                or ((entry.get("scope") or {}).get("violations")
                    and not entry["scope"].get("shared_range") and not multiple_active)):
            entry["state"] = precedence_max([entry["state"], "attention"])

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
        "verification_attention": verification_attention,
        "next_action": next_action,
    }
    if slug_error:
        payload["slug_error"] = slug_error
    exit_code = 2 if slug_error else 0
    return payload, exit_code


# ── ledger ──────────────────────────────────────────────────────────────────

LEDGER_STAGE_ORDER = ["prd", "spec", "qa-plan", "plan", "implement", "qa-report"]


def ledger_rows(payload: dict, work_root: Path, project_root: Path) -> list[dict]:
    """One row per work item (T08): state, stage files, last verification and approval, and
    the AI tools and sessions recorded in activity.jsonl. Read-only; ignores --slug."""
    test_cmd = manifest_value(project_root, "test_cmd") or None
    rows = []
    for entry in payload["work_items"]:
        item_dir = work_root / entry["slug"]
        stages = {stage["name"]: stage for stage in entry["stages"]}
        mode = ""
        meta = item_dir / "meta.yml"
        if meta.is_file():
            for line in meta.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("execution_mode:"):
                    mode = line.split(":", 1)[1].strip()
        qa_plan = _REGISTRY["execution_modes"].get(mode, {}).get("artifacts", {}).get("qa-plan", {}).get("requirement")
        verification = entry["verification"]
        approval = entry["approval"]
        title = None
        if meta.is_file():
            for line in meta.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("title:"):
                    title = line.split(":", 1)[1].strip() or None
        evidence = {}
        try:
            evidence = json.loads((item_dir / EVIDENCE_FILE).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            evidence = {}
        duration = None
        try:
            duration = round((datetime.fromisoformat(str(evidence["recorded_at"]))
                              - datetime.fromisoformat(str(evidence["started_at"]))).total_seconds(), 1)
        except (KeyError, ValueError, TypeError):
            duration = None
        rows.append({
            "slug": entry["slug"],
            "title": title,
            "next_stage": entry.get("next_stage"),
            "mode": mode or None,
            "work_status": entry["work_status"],
            "delivery_status": entry["delivery_status"],
            "state": entry["state"],
            "error": (entry["meta_errors"] or [None])[0],
            "stages": [
                {"name": name, "status": stages[name]["status"], "file": stages[name]["file"],
                 "present": (item_dir / stages[name]["file"]).is_file()}
                for name in [*LEDGER_STAGE_ORDER, *sorted(set(stages) - set(LEDGER_STAGE_ORDER))]
                if name in stages
            ],
            "test_cases": ("n/a (mode has no QA stage)" if qa_plan == "absent" else
                           ("qa-plan" if "qa-plan" in stages else "missing")),
            "test_cmd": test_cmd,
            "verification": {key: verification.get(key) for key in ("state", "recorded_at", "command", "detail")}
                            | {"started_at": evidence.get("started_at"), "duration_seconds": duration},
            "scope": entry.get("scope"),
            "approval": {key: approval.get(key) for key in ("state", "by", "approved_at", "confirmation")}
                        | (_agent_claim(item_dir) if approval.get("state") not in (None, "n/a") else {}),
            "activity": activity.summarize(item_dir),
        })
    return rows


def _agent_claim(item_dir: Path) -> dict:
    """What an agent-reported approval says the person said, labeled as the agent's claim."""
    if not (item_dir / "approval.json").is_file():
        return {}
    claim = assess_approval(item_dir)
    return {key: claim[key] for key in ("quote", "basis") if claim.get(key)} and {
        "agent_reported_claim": {key: claim[key] for key in ("quote", "basis") if claim.get(key)}}


def orphan_folders(work_root: Path) -> int:
    if not work_root.is_dir():
        return 0
    return sum(1 for child in work_root.iterdir()
               if child.is_dir() and child.name != "_archive" and not child.name.startswith(".")
               and not (child / "meta.yml").is_file())


def _scope_note(scope: dict | None) -> str:
    """` scope=...` for the status line: the first three paths outside allowed_paths and the
    total, a widened list, or `ok`."""
    if not scope:
        return ""
    violations = scope.get("violations") or []
    note = " scope=ok" if not violations else (
        f" scope={len(violations)} outside allowed_paths: {', '.join(violations[:3])}"
        + (f" and {len(violations) - 3} more" if len(violations) > 3 else ""))
    if scope.get("recorded_allowed_paths"):
        note += f" (allowed_paths changed since the last run: was {', '.join(scope['recorded_allowed_paths'])})"
    for text in scope.get("notes") or []:
        note += f" ({text})"
    return note


def _short_time(value: object) -> str:
    text = str(value or "")
    return text[:16].replace("T", " ") if text else "-"


def _stage_marks(row: dict) -> str:
    return ", ".join(
        f"{stage['name']}={stage['status']} ({stage['file']}" + ("" if stage["present"] else ", missing") + ")"
        for stage in row["stages"]
    ) or "-"


def _last(row: dict) -> str:
    last = row["activity"].get("last")
    if not last:
        return "-" if not row["activity"]["present"] else "unreadable"
    sessions = ", ".join(str(session)[:12] for session in last.get("sessions") or [])
    return f"{last['event']} {_short_time(last['at'])} by {last['tools']}" + (f" ({sessions})" if sessions else "")


def render_ledger_text(rows: list[dict], omitted: int = 0) -> str:
    lines = [f"ledger: {len(rows)} work item(s)"
             + (f"; omitted: {omitted} folder(s) without meta.yml" if omitted else "")]
    for row in rows:
        verification = row["verification"]
        approval = row["approval"]
        stage = row.get("next_stage") or {}
        lines.append(
            f"- {row['slug']} [{row['work_status']}/{row['delivery_status']}] state={row['state']}"
            + (f" error={row['error']}" if row["error"] else "")
            + (f" — {row['title']}" if row.get("title") else "")
            + (f"; next stage: {stage['name']} ({stage['status']})" if stage.get("name") else "")
        )
        lines.append(f"    stages: {_stage_marks(row)}; test cases: {row['test_cases']}"
                     + (f";{_scope_note(row['scope'])}" if row.get("scope") else ""))
        lines.append(
            f"    verify: {verification.get('state') or 'n/a'} {_short_time(verification.get('recorded_at'))}"
            + (f" ({verification['duration_seconds']}s)" if verification.get("duration_seconds") is not None else "")
            + f"; approval: {approval.get('state') or 'n/a'}"
            + (f" by {approval['by']} ({approval.get('confirmation')}) {_short_time(approval.get('approved_at'))}"
               if approval.get("by") else "")
        )
        sessions = len(row["activity"]["sessions"])
        unreadable = row["activity"]["unreadable"]
        lines.append(
            f"    last: {_last(row)}; sessions: {sessions}"
            + (f"; unreadable activity lines: {unreadable} (try `{activity.MERGE_HINT}` in .gitattributes)" if unreadable else "")
        )
    return "\n".join(lines)


def render_ledger_markdown(rows: list[dict], omitted: int = 0) -> str:
    lines = [*([f"_omitted: {omitted} folder(s) without meta.yml_", ""] if omitted else []),
        "| Item | Status | State | Stages | Verification | Approval | Last activity | Sessions |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        verification = row["verification"]
        approval = row["approval"]
        cells = [
            f"`{row['slug']}`",
            f"{row['work_status']} / {row['delivery_status']}",
            row["state"] + (f" ({row['error']})" if row["error"] else ""),
            _stage_marks(row),
            f"{verification.get('state') or 'n/a'} {_short_time(verification.get('recorded_at'))}",
            (approval.get("state") or "n/a")
            + (f" by {approval['by']} ({approval.get('confirmation')})" if approval.get("by") else ""),
            _last(row),
            str(len(row["activity"]["sessions"])),
        ]
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in cells) + " |")
    return "\n".join(lines)


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
        participants = plan.get("participants") or []
        participant_note = (
            f" participants={','.join(participants)}" if participants else ""
        )
        lines.append(
            f"  - {entry['slug']} [work={entry['work_status']} delivery={entry['delivery_status']}] "
            f"state={entry['state']} "
            f"plan={plan_note} next_stage={stage_note}{participant_note}"
            + (f" verify={entry['verification']['state']}" if entry["verification"]["state"] != "n/a" else "")
            + (f" approval={entry['approval']['state']}"
               + (f"({entry['approval']['confirmation']})" if entry["approval"].get("confirmation") else "")
               if entry["approval"]["state"] != "n/a" else "")
            + (f" reaffirmed={reaffirmed}" if (reaffirmed := (entry["verification"].get("reaffirmed") or 0)
                                                + (entry["approval"].get("reaffirmed") or 0)) else "")
            + _scope_note(entry.get("scope"))
        )
        # An unassessed item's errors are participant reporting only (see
        # probe_plan), so surfacing them here cannot leak plan assessment into
        # history. Assessed items already report through state and next_action.
        if not plan.get("assessed"):
            for message in plan.get("errors") or []:
                lines.append(f"    attention: {message}")
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
    parser.add_argument("--ledger", action="store_true",
                        help="one row per work item: stages, verification, approval, AI tools and sessions")
    parser.add_argument("--markdown", action="store_true", help="with --ledger, a Markdown table for handoff notes")
    parser.add_argument("--strict", action="store_true",
                        help="exit 3 when completed work has stale, failed or missing verification evidence")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.markdown and not args.ledger:
        parser.error("--markdown needs --ledger")
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
    payload, exit_code = build_payload(work_root, project_root, None if args.ledger else args.slug)
    if args.ledger:
        rows = ledger_rows(payload, work_root, project_root)
        omitted = orphan_folders(work_root)
        if args.slug:
            print("note: --ledger lists every work item; --slug is ignored", file=sys.stderr)
        if args.json:
            print(json.dumps({"schema_version": SCHEMA_VERSION, "ledger": rows, "omitted_folders": omitted},
                             ensure_ascii=True, indent=2))
        elif args.markdown:
            print(render_ledger_markdown(rows, omitted))
        else:
            print(render_ledger_text(rows, omitted))
        if exit_code == 0 and args.strict and payload["verification_attention"]:
            return 3
        return exit_code
    if args.json:
        print(render_json(payload))
    else:
        print(render_text(payload))
    if exit_code == 2 and "slug_error" in payload:
        print(payload["slug_error"], file=sys.stderr)
    if exit_code == 0 and args.strict and payload["verification_attention"]:
        return 3
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
