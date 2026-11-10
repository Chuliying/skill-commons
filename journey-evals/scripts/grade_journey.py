#!/usr/bin/env python3
"""Deterministically grade a real-agent journey workspace."""

from __future__ import annotations

import argparse
import ast
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


# The grader lives at <skills-repo>/journey-evals/scripts/grade_journey.py, so the
# deterministic gates it re-runs resolve relative to the skills repo, not the graded
# journey workspace. Re-running the TRUSTED copy is the point: a workspace copy is
# writable by the agent being graded.
SKILLS_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SKILLS_REPO / "scripts"))
import execution_modes  # noqa: E402  (resolved against the trusted skills repo above)


def _absent_files(mode):
    """Canonical files a mode forbids, derived from the registry (ADR-R3 I-M1).

    Previously each scenario restated its own tuple, which drifted: the
    personal-feature check demanded prd.md be ABSENT while the registry declares prd
    OPTIONAL for that mode, so a legitimate personal PRD would have failed the journey.
    """
    return sorted(execution_modes.canonical_file(name)
                  for name in execution_modes.absent_artifacts(mode))


def _none_present(work, mode):
    return not any((work / name).exists() for name in _absent_files(mode))


def _run_ok(args: list[str], cwd: Path | None = None) -> bool:
    try:
        return subprocess.run(
            args, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode == 0
    except OSError:
        return False


def prd_shape_ok(prd: Path, tier: str) -> bool:
    """Re-run the deterministic PRD shape gate; a stub/[TBD] PRD fails it."""
    script = SKILLS_REPO / "scripts/check-prd.py"
    if not (script.is_file() and prd.is_file()):
        return False
    return _run_ok(["python3", str(script), "--prd", str(prd), "--tier", tier])


def traceability_ok(prd: Path, qa_plan: Path) -> bool:
    """Re-run AC->TC traceability; a single-char qa-plan leaves ACs unmapped."""
    script = SKILLS_REPO / "qa/scripts/check-traceability.py"
    if not (script.is_file() and prd.is_file() and qa_plan.is_file()):
        return False
    return _run_ok(["python3", str(script), "--prd", str(prd), "--qa-plan", str(qa_plan)])


def security_gate_reproduced(workspace: Path) -> bool:
    """Re-run the secret scan against the workspace using the TRUSTED scanner from the
    skills repo -- never the workspace's own generated copy, which the graded agent can
    tamper with (e.g. replace with `exit 0`). Runs with cwd=workspace so it reads the
    workspace manifest/source roots and .gitignore. A planted secret fails this even if
    the report claims 'Security: PASS' and the workspace scanner was neutered."""
    scan = SKILLS_REPO / "security/scripts/scan-secrets.sh"
    if not scan.is_file():
        return False
    return _run_ok(["bash", str(scan)], cwd=workspace)


def plan_consistency_ok(work: Path) -> bool:
    """Re-run plan-sync consistency on the work item's plan/. Stub plan files (single
    line, no sections/tasks) fail this, so 'formal artifacts exist' is not enough."""
    script = SKILLS_REPO / "plan-sync/scripts/validate_consistency.py"
    plan_dir = work / "plan"
    if not (script.is_file() and plan_dir.is_dir()):
        return False
    return _run_ok(["python3", str(script), "--plan-dir", str(plan_dir)])

def _is_greet_ws(node: ast.AST) -> bool:
    """True for a call greet("  Codex  ") (bound method or plain)."""
    if not isinstance(node, ast.Call):
        return False
    func = node.func
    name = func.attr if isinstance(func, ast.Attribute) else func.id if isinstance(func, ast.Name) else ""
    return (
        name == "greet"
        and len(node.args) >= 1
        and isinstance(node.args[0], ast.Constant)
        and node.args[0].value == "  Codex  "
    )


def _is_expected(node: ast.AST) -> bool:
    return isinstance(node, ast.Constant) and node.value == "hello Codex"


def pinning_assertion_present(test_file: Path) -> bool:
    """AST-verified: some assertion must actually compare greet("  Codex  ") to the
    expected "hello Codex". Substring/comment tricks and trivial co-located assertions
    (`assertEqual("hello Codex", "hello Codex"); greet("  Codex  ")`) do not count,
    because the greet(...) call must be an OPERAND of the equality itself."""
    if not test_file.is_file():
        return False
    try:
        tree = ast.parse(test_file.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError:
        return False
    for node in ast.walk(tree):
        # unittest style: self.assertEqual(<greet(...)>, "hello Codex") in either order
        if isinstance(node, ast.Call):
            func = node.func
            fname = func.attr if isinstance(func, ast.Attribute) else func.id if isinstance(func, ast.Name) else ""
            if fname == "assertEqual" and len(node.args) >= 2:
                a, b = node.args[0], node.args[1]
                if (_is_greet_ws(a) and _is_expected(b)) or (_is_greet_ws(b) and _is_expected(a)):
                    return True
        # pytest style: assert greet("  Codex  ") == "hello Codex"
        if isinstance(node, ast.Assert) and isinstance(node.test, ast.Compare):
            cmp = node.test
            if any(isinstance(op, ast.Eq) for op in cmp.ops):
                operands = [cmp.left, *cmp.comparators]
                if any(_is_greet_ws(o) for o in operands) and any(_is_expected(o) for o in operands):
                    return True
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
            r"\.(?:agents|codex|claude)/skills/security/scripts/scan-secrets\.sh"
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
        structural["lightweight_fallback"] = _none_present(work, "personal-feature")
        recorded["implement_read_recorded"] = skill_read_recorded(report, "implement")
    elif scenario == "team-feature":
        # ADR-R3 I-M1: the roster comes from the registry, not from a tuple restated
        # here. A local list drifts from the contract while both halves keep looking
        # correct -- this one had five entries and omitted plan/plan.md, which the
        # following line then had to add back by hand.
        structural["formal_artifacts"] = all(
            (work / name).is_file()
            for name in execution_modes.required_files("team-feature")
        )
        # Existence is not shape. A single-line stub satisfies the check above, so
        # re-run the deterministic gates that own each artifact's contract, using the
        # TRUSTED copies in the skills repo rather than the workspace's generated ones.
        structural["prd_shape_verified"] = prd_shape_ok(work / "prd.md", "team")
        structural["traceability_verified"] = traceability_ok(
            work / "prd.md", work / "qa-plan.md"
        )
        structural["plan_consistency_verified"] = plan_consistency_ok(work)
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
        # Behavior, not tokens. `contains(src/greet.py, ".strip()")` passed on a comment
        # that merely mentioned .strip(), which is the JE-1 defect: a grader answering
        # "was the bug fixed?" by looking for a string. Run the function instead.
        structural["bug_fixed"] = command_ok(
            root,
            "python3",
            "-c",
            "from src.greet import greet; assert greet('  Codex  ') == 'hello Codex'",
        )
        # The fixture's pinning test must survive as a real assertion. Deleting it and
        # leaving the input string in a comment does not count, and neither does a
        # trivial co-located assertion -- the greet(...) call must be an operand of the
        # equality itself, which is checked against the AST.
        structural["pinning_test_intact"] = pinning_assertion_present(
            root / "tests/test_greet.py"
        )
        structural["bug_fallback"] = _none_present(work, "bug-fix")
        recorded["debug_skills_read_recorded"] = all(
            skill_read_recorded(report, name) for name in ("systematic-debugging", "implement")
        )
    elif scenario == "refactor":
        source = (root / "src/greet.py").read_text(encoding="utf-8", errors="replace")
        structural["refactored_once"] = (
            "def _normalize_name" in source and source.count(".strip().title()") == 1
        )
        structural["intent_artifact"] = (work / "prd.md").is_file()
        structural["no_qa_ceremony"] = _none_present(work, "refactor")
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
        # A recorded command is a claim, not evidence. Re-run the secret scan with the
        # TRUSTED scanner from the skills repo -- never the workspace's generated copy,
        # which the graded agent can replace with `exit 0`. A planted secret fails here
        # even when the report says "Security: PASS".
        structural["security_reproduced"] = security_gate_reproduced(root)
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
