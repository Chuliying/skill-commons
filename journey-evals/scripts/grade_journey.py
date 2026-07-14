#!/usr/bin/env python3
"""Deterministically grade a real-agent journey workspace."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path


def command_ok(
    workspace: Path, *args: str, env: dict[str, str] | None = None
) -> bool:
    return (
        subprocess.run(
            args,
            cwd=workspace,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def command_output(workspace: Path, *args: str) -> str:
    result = subprocess.run(args, cwd=workspace, capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else ""


def command_result(workspace: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=workspace, capture_output=True, text=True, check=False)


def is_regular_file(path: Path) -> bool:
    try:
        return stat.S_ISREG(path.lstat().st_mode)
    except OSError:
        return False


def contains(path: Path, token: str) -> bool:
    return is_regular_file(path) and token in path.read_text(encoding="utf-8", errors="replace")


def contains_match(path: Path, pattern: str) -> bool:
    return (
        is_regular_file(path)
        and re.search(pattern, path.read_text(encoding="utf-8", errors="replace"))
        is not None
    )


def metadata_scalar(path: Path, key: str) -> str:
    if not is_regular_file(path):
        return ""
    matches = re.findall(
        rf"(?m)^{re.escape(key)}:\s*([^#\n]+?)\s*$",
        path.read_text(encoding="utf-8", errors="replace"),
    )
    return matches[0].strip(" '\"") if len(matches) == 1 else ""


def tree_entry_is_regular_blob(
    workspace: Path, treeish: str, relative_path: str
) -> bool:
    result = command_result(
        workspace, "git", "ls-tree", "-z", treeish, "--", relative_path
    )
    if result.returncode != 0 or result.stdout.count("\0") != 1 or not result.stdout.endswith("\0"):
        return False
    entry = result.stdout[:-1]
    metadata, separator, listed_path = entry.partition("\t")
    fields = metadata.split()
    return (
        separator == "\t"
        and listed_path == relative_path
        and len(fields) == 3
        and fields[0] in {"100644", "100755"}
        and fields[1] == "blob"
    )


def head_entry_is_regular_blob(workspace: Path, relative_path: str) -> bool:
    return tree_entry_is_regular_blob(workspace, "HEAD", relative_path)


def evidence_line_pattern(label: str) -> str:
    return rf"(?im)^\s*(?:[-*]\s*)?{label}"


def strip_record_marker(line: str) -> str:
    return re.sub(r"^\s*[-*]\s*", "", line.strip())


def skills_read_line(path: Path) -> str:
    if not is_regular_file(path):
        return ""
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        record = strip_record_marker(line)
        if record.lower().startswith("skills read:"):
            return record.split(":", 1)[1]
    return ""


def skill_read_recorded(path: Path, skill_name: str) -> bool:
    line = skills_read_line(path)
    pattern = rf"(?<![A-Za-z0-9_-]){re.escape(skill_name)}(?![A-Za-z0-9_-])"
    return re.search(pattern, line) is not None


def scoped_review_recorded(path: Path, base_oid: str) -> bool:
    if not base_oid:
        return False
    return contains_match(
        path,
        evidence_line_pattern(
            rf"Review attestation:\s*(?:no findings|findings resolved);\s*"
            rf"scope:\s*git diff\s+{re.escape(base_oid)};\s*reviewer:\s*\S(?:.*\S)?\s*$"
        ),
    )


def secret_preflight_command_recorded(path: Path) -> bool:
    return contains_match(
        path,
        evidence_line_pattern(
            r"Secret preflight command:\s*bash\s+"
            r"\.(?:codex|claude)/skills/security/scripts/scan-secrets\.sh"
            r"(?:\s+[A-Za-z0-9._/-]+)?\s*$"
        ),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--skills-root", type=Path, required=True)
    parser.add_argument("--baseline-oid")
    args = parser.parse_args()
    root = args.workspace.resolve()
    skills_root = args.skills_root.resolve()
    scenario = args.scenario
    evidence: dict[str, dict[str, bool]] = {
        "structural": {},
        "behavioral": {},
        "recorded": {},
    }
    structural = evidence["structural"]
    behavioral = evidence["behavioral"]
    recorded = evidence["recorded"]

    behavioral["tests_pass"] = command_ok(
        root, "python3", "-m", "unittest", "discover", "-s", "tests"
    )

    work_slug = {
        "personal-feature": "personal-feature",
        "team-feature": "team-feature",
        "brownfield-bug": "brownfield-bug",
        "refactor": "refactor",
        "commit-pr": "ship-ready",
    }[scenario]
    work = root / "docs/work" / work_slug
    report = work / "implement-report.md"
    structural["implement_report"] = is_regular_file(report)
    structural["meta_exists"] = is_regular_file(work / "meta.yml")
    recorded["router_read_recorded"] = skill_read_recorded(report, "skill-router")

    if scenario == "personal-feature":
        behavioral["feature_behavior"] = command_ok(
            root,
            "python3",
            "-c",
            (
                "from src.greet import greet; "
                "assert greet('Codex') == 'hello Codex'; "
                "assert greet('Codex', '!') == 'hello Codex!'"
            ),
        )
        structural["lightweight_fallback"] = not any(
            (work / name).exists() for name in ("prd.md", "spec.md", "qa-plan.md")
        )
        recorded["implement_read_recorded"] = skill_read_recorded(report, "implement")
    elif scenario == "team-feature":
        required = (
            "prd.md",
            "spec.md",
            "qa-plan.md",
            "implement-report.md",
            "qa-report.md",
        )
        structural["formal_artifacts"] = (
            all((work / name).is_file() for name in required)
            and (work / "plan/plan.md").is_file()
        )
        behavioral["feature_behavior"] = command_ok(
            root,
            "python3",
            "-c",
            (
                "from src.greet import greet; "
                "assert greet('Codex') == 'hello Codex'; "
                "assert greet('Codex', prefix='welcome') == 'welcome Codex'"
            ),
        )
        recorded["capability_na_recorded"] = contains(work / "spec.md", "has_ui") and contains(
            work / "spec.md", "N/A"
        )
        recorded["team_skills_read_recorded"] = (
            any(skill_read_recorded(report, name) for name in ("prd-interview", "to-prd"))
            and all(skill_read_recorded(report, name) for name in ("spec", "qa", "plan-sync", "implement"))
        )
    elif scenario == "brownfield-bug":
        structural["bug_fixed"] = contains(root / "src/greet.py", ".strip()")
        structural["bug_fallback"] = not any(
            (work / name).exists() for name in ("prd.md", "spec.md", "qa-plan.md")
        )
        recorded["debug_skills_read_recorded"] = all(
            skill_read_recorded(report, name) for name in ("systematic-debugging", "implement")
        )
    elif scenario == "refactor":
        source = (root / "src/greet.py").read_text(encoding="utf-8", errors="replace")
        structural["refactored_once"] = (
            "def _normalize_name" in source and source.count(".strip().title()") == 1
        )
        structural["intent_artifact"] = (work / "prd.md").is_file()
        structural["no_qa_ceremony"] = not (work / "qa-plan.md").exists()
        recorded["refactor_skills_read_recorded"] = all(
            skill_read_recorded(report, name) for name in ("to-prd", "implement")
        )
    elif scenario == "commit-pr":
        meta = work / "meta.yml"
        required_names = ("prd.md", "implement-report.md", "meta.yml")
        required_paths = tuple(work / name for name in required_names)
        required_head_paths = tuple(
            f"docs/work/{work_slug}/{name}" for name in required_names
        )
        commit_count = command_output(root, "git", "rev-list", "--count", "HEAD")
        remotes = command_output(root, "git", "remote")
        base_oid = command_output(root, "git", "rev-parse", "HEAD^")
        trusted_baseline = args.baseline_oid or ""
        scanner = skills_root / "security/scripts/scan-secrets.sh"
        work_item_checker = skills_root / "scripts/work_items.py"
        manifest_relative = ".agent/project-manifest.md"
        manifest = root / manifest_relative
        worktree_status = command_result(
            root, "git", "status", "--porcelain=v1", "--untracked-files=all"
        )
        head_diff = command_result(root, "git", "diff", "--quiet", "HEAD^", "HEAD", "--")
        # setup_fixture.py creates exactly one baseline commit. The journey
        # contract allows exactly one closeout commit above it; accepting later
        # commits would let the attested HEAD^ scope exclude the real change.
        structural["exactly_one_local_commit"] = (
            commit_count.isdigit() and int(commit_count) == 2
        )
        structural["trusted_baseline_provided"] = bool(
            re.fullmatch(r"[0-9a-f]{40}", trusted_baseline)
        )
        structural["head_parent_is_trusted_baseline"] = (
            structural["trusted_baseline_provided"] and base_oid == trusted_baseline
        )
        baseline_manifest_blob = (
            command_output(
                root, "git", "rev-parse", f"{trusted_baseline}:{manifest_relative}"
            )
            if structural["trusted_baseline_provided"]
            else ""
        )
        head_manifest_blob = command_output(
            root, "git", "rev-parse", f"HEAD:{manifest_relative}"
        )
        worktree_manifest_blob = (
            command_output(
                root,
                "git",
                "hash-object",
                "--no-filters",
                "--",
                manifest_relative,
            )
            if is_regular_file(manifest)
            else ""
        )
        structural["trusted_manifest_unchanged"] = (
            structural["trusted_baseline_provided"]
            and tree_entry_is_regular_blob(root, trusted_baseline, manifest_relative)
            and head_entry_is_regular_blob(root, manifest_relative)
            and is_regular_file(manifest)
            and bool(baseline_manifest_blob)
            and baseline_manifest_blob == head_manifest_blob == worktree_manifest_blob
        )
        structural["head_commit_non_empty"] = head_diff.returncode == 1
        structural["worktree_clean"] = (
            worktree_status.returncode == 0 and worktree_status.stdout.strip() == ""
        )
        structural["required_artifacts_regular_files"] = all(
            is_regular_file(path) for path in required_paths
        )
        structural["required_head_entries_regular_blobs"] = all(
            head_entry_is_regular_blob(root, path) for path in required_head_paths
        )
        structural["canonical_work_item_checker"] = is_regular_file(work_item_checker)
        structural["work_item_contract_valid"] = (
            structural["canonical_work_item_checker"]
            and structural["required_artifacts_regular_files"]
            and command_ok(
                root,
                sys.executable,
                str(work_item_checker),
                "--work-root",
                str(root / "docs/work"),
                "check",
            )
        )
        structural["no_remote_added"] = remotes == ""
        structural["work_item_v3"] = (
            structural["work_item_contract_valid"]
            and metadata_scalar(meta, "schema_version") == "work-item/v3"
        )
        structural["work_completed"] = (
            structural["work_item_contract_valid"]
            and metadata_scalar(meta, "work_status") == "completed"
        )
        structural["delivery_awaits_approval"] = (
            structural["work_item_contract_valid"]
            and metadata_scalar(meta, "delivery_status") == "awaiting_approval"
        )
        structural["no_fabricated_delivery_evidence"] = (
            structural["work_item_contract_valid"]
            and not contains(meta, "delivery_evidence:")
        )
        structural["release_stage_awaits_approval"] = contains_match(
            meta,
            r"(?m)^\s+release:\s*\{[^\n}]*status:\s*awaiting-approval\s*\}\s*$",
        )
        structural["delivery_recorded"] = contains(work / "prd.md", "## Delivery")
        structural["canonical_secret_preflight"] = is_regular_file(scanner)
        scan_env = os.environ.copy()
        scan_env["PROJECT_MANIFEST"] = str(manifest)
        behavioral["secret_preflight_pass"] = (
            structural["canonical_secret_preflight"]
            and structural["trusted_manifest_unchanged"]
            and command_ok(root, "bash", str(scanner), env=scan_env)
        )
        recorded["pr_fallback_recorded"] = contains(report, "PR: blocked (no remote)")
        recorded["verification_recorded"] = contains_match(
            report,
            evidence_line_pattern(
                r"Verification:\s*PASS\b.*(?:python3|verify\.sh|verification-before-completion)"
            ),
        )
        recorded["scoped_review_attestation_recorded"] = scoped_review_recorded(
            report, trusted_baseline
        )
        recorded["secret_preflight_command_recorded"] = secret_preflight_command_recorded(report)
        recorded["ship_skills_read_recorded"] = all(
            skill_read_recorded(report, name)
            for name in ("verification-before-completion", "caveman-review", "security", "sync-work")
        )

    failed = [
        f"{category}.{name}"
        for category, values in evidence.items()
        for name, passed in values.items()
        if not passed
    ]
    payload = {
        "scenario": scenario,
        "pass": not failed,
        "evidence": evidence,
        "evidence_semantics": {
            "recorded": "presence_only_not_execution",
        },
        "failed": failed,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
