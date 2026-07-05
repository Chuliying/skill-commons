#!/usr/bin/env python3
"""Deterministically grade a real-agent journey workspace."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


def command_ok(workspace: Path, *args: str) -> bool:
    return subprocess.run(args, cwd=workspace, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def contains(path: Path, token: str) -> bool:
    return path.is_file() and token in path.read_text(encoding="utf-8", errors="replace")


def contains_match(path: Path, pattern: str) -> bool:
    return path.is_file() and re.search(pattern, path.read_text(encoding="utf-8", errors="replace")) is not None


def evidence_line_pattern(label: str) -> str:
    return rf"(?im)^\s*(?:[-*]\s*)?{label}"


def strip_record_marker(line: str) -> str:
    return re.sub(r"^\s*[-*]\s*", "", line.strip())


def skills_read_line(path: Path) -> str:
    if not path.is_file():
        return ""
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        record = strip_record_marker(line)
        if record.lower().startswith("skills read:"):
            return record.split(":", 1)[1]
    return ""


def skill_was_read(path: Path, skill_name: str) -> bool:
    line = skills_read_line(path)
    pattern = rf"(?<![A-Za-z0-9_-]){re.escape(skill_name)}(?![A-Za-z0-9_-])"
    return re.search(pattern, line) is not None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    root = args.workspace.resolve()
    scenario = args.scenario
    checks: dict[str, bool] = {}

    checks["tests_pass"] = command_ok(root, "python3", "-m", "unittest", "discover", "-s", "tests")

    work_slug = {
        "personal-feature": "personal-feature",
        "team-feature": "team-feature",
        "brownfield-bug": "brownfield-bug",
        "refactor": "refactor",
        "commit-pr": "ship-ready",
    }[scenario]
    work = root / "docs/work" / work_slug
    report = work / "implement-report.md"
    checks["implement_report"] = report.is_file()
    checks["router_read"] = skill_was_read(report, "skill-router")
    checks["meta_exists"] = (work / "meta.yml").is_file()

    if scenario == "personal-feature":
        checks["feature_behavior"] = command_ok(
            root,
            "python3",
            "-c",
            (
                "from src.greet import greet; "
                "assert greet('Codex') == 'hello Codex'; "
                "assert greet('Codex', '!') == 'hello Codex!'"
            ),
        )
        checks["lightweight_fallback"] = not any((work / name).exists() for name in ("prd.md", "spec.md", "qa-plan.md"))
        checks["implement_read"] = skill_was_read(report, "implement")
    elif scenario == "team-feature":
        required = (
            "prd.md",
            "spec.md",
            "qa-plan.md",
            "plan/implementation.md",
            "plan/tasks.md",
            "plan/notes.md",
            "implement-report.md",
            "qa-report.md",
        )
        checks["formal_artifacts"] = all((work / name).is_file() for name in required)
        checks["feature_behavior"] = command_ok(
            root,
            "python3",
            "-c",
            (
                "from src.greet import greet; "
                "assert greet('Codex') == 'hello Codex'; "
                "assert greet('Codex', prefix='welcome') == 'welcome Codex'"
            ),
        )
        checks["capability_na"] = contains(work / "spec.md", "has_ui") and contains(work / "spec.md", "N/A")
        checks["team_skills_read"] = (
            any(skill_was_read(report, name) for name in ("prd-interview", "to-prd"))
            and all(skill_was_read(report, name) for name in ("spec", "qa", "plan-sync", "implement"))
        )
    elif scenario == "brownfield-bug":
        checks["bug_fixed"] = contains(root / "src/greet.py", ".strip()")
        checks["bug_fallback"] = not any((work / name).exists() for name in ("prd.md", "spec.md", "qa-plan.md"))
        checks["debug_skills_read"] = all(
            skill_was_read(report, name) for name in ("systematic-debugging", "implement")
        )
    elif scenario == "refactor":
        source = (root / "src/greet.py").read_text(encoding="utf-8", errors="replace")
        checks["refactored_once"] = "def _normalize_name" in source and source.count(".strip().title()") == 1
        checks["intent_artifact"] = (work / "prd.md").is_file()
        checks["no_qa_ceremony"] = not (work / "qa-plan.md").exists()
        checks["refactor_skills_read"] = all(skill_was_read(report, name) for name in ("to-prd", "implement"))
    elif scenario == "commit-pr":
        commit_count = subprocess.run(
            ["git", "rev-list", "--count", "HEAD"], cwd=root, capture_output=True, text=True, check=False
        ).stdout.strip()
        remotes = subprocess.run(
            ["git", "remote"], cwd=root, capture_output=True, text=True, check=False
        ).stdout.strip()
        checks["local_commit_created"] = commit_count.isdigit() and int(commit_count) >= 2
        checks["no_remote_added"] = remotes == ""
        checks["work_item_shipped"] = contains(work / "meta.yml", "status: shipped")
        checks["delivery_recorded"] = contains(work / "prd.md", "## Delivery")
        checks["pr_fallback"] = contains(report, "PR: blocked (no remote)")
        checks["verification_recorded"] = contains_match(
            report,
            evidence_line_pattern(r"Verification:\s*PASS\b"),
        )
        checks["review_recorded"] = contains_match(
            report,
            evidence_line_pattern(r"(?:Review|Code review):\s*(?:PASS|no findings|findings resolved)\b"),
        )
        checks["security_recorded"] = contains_match(
            report,
            evidence_line_pattern(r"Security:\s*PASS\b"),
        )
        checks["ship_skills_read"] = all(
            skill_was_read(report, name)
            for name in ("verification-before-completion", "caveman-review", "security", "finishing-a-development-branch")
        )

    payload = {
        "scenario": scenario,
        "pass": all(checks.values()),
        "checks": checks,
        "failed": [name for name, passed in checks.items() if not passed],
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
