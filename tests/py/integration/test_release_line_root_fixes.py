"""Release-line root-fix regressions.

These tests intentionally describe the fail-closed behavior required at public
product boundaries.  They are RED against baseline 4e06ce3.
"""

import copy
import inspect
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from foundation import core as foundation_core
from foundation import home as foundation_home
from orchestration import errors as orchestration_errors
from orchestration import execution, graph, identity
from productscope import activation, contracts
from productscope import errors as productscope_errors


REPO_ROOT = Path(__file__).resolve().parents[3]
SCANNER = REPO_ROOT / "security" / "scripts" / "scan-secrets.sh"


def _git_repo(path):
    path.mkdir()
    subprocess.run(
        ["git", "init", "-q", str(path)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["git", "-C", str(path), "config", "user.name", "Release Test"],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(path), "config", "user.email", "release@example.test"],
        check=True,
    )
    return path


def _commit_file(repo, relative_path, content):
    import hashlib

    path = repo / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "add", relative_path], check=True)
    subprocess.run(
        ["git", "-C", str(repo), "commit", "-qm", "add " + relative_path],
        check=True,
    )
    oid = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    return oid, hashlib.sha256(content.encode("utf-8")).hexdigest()


def _artifact_ref(repo, relative_path, content, kind, repo_id="repoA"):
    oid, digest = _commit_file(repo, relative_path, content)
    return {
        "repo_id": repo_id,
        "commit_oid": oid,
        "path": relative_path,
        "digest": digest,
        "artifact_kind": kind,
    }


def _personal_proposals(provenance=None):
    return identity.build_slice_proposals(
        provenance
        or {
            "repo_id": "repoA",
            "commit_oid": "a" * 40,
            "path": "initiative.md",
            "digest": "b" * 64,
            "artifact_kind": "prd",
        },
        [
            {
                "repo_id": "repoA",
                "workflow_profile": "personal-feature",
                "owner": "ownerA",
            },
            {
                "repo_id": "repoB",
                "workflow_profile": "personal-feature",
                "owner": "ownerB",
            },
        ],
        [
            {"requirement_id": "R1", "repo_id": "repoA"},
            {"requirement_id": "R2", "repo_id": "repoB"},
        ],
        [],
    )


def _execution_graph(dispatchable=True):
    return {
        "generation": 1,
        "graph_digest": "g" * 64,
        "nodes": [
            {
                "id": "task:repoA",
                "kind": "repo-task",
                "repo_id": "repoA",
                "generation": 1,
            }
        ],
        "edges": [],
        "dispatchable": dispatchable,
    }


def _scanner_repo(root, source_root):
    repo = root / "repo"
    _git_repo(repo)
    (repo / ".agent").mkdir()
    (repo / ".gitignore").write_text(".env\n", encoding="utf-8")
    (repo / ".agent" / "project-manifest.md").write_text(
        "\n".join(
            [
                "## Paths",
                "- source_roots: " + source_root,
                "## Stack",
                "- source_extensions: py",
                "- framework: python-cli",
                "- package_manager: python",
                "- has_ui: false",
                "",
            ]
        ),
        encoding="utf-8",
    )
    subprocess.run(["git", "-C", str(repo), "config", "core.excludesFile", "/dev/null"],
                   check=True)
    subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "fixture"], check=True)
    return repo


def _run_scanner(repo, *targets, environment=None):
    return subprocess.run(
        ["bash", str(SCANNER), *targets],
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=environment,
    )


def _scanner_call_ledger(root):
    """Return an environment that records every scan-files helper invocation."""
    real_python = shutil.which("python3")
    if real_python is None:
        raise AssertionError("python3 is required")
    shim_dir = root / "python-bin"
    shim_dir.mkdir()
    ledger = root / "scan-files.calls"
    ledger.write_text("", encoding="utf-8")
    shim = shim_dir / "python3"
    shim.write_text(
        """#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    */scan-files.py)
      printf '%s\n' "$*" >> "$SCAN_FILES_CALL_LEDGER"
      break
      ;;
  esac
done
exec "$REAL_PYTHON" "$@"
""",
        encoding="utf-8",
    )
    shim.chmod(0o755)
    environment = dict(os.environ)
    environment.update(
        {
            "PATH": str(shim_dir) + os.pathsep + environment["PATH"],
            "REAL_PYTHON": real_python,
            "SCAN_FILES_CALL_LEDGER": str(ledger),
        }
    )
    return environment, ledger


class ReleaseLineRootFixes(unittest.TestCase):
    def test_f01_manifest_and_cli_share_target_validation(self):
        with tempfile.TemporaryDirectory(prefix="f01-release-") as temporary:
            root = Path(temporary)
            outside = root / "outside"
            outside.mkdir()
            (outside / "clean.py").write_text("x = 1\n", encoding="utf-8")
            repo = _scanner_repo(root, "../outside")
            environment, ledger = _scanner_call_ledger(root)

            manifest_result = _run_scanner(repo, environment=environment)
            manifest_calls = ledger.read_text(encoding="utf-8")
            ledger.write_text("", encoding="utf-8")
            cli_result = _run_scanner(
                repo, "../outside", environment=environment
            )
            cli_calls = ledger.read_text(encoding="utf-8")

            for result, calls in (
                (manifest_result, manifest_calls),
                (cli_result, cli_calls),
            ):
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(calls, "", result.stdout)
                self.assertIn("outside the Git worktree", result.stdout)
                self.assertNotIn("Secret scan targets:", result.stdout)
                self.assertNotIn("PASS:", result.stdout)
                self.assertNotIn("CLEAR:", result.stdout)
                self.assertNotIn("Secret preflight result: PASS", result.stdout)

    def test_f02_arbitrary_binding_cannot_dispatch(self):
        proposals = _personal_proposals()
        bindings = {
            "repoA": {"execution-plan": {"not": "an artifact ref"}},
            "repoB": {"execution-plan": {"also": "not an artifact ref"}},
        }
        proposals_before = copy.deepcopy(proposals)
        bindings_before = copy.deepcopy(bindings)

        with self.assertRaises(orchestration_errors.OrchestrationError) as caught:
            graph.build_graph(proposals, bindings, generation=1)

        self.assertEqual(caught.exception.code, "INVALID_BINDING")
        self.assertEqual(proposals, proposals_before)
        self.assertEqual(bindings, bindings_before)

    def test_f03_non_dispatchable_graph_cannot_dispatch(self):
        blocked_graph = _execution_graph(dispatchable=False)
        blocked_graph.update(
            {
                "ready_order": ["R1"],
                "binding_report": {
                    "slices": [
                        {
                            "repo_id": "repoA",
                            "state": "CURRENT",
                            "missing": [],
                        }
                    ],
                    "dispatchable": True,
                },
            }
        )
        graph.validate_graph(blocked_graph)
        journal = execution.new_journal()
        journal_before = copy.deepcopy(journal)

        result = execution.dispatch(
            blocked_graph, "task:repoA", {"max_retries": 0}, journal
        )

        self.assertEqual(journal, journal_before)
        self.assertEqual(
            result,
            {"state": "BLOCKED", "reason": "GRAPH_NOT_DISPATCHABLE"},
        )

    def test_f04_negative_retry_budget_is_rejected(self):
        source_graph = _execution_graph()
        policy = {"max_retries": -5}
        graph_before = copy.deepcopy(source_graph)
        policy_before = copy.deepcopy(policy)
        journal = execution.new_journal()
        journal_before = copy.deepcopy(journal)

        with self.assertRaises(orchestration_errors.OrchestrationError) as caught:
            execution.dispatch(source_graph, "task:repoA", policy, journal)

        self.assertEqual(caught.exception.code, "INVALID_RETRY_POLICY")
        self.assertEqual(source_graph, graph_before)
        self.assertEqual(policy, policy_before)
        self.assertEqual(journal, journal_before)

    def test_f05_late_result_cannot_bind_to_successor(self):
        journal = execution.new_journal()
        first_dispatch = execution.dispatch(
            _execution_graph(), "task:repoA", {"max_retries": 1}, journal
        )
        interrupted_attempt_digest = first_dispatch["attempt_digest"]
        journal["locks"].clear()
        execution.reconcile(journal, "task:repoA", "retry after crash")
        journal_before_late_result = copy.deepcopy(journal)

        with self.assertRaises(orchestration_errors.OrchestrationError) as caught:
            execution.record_result(
                journal, interrupted_attempt_digest, "OBSERVED", exit_code=0
            )

        self.assertEqual(caught.exception.code, "ATTEMPT_IDENTITY_REQUIRED")
        self.assertEqual(journal, journal_before_late_result)

    def test_f06_six_participants_are_rejected(self):
        registry = [
            {
                "repo_id": "repo%d" % index,
                "workflow_profile": "personal-feature",
                "owner": "owner%d" % index,
            }
            for index in range(6)
        ]
        assignments = [
            {"requirement_id": "R%d" % index, "repo_id": "repo%d" % index}
            for index in range(6)
        ]
        registry_before = copy.deepcopy(registry)
        assignments_before = copy.deepcopy(assignments)

        with self.assertRaises(orchestration_errors.OrchestrationError) as caught:
            identity.build_slice_proposals(
                {
                    "repo_id": "repo0",
                    "commit_oid": "a" * 40,
                    "path": "initiative.md",
                    "digest": "b" * 64,
                    "artifact_kind": "prd",
                },
                registry,
                assignments,
                [],
            )

        self.assertEqual(caught.exception.code, "UNSUPPORTED_PARTICIPANT_COUNT")
        self.assertEqual(registry, registry_before)
        self.assertEqual(assignments, assignments_before)

    def test_f07_delta_analysis_identity_must_match(self):
        analysis = contracts.build_analysis(
            envelope_digest="d" * 64,
            base_scope_revision="c" * 40,
            deterministic_matches=[],
            advisory_candidates=[],
            canonical_diff={
                "added": [],
                "modified": [],
                "superseded": [],
                "removed": [],
                "unchanged": [],
            },
            conflicts=[],
            impact_candidates=[],
        )
        matching_delta = {
            "product_id": "prod",
            "proposal_ref": analysis["envelope_digest"],
            "parent_scope_revision": analysis["base_scope_revision"],
            "accepted_changes": [{"requirement_id": "R1", "operation": "ADD"}],
            "accepted_relations": [],
            "requirement_impact": [],
            "decision_context": {
                "mode": "personal-apply",
                "source_package_path": "package.md",
                "source_package_digest": "a" * 64,
                "decided_at": "2026-07-27T00:00:00+08:00",
            },
            "delta_digest": "b" * 64,
        }

        for field, mismatched_value in (
            ("proposal_ref", "e" * 64),
            ("parent_scope_revision", "f" * 40),
        ):
            with self.subTest(field=field):
                delta = copy.deepcopy(matching_delta)
                delta[field] = mismatched_value
                analysis_before = copy.deepcopy(analysis)
                delta_before = copy.deepcopy(delta)

                with self.assertRaises(
                    productscope_errors.ProductScopeError
                ) as caught:
                    contracts.validate_delta_against_analysis(delta, analysis)

                self.assertEqual(caught.exception.code, "IDENTITY_MISMATCH")
                self.assertEqual(analysis, analysis_before)
                self.assertEqual(delta, delta_before)

    def test_f08_duplicate_requirement_ids_are_rejected(self):
        delta = {
            "product_id": "prod",
            "proposal_ref": "d" * 64,
            "parent_scope_revision": "c" * 40,
            "accepted_changes": [
                {"requirement_id": "R1", "operation": "ADD"},
                {"requirement_id": "R1", "operation": "MODIFY"},
            ],
            "accepted_relations": [],
            "requirement_impact": [],
            "decision_context": {
                "mode": "personal-apply",
                "source_package_path": "package.md",
                "source_package_digest": "a" * 64,
                "decided_at": "2026-07-27T00:00:00+08:00",
            },
            "delta_digest": "b" * 64,
        }
        delta_before = copy.deepcopy(delta)

        with self.assertRaises(productscope_errors.ProductScopeError) as caught:
            contracts.validate_delta(delta)

        self.assertEqual(caught.exception.code, "DUPLICATE_REQUIREMENT_ID")
        self.assertEqual(delta, delta_before)

    def test_f09_git_object_failure_is_not_needs_rebase(self):
        real_git = shutil.which("git")
        self.assertIsNotNone(real_git)
        candidate_ref = {
            "repo_id": "repoA",
            "commit_oid": "a" * 40,
            "path": "delta.json",
            "digest": "b" * 64,
            "artifact_kind": "accepted-scope-delta",
        }

        for failed_subcommand in ("hash-object", "mktree", "commit-tree"):
            with self.subTest(failed_subcommand=failed_subcommand):
                with tempfile.TemporaryDirectory(prefix="f09-release-") as temporary:
                    root = Path(temporary)
                    scope_repo = _git_repo(root / "scope")
                    shim_dir = root / "bin"
                    shim_dir.mkdir()
                    shim = shim_dir / "git"
                    shim.write_text(
                        """#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    rev-list|hash-object|mktree|commit-tree|update-ref)
      printf '%s\n' "$arg" >> "$GIT_CALL_LEDGER"
      ;;
  esac
  if [ "$arg" = "$FAIL_GIT_SUBCOMMAND" ]; then
    echo "forced $arg failure" >&2
    exit 73
  fi
done
exec "$REAL_GIT" "$@"
""",
                        encoding="utf-8",
                    )
                    shim.chmod(0o755)
                    call_ledger = root / "git.calls"
                    call_ledger.write_text("", encoding="utf-8")
                    git_dir = str(scope_repo / ".git")
                    state_before = {
                        "head": activation.head(git_dir),
                        "lineage": activation.lineage(git_dir),
                    }
                    environment = {
                        "PATH": str(shim_dir) + os.pathsep + os.environ["PATH"],
                        "REAL_GIT": real_git,
                        "FAIL_GIT_SUBCOMMAND": failed_subcommand,
                        "GIT_CALL_LEDGER": str(call_ledger),
                    }

                    with mock.patch.object(
                        activation.core, "resolve", return_value={}
                    ), mock.patch.dict(os.environ, environment, clear=False):
                        with self.assertRaises(
                            productscope_errors.ProductScopeError
                        ) as caught:
                            activation.activate(
                                git_dir, "foundation-unused", candidate_ref, None
                            )

                    self.assertEqual(
                        caught.exception.code, "ACTIVATION_GIT_ERROR"
                    )
                    self.assertIn(failed_subcommand, caught.exception.message)
                    calls = call_ledger.read_text(encoding="utf-8").splitlines()
                    self.assertIn(failed_subcommand, calls)
                    failed_index = (
                        "hash-object",
                        "mktree",
                        "commit-tree",
                        "update-ref",
                    ).index(failed_subcommand)
                    self.assertFalse(
                        set(calls).intersection(
                            (
                                "hash-object",
                                "mktree",
                                "commit-tree",
                                "update-ref",
                            )[failed_index + 1 :]
                        ),
                        calls,
                    )
                    self.assertEqual(
                        {
                            "head": activation.head(git_dir),
                            "lineage": activation.lineage(git_dir),
                        },
                        state_before,
                    )

    def test_f10_bindings_resolve_once_before_graph(self):
        resolver = graph.resolve_and_validate_bindings
        self.assertEqual(
            list(inspect.signature(resolver).parameters),
            ["bindings", "foundation_home"],
        )

        with tempfile.TemporaryDirectory(prefix="f10-release-") as temporary:
            root = Path(temporary)
            home_repo = _git_repo(root / "home")
            source_repo = _git_repo(root / "source-a")
            source_repo_b = _git_repo(root / "source-b")
            home_git = str(home_repo / ".git")
            foundation_core.register(
                home_git,
                "repoA",
                str(source_repo / ".git"),
                foundation_home.read_head(home_git),
            )
            foundation_core.register(
                home_git,
                "repoB",
                str(source_repo_b / ".git"),
                foundation_home.read_head(home_git),
            )
            prd_ref = _artifact_ref(source_repo, "initiative.md", "initiative", "prd")
            foundation_core.publish(
                home_git,
                "repoA/home",
                prd_ref,
                [],
                foundation_home.read_head(home_git),
            )
            plan_ref = _artifact_ref(
                source_repo, "plan.md", "execution plan", "plan"
            )
            foundation_core.publish(
                home_git,
                "repoA/home",
                plan_ref,
                [],
                foundation_home.read_head(home_git),
            )
            plan_ref_b = _artifact_ref(
                source_repo_b,
                "plan.md",
                "repo B execution plan",
                "plan",
                repo_id="repoB",
            )
            foundation_core.publish(
                home_git,
                "repoA/home",
                plan_ref_b,
                [],
                foundation_home.read_head(home_git),
            )
            proposals = _personal_proposals(prd_ref)
            bindings = {
                "repoA": {
                    "execution-plan": plan_ref,
                    "prd-snapshot": prd_ref,
                },
                "repoB": {"execution-plan": plan_ref_b},
            }
            raw_bindings_before = copy.deepcopy(bindings)
            foundation_head_before = foundation_home.read_head(home_git)

            with self.assertRaises(
                orchestration_errors.OrchestrationError
            ) as raw_caught:
                graph.build_graph(proposals, bindings, generation=1)
            self.assertEqual(raw_caught.exception.code, "INVALID_BINDING")
            self.assertEqual(bindings, raw_bindings_before)

            class ForgedBindings(graph.ValidatedBindings):
                def __init__(self):
                    pass

                def _for_repo(self, repo_id):
                    return {
                        "execution-plan": {"not": "Foundation-resolved"},
                    }

            with self.assertRaises(
                orchestration_errors.OrchestrationError
            ) as forged_caught:
                graph.build_graph(proposals, ForgedBindings(), generation=1)
            self.assertEqual(forged_caught.exception.code, "INVALID_BINDING")

            with self.assertRaises(TypeError):
                graph.ValidatedBindings(object(), bindings)
            self.assertFalse(hasattr(graph, "_VALIDATED_BINDINGS_TOKEN"))
            self.assertFalse(hasattr(graph, "_issue_validated_bindings"))
            self.assertFalse(hasattr(graph, "_ISSUED_VALIDATED_BINDINGS"))

            allocated = object.__new__(graph.ValidatedBindings)
            object.__setattr__(
                allocated,
                "_ValidatedBindings__by_repo",
                copy.deepcopy(bindings),
            )
            with self.assertRaises(
                orchestration_errors.OrchestrationError
            ) as allocated_caught:
                graph.build_graph(proposals, allocated, generation=1)
            self.assertEqual(allocated_caught.exception.code, "INVALID_BINDING")

            with mock.patch.object(
                foundation_core, "resolve", wraps=foundation_core.resolve
            ) as resolve:
                validated_bindings = resolver(bindings, home_git)
                self.assertIsInstance(validated_bindings, graph.ValidatedBindings)
                self.assertNotIsInstance(validated_bindings, dict)
                exposed = validated_bindings._for_repo("repoA")
                exposed["execution-plan"] = {"not": "Foundation-resolved"}
                object.__setattr__(
                    validated_bindings,
                    "_ValidatedBindings__by_repo",
                    {
                        "repoA": {
                            "execution-plan": {"not": "Foundation-resolved"},
                        },
                        "repoB": {
                            "execution-plan": {"not": "Foundation-resolved"},
                        },
                    },
                )
                report = graph.binding_report(proposals, validated_bindings)
                built = graph.build_graph(
                    proposals, validated_bindings, generation=1
                )

            self.assertEqual(resolve.call_count, 3)
            resolve.assert_has_calls(
                [
                    mock.call(home_git, plan_ref),
                    mock.call(home_git, prd_ref),
                    mock.call(home_git, plan_ref_b),
                ],
                any_order=True,
            )
            self.assertEqual(
                foundation_home.read_head(home_git), foundation_head_before
            )
            self.assertTrue(report["dispatchable"])
            self.assertTrue(built["dispatchable"])
            repo_a_plan_nodes = [
                node
                for node in built["nodes"]
                if node.get("repo_id") == "repoA"
                and node.get("binding") == "execution-plan"
            ]
            self.assertEqual(
                [node["artifact_ref"] for node in repo_a_plan_nodes],
                [plan_ref],
            )
            self.assertEqual(
                built["nodes"][0]["generation"],
                built["generation"],
            )

    def test_f11_manifest_symlinks_are_rejected_before_scan(self):
        with tempfile.TemporaryDirectory(prefix="f11-release-") as temporary:
            root = Path(temporary)
            outside = root / "outside"
            outside.mkdir()
            (outside / "clean.py").write_text("x = 1\n", encoding="utf-8")
            repo = _scanner_repo(root, "source-link/")
            os.symlink(outside, repo / "source-link")
            environment, ledger = _scanner_call_ledger(root)

            result = _run_scanner(repo, environment=environment)

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual(ledger.read_text(encoding="utf-8"), "", result.stdout)
            self.assertIn("target is a symlink", result.stdout)
            self.assertNotIn("Secret scan targets:", result.stdout)
            self.assertNotIn("PASS:", result.stdout)
            self.assertNotIn("CLEAR:", result.stdout)
            self.assertNotIn("Secret preflight result: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
