"""Orchestration Slice B: repo-owned projection and recoverable apply (FR-003).

Covers qa-plan TC-005/006/017.

The property that matters here is ownership: the coordinator may compute what a repo
should do, and may never write it. Every test either checks that a projection is
read-only, or that apply refuses when its compare-and-swap precondition no longer
holds. There is no cross-repo atomicity to test, because the PRD explicitly does not
claim any (D-O3) -- apply is per repo and resumable instead.
"""

import unittest

from orchestration import errors, projection


def _plan(digest="p" * 64, external=""):
    return {"digest": digest, "external_block": external, "tasks": ["local-1"]}


class ProjectionIsReadOnly(unittest.TestCase):
    def setUp(self):
        self.graph = {
            "generation": 1,
            "graph_digest": "g" * 64,
            "nodes": [{"id": "task:repoA", "kind": "repo-task", "repo_id": "repoA",
                       "generation": 1}],
            "edges": [],
            "dispatchable": True,
        }

    def test_tc005_projection_does_not_mutate_the_plan(self):
        plan = _plan()
        before = dict(plan)
        proposal = projection.project(self.graph, "repoA", plan["digest"])
        self.assertEqual(plan, before)
        self.assertEqual(proposal["expected_plan_digest"], plan["digest"])
        self.assertEqual(proposal["graph_digest"], self.graph["graph_digest"])
        self.assertEqual(proposal["generation"], 1)
        # A proposal is inert until a repo-local apply consumes it.
        self.assertNotIn("receipt", proposal)

    def test_projection_is_deterministic(self):
        first = projection.project(self.graph, "repoA", "p" * 64)
        second = projection.project(self.graph, "repoA", "p" * 64)
        self.assertEqual(first, second)

    def test_projection_for_an_unknown_repo_fails(self):
        with self.assertRaises(errors.OrchestrationError):
            projection.project(self.graph, "repoZ", "p" * 64)

    def test_non_dispatchable_graph_cannot_be_projected(self):
        blocked = dict(self.graph, dispatchable=False)
        with self.assertRaises(errors.OrchestrationError) as caught:
            projection.project(blocked, "repoA", "p" * 64)
        self.assertEqual(caught.exception.code, errors.MISSING_BINDING)


class ApplyIsRepoOwnedAndCAS(unittest.TestCase):
    def setUp(self):
        self.graph = {
            "generation": 1,
            "graph_digest": "g" * 64,
            "nodes": [{"id": "task:repoA", "kind": "repo-task", "repo_id": "repoA",
                       "generation": 1}],
            "edges": [],
            "dispatchable": True,
        }
        self.proposal = projection.project(self.graph, "repoA", "p" * 64)

    def test_apply_updates_only_the_generated_external_block(self):
        plan = _plan(external="stale external")
        applied = projection.apply(self.proposal, plan)
        self.assertEqual(applied["state"], "APPLIED")
        # Local task list is repo-owned and must survive untouched.
        self.assertEqual(applied["plan"]["tasks"], plan["tasks"])
        self.assertNotEqual(applied["plan"]["external_block"], "stale external")
        receipt = applied["receipt"]
        self.assertEqual(receipt["graph_digest"], self.graph["graph_digest"])
        self.assertEqual(receipt["generation"], 1)
        self.assertEqual(receipt["repo_id"], "repoA")

    def test_tc017_cas_conflict_blocks_with_zero_writes(self):
        moved = _plan(digest="q" * 64, external="local edit")
        before = dict(moved)
        result = projection.apply(self.proposal, moved)
        self.assertEqual(result["state"], "BLOCKED")
        self.assertEqual(result["reason"], errors.CAS_CONFLICT)
        # Both the local plan and the original proposal survive.
        self.assertEqual(moved, before)
        self.assertNotIn("receipt", result)
        self.assertEqual(self.proposal["expected_plan_digest"], "p" * 64)

    def test_apply_is_idempotent_for_the_same_proposal(self):
        plan = _plan()
        first = projection.apply(self.proposal, plan)
        second = projection.apply(self.proposal, first["plan"])
        # The second apply recognises its own receipt rather than writing twice.
        self.assertEqual(second["state"], "APPLIED")
        self.assertEqual(first["receipt"], second["receipt"])


class PartialApplyResumes(unittest.TestCase):
    def _graph(self):
        return {
            "generation": 1,
            "graph_digest": "g" * 64,
            "nodes": [
                {"id": "task:repoA", "kind": "repo-task", "repo_id": "repoA",
                 "generation": 1},
                {"id": "task:repoB", "kind": "repo-task", "repo_id": "repoB",
                 "generation": 1},
                {"id": "task:repoC", "kind": "repo-task", "repo_id": "repoC",
                 "generation": 1},
            ],
            # repoB depends on repoA; repoC is independent.
            "edges": [{"kind": "depends-on", "from": "task:repoB", "to": "task:repoA"}],
            "dispatchable": True,
        }

    def test_tc006_dependent_stays_blocked_while_independent_stays_ready(self):
        graph = self._graph()
        receipts = {
            # repoA never applied: it crashed before apply.
            "repoC": projection.apply(
                projection.project(graph, "repoC", "p" * 64), _plan())["receipt"],
        }
        status = projection.apply_status(graph, receipts)
        self.assertEqual(status["pending_repo_ids"], ["repoA", "repoB"])
        self.assertEqual(status["blocked_node_ids"], ["task:repoB"])
        # Full-set assertions. An assertIn here would pass even if every unapplied node
        # were also reported ready, which is exactly the defect this AC guards.
        self.assertEqual(status["ready_node_ids"], ["task:repoC"])
        self.assertEqual(status["awaiting_apply_node_ids"], ["task:repoA"])

    def test_a_node_whose_repo_never_applied_is_not_ready(self):
        graph = self._graph()
        status = projection.apply_status(graph, {})
        self.assertEqual(status["ready_node_ids"], [])
        self.assertEqual(status["awaiting_apply_node_ids"], ["task:repoA", "task:repoC"])
        self.assertEqual(status["blocked_node_ids"], ["task:repoB"])

    def test_tc006_resume_does_not_change_existing_receipts(self):
        graph = self._graph()
        applied_c = projection.apply(
            projection.project(graph, "repoC", "p" * 64), _plan())
        receipts = {"repoC": applied_c["receipt"]}
        before = dict(receipts["repoC"])
        applied_a = projection.apply(
            projection.project(graph, "repoA", "p" * 64), _plan())
        receipts["repoA"] = applied_a["receipt"]
        self.assertEqual(receipts["repoC"], before)
        status = projection.apply_status(graph, receipts)
        self.assertEqual(status["pending_repo_ids"], ["repoB"])

    def test_mixed_generation_receipts_block_dependents(self):
        graph = self._graph()
        stale = projection.apply(
            projection.project(dict(graph, generation=0, graph_digest="h" * 64),
                               "repoA", "p" * 64), _plan())["receipt"]
        status = projection.apply_status(graph, {"repoA": stale})
        # A receipt from another generation does not satisfy this graph.
        self.assertIn("repoA", status["pending_repo_ids"])
        self.assertIn("task:repoB", status["blocked_node_ids"])


if __name__ == "__main__":
    unittest.main()
