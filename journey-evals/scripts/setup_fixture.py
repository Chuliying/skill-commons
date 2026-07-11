#!/usr/bin/env python3
"""Create one isolated real-agent journey repository."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


SCENARIOS = {
    "personal-feature": "personal",
    "team-feature": "team-sprint",
    "brownfield-bug": "personal",
    "refactor": "personal",
    "commit-pr": "team-sprint",
}


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    subprocess.run(args, cwd=cwd, env=env, check=True, stdout=subprocess.DEVNULL)


def manifest(delivery_mode: str) -> str:
    return f"""
# Project Manifest

## skill-commons bootstrap
- platforms: claude-code, codex
- delivery_mode: {delivery_mode}
- capability_packs:

## Core Documents
- guardrails: .agent/guardrails.md
- system_context: .agent/knowledge/system-context.md
- architecture_map: .agent/knowledge/architecture-map.md

## Paths
- source_roots: src
- tests_root: tests
- test_glob: tests/test_*.py
- work_root: docs/work
- docs_root: docs

## Stack
- framework: python-cli
- package_manager: python
- source_extensions: py
- test_cmd: PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests
- lint_cmd: PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile src/greet.py tests/test_greet.py
- has_ui: false
- has_api: false
- typed_contracts: false
- has_e2e: false

## Git Workflow
- base_branch: main
- remote: origin
- integration_flow: pull-request
- sprint_tracking: false
"""


def configure_scenario(scenario: str, dest: Path) -> None:
    if scenario == "brownfield-bug":
        write(
            dest / "tests/test_greet.py",
            """
import unittest
from src.greet import greet

class GreetTest(unittest.TestCase):
    def test_plain_name(self) -> None:
        self.assertEqual("hello Codex", greet("Codex"))

    def test_surrounding_whitespace(self) -> None:
        self.assertEqual("hello Codex", greet("  Codex  "))

if __name__ == "__main__":
    unittest.main()
""",
        )
    elif scenario == "refactor":
        write(
            dest / "src/greet.py",
            """
def greet(name: str) -> str:
    normalized = name.strip().title()
    return f"hello {normalized}"

def farewell(name: str) -> str:
    normalized = name.strip().title()
    return f"goodbye {normalized}"
""",
        )
        write(
            dest / "tests/test_greet.py",
            """
import unittest
from src.greet import farewell, greet

class GreetTest(unittest.TestCase):
    def test_greet_characterization(self) -> None:
        self.assertEqual("hello Codex", greet(" codex "))

    def test_farewell_characterization(self) -> None:
        self.assertEqual("goodbye Codex", farewell(" codex "))

if __name__ == "__main__":
    unittest.main()
""",
        )
    elif scenario == "commit-pr":
        work = dest / "docs/work/ship-ready"
        write(work / "prd.md", "# Ship-ready PRD\n\nAC-001: greet returns the documented message.")
        write(work / "spec.md", "# Spec\n\nImplement the documented greeting contract.")
        write(work / "qa-plan.md", "# QA Plan\n\nVerify AC-001 with the fixture test suite.")
        write(work / "plan/plan.md", "# Plan\n\nExecute verification and prepare release closeout.")
        write(work / "qa-report.md", "# QA Report\n\nAC-001: PASS")
        write(work / "implement-report.md", "# Implement Report\n\nTests: PASS")
        write(
            work / "meta.yml",
            """
schema_version: work-item/v3
slug: ship-ready
title: Ship-ready greeting
created_at: 2026-07-04T00:00:00+08:00
updated_at: 2026-07-04T00:00:00+08:00
execution_mode: team-feature
work_status: active
delivery_status: not_requested
stages:
  prd: { skill: prd-interview, file: prd.md, status: approved }
  spec: { skill: spec, file: spec.md, status: approved }
  qa-plan: { skill: qa, file: qa-plan.md, status: done }
  plan: { skill: plan-sync, file: plan/plan.md, status: done }
  implement: { skill: implement, file: implement-report.md, status: done }
  qa-report: { skill: qa, file: qa-report.md, status: validated }
  release: { skill: finishing-a-development-branch, file: qa-report.md, status: pending }
inputs:
  - release-request
""",
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", choices=sorted(SCENARIOS), required=True)
    parser.add_argument("--dest", type=Path, required=True)
    parser.add_argument("--skills-root", type=Path, required=True)
    args = parser.parse_args()

    dest = args.dest.resolve()
    skills_root = args.skills_root.resolve()
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(skills_root / "tests/fixtures/python-cli", dest)

    write(dest / ".agent/project-manifest.md", manifest(SCENARIOS[args.scenario]))
    write(
        dest / ".agent/guardrails.md",
        """
# Guardrails
- Work only inside this isolated repository.
- Never add a remote or push.
- Ask before irreversible deletion.
""",
    )
    write(dest / ".agent/knowledge/system-context.md", "# Journey Fixture\n\nA minimal Python greeting library.")
    write(dest / ".agent/knowledge/architecture-map.md", "# Architecture\n\n`src/greet.py` is tested by `tests/test_greet.py`.")
    write(
        dest / "AGENTS.md",
        """
# Journey eval fixture

- Start with the generated `skill-router/SKILL.md` for your harness.
- Read every dispatched skill before acting and record `Skills read:` in the required report.
- Follow `.agent/project-manifest.md`, `.agent/guardrails.md`, and the work-item artifact contract embedded in generated skills.
- Work locally only. Never add a remote or push.
""",
    )
    with (dest / ".gitignore").open("a", encoding="utf-8") as handle:
        handle.write("\n.claude/skills/\n.codex/\n")

    configure_scenario(args.scenario, dest)
    run(
        "bash",
        str(skills_root / "bootstrap/generate.sh"),
        str(dest / ".claude/skills"),
        str(dest / ".codex/skills"),
        env={**os.environ, "DELIVERY_MODE": SCENARIOS[args.scenario]},
    )
    run("git", "init", "-q", cwd=dest)
    run("git", "checkout", "-q", "-b", "main", cwd=dest)
    run("git", "add", "-A", cwd=dest)
    run("git", "-c", "user.name=Journey Eval", "-c", "user.email=eval@example.com", "commit", "-qm", "fixture baseline", cwd=dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
