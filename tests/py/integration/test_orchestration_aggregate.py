"""Orchestration Slice D: exact invalidation and advisory aggregate (FR-005/006).

Covers qa-plan TC-009/011/012/016/022, including the DAG corpus the PRD requires.

Invalidation has to be exact in BOTH directions, and the second direction is the one
that gets skipped: over-invalidation is invisible in a pass/fail sense, it just makes
everyone redo work, and then people stop trusting the tool. So the corpus asserts
nothing outside the closure is touched, not only that everything inside it is.
"""

import itertools
import unittest

from orchestration import aggregate, errors, invalidation


def _graph(generation=1, digest="g" * 64, edges=None, repos=("repoA", "repoB", "repoC")):
    return {
        "generation": generation,
        "graph_digest": digest,
        "nodes": [{"id": "task:%s" % r, "kind": "repo-task", "repo_id": r,
                   "generation": generation} for r in repos],
        "edges": edges if edges is not None else [],
        "dispatchable": True,
    }


class ExactInvalidation(unittest.TestCase):
    def test_tc009_closure_contains_downstream_and_nothing_else(self):
        edges = [{"kind": "depends-on", "from": "task:repoB", "to": "task:repoA"}]
        old = _graph(edges=edges)
        # repoA's binding changed, so repoA and its dependents are affected.
        new = _graph(edges=edges, digest="h" * 64)
        new["nodes"][0] = dict(new["nodes"][0], binding_digest="changed")
        closure = invalidation.impact_closure(old, new, changed_node_ids=["task:repoA"])
        self.assertEqual(closure["stale_node_ids"], ["task:repoA", "task:repoB"])
        self.assertNotIn("task:repoC", closure["stale_node_ids"])

    def test_independent_change_does_not_reach_unrelated_repos(self):
        edges = [{"kind": "depends-on", "from": "task:repoB", "to": "task:repoA"}]
        old = _graph(edges=edges)
        closure = invalidation.impact_closure(old, old, changed_node_ids=["task:repoC"])
        self.assertEqual(closure["stale_node_ids"], ["task:repoC"])

    def test_tc009_dag_corpus_is_exact_in_both_directions(self):
        """Generated DAGs: closure loses nothing inside and touches nothing outside."""
        node_ids = ["task:n%d" % i for i in range(5)]
        for edge_subset in itertools.combinations(
                [(a, b) for i, a in enumerate(node_ids) for b in node_ids[i + 1:]], 3):
            edges = [{"kind": "depends-on", "from": b, "to": a} for a, b in edge_subset]
            graph = {
                "generation": 1, "graph_digest": "g" * 64,
                "nodes": [{"id": n, "kind": "repo-task", "repo_id": n, "generation": 1}
                          for n in node_ids],
                "edges": edges, "dispatchable": True,
            }
            for changed in node_ids:
                closure = invalidation.impact_closure(graph, graph, [changed])
                expected = _reachable(changed, edges)
                self.assertEqual(set(closure["stale_node_ids"]), expected,
                                 "changed=%s edges=%s" % (changed, edge_subset))

    def test_stale_is_a_new_record_and_does_not_edit_old_results(self):
        graph = _graph()
        results = {"task:repoA": {"state": "OBSERVED", "exit_code": 0}}
        before = dict(results["task:repoA"])
        records = invalidation.stale_records(graph, results, ["task:repoA"])
        self.assertEqual(results["task:repoA"], before)
        self.assertEqual(records[0]["node_id"], "task:repoA")
        self.assertEqual(records[0]["kind"], "STALE")


def _reachable(start, edges):
    """Nodes reachable from `start` following depends-on edges backwards (dependents)."""
    dependents = {}
    for edge in edges:
        dependents.setdefault(edge["to"], []).append(edge["from"])
    seen, stack = {start}, [start]
    while stack:
        current = stack.pop()
        for dependent in dependents.get(current, []):
            if dependent not in seen:
                seen.add(dependent)
                stack.append(dependent)
    return seen


class AggregatePrecedence(unittest.TestCase):
    def test_tc016_precedence_is_stale_then_failed_then_blocked(self):
        state = aggregate.aggregate(
            _graph(),
            results={"task:repoA": {"state": "FAILED"},
                     "task:repoB": {"state": "BLOCKED"}},
            stale_node_ids=["task:repoC"],
        )
        self.assertEqual(state["aggregate"], "STALE")

    def test_failed_outranks_blocked(self):
        state = aggregate.aggregate(
            _graph(),
            results={"task:repoA": {"state": "FAILED"},
                     "task:repoB": {"state": "BLOCKED"}},
            stale_node_ids=[],
        )
        self.assertEqual(state["aggregate"], "FAILED")

    def test_all_observed_is_advisory_complete(self):
        state = aggregate.aggregate(
            _graph(),
            results={"task:%s" % r: {"state": "OBSERVED"}
                     for r in ("repoA", "repoB", "repoC")},
            stale_node_ids=[],
        )
        self.assertEqual(state["aggregate"], "ADVISORY_COMPLETE")
        self.assertEqual(state["actions"], [])
        self.assertIsNone(state["next_action"])

    def test_tc022_multiple_blockers_expose_all_actions_and_one_next(self):
        state = aggregate.aggregate(
            _graph(),
            results={"task:repoA": {"state": "FAILED"},
                     "task:repoB": {"state": "BLOCKED"}},
            stale_node_ids=["task:repoC"],
        )
        self.assertEqual(len(state["actions"]), 3)
        self.assertEqual(state["next_action"], state["actions"][0])
        # Highest precedence first, then deterministic ordering.
        self.assertEqual(state["actions"][0]["state"], "STALE")

    def test_tc016_every_aggregate_state_is_reachable_and_labelled(self):
        """The Gherkin asks for every state, not just the two easy ones.

        Precedence is a fixed tuple so the risk is low, but a PASS resting on two states
        outruns its evidence -- BLOCKED-only and IN_PROGRESS had no assertion anywhere.
        """
        graph = _graph(repos=("repoA",))
        cases = [
            ("ADVISORY_COMPLETE", {"task:repoA": {"state": "OBSERVED"}}, []),
            ("BLOCKED", {"task:repoA": {"state": "BLOCKED"}}, []),
            ("FAILED", {"task:repoA": {"state": "FAILED"}}, []),
            ("STALE", {}, ["task:repoA"]),
            ("IN_PROGRESS", {}, []),
        ]
        for expected, results, stale in cases:
            state = aggregate.aggregate(graph, results, stale)
            self.assertEqual(state["aggregate"], expected, expected)
        self.assertEqual({c[0] for c in cases}, set(aggregate.AGGREGATE_STATES))

    def test_tc016_stale_and_blocked_overlap_resolves_to_stale(self):
        """The remaining constructible overlap the corpus did not cover."""
        state = aggregate.aggregate(
            _graph(),
            results={"task:repoA": {"state": "BLOCKED"}},
            stale_node_ids=["task:repoA"],
        )
        self.assertEqual(state["aggregate"], "STALE")
        for_a = [a for a in state["actions"] if a["node_id"] == "task:repoA"]
        self.assertEqual(len(for_a), 1)
        self.assertEqual(for_a[0]["state"], "STALE")

    def test_one_target_keeps_only_its_highest_precedence_action(self):
        state = aggregate.aggregate(
            _graph(),
            results={"task:repoA": {"state": "FAILED"}},
            stale_node_ids=["task:repoA"],
        )
        for_a = [a for a in state["actions"] if a["node_id"] == "task:repoA"]
        self.assertEqual(len(for_a), 1)
        self.assertEqual(for_a[0]["state"], "STALE")

    def test_unknown_state_is_an_error(self):
        with self.assertRaises(errors.OrchestrationError) as caught:
            aggregate.aggregate(_graph(),
                                results={"task:repoA": {"state": "MADE_UP"}},
                                stale_node_ids=[])
        self.assertEqual(caught.exception.code, errors.UNKNOWN_EVIDENCE_STATE)

    def test_a_result_for_a_node_outside_the_graph_is_refused(self):
        """Fail-closed. Ranking an action for a node nobody can act on is worse than
        refusing the input, and it previously produced a phantom action with repo_id
        None."""
        with self.assertRaises(errors.OrchestrationError) as caught:
            aggregate.aggregate(_graph(), {"task:ghost": {"state": "FAILED"}}, [])
        self.assertEqual(caught.exception.code, errors.UNKNOWN_EVIDENCE_STATE)

    def test_a_stale_id_outside_the_graph_is_refused(self):
        with self.assertRaises(errors.OrchestrationError):
            aggregate.aggregate(_graph(), {}, stale_node_ids=["task:ghost"])

    def test_an_edge_to_an_unknown_node_raises_a_typed_error(self):
        """Previously a raw KeyError, indistinguishable from a bug to the caller."""
        bad = _graph(edges=[{"kind": "depends-on", "from": "task:repoA",
                             "to": "task:ghost"}])
        with self.assertRaises(errors.OrchestrationError) as caught:
            aggregate.aggregate(bad, {}, [])
        self.assertEqual(caught.exception.code, errors.UNKNOWN_EVIDENCE_STATE)

    def test_tc011_a_trusted_looking_field_cannot_raise_the_aggregate(self):
        state = aggregate.aggregate(
            _graph(repos=("repoA",)),
            results={"task:repoA": {"state": "OBSERVED", "trusted": True,
                                    "verified_by": "totally-real-ci"}},
            stale_node_ids=[],
        )
        self.assertEqual(state["aggregate"], "ADVISORY_COMPLETE")
        self.assertNotIn("VERIFIED", str(state))


class VerificationBoundary(unittest.TestCase):
    def test_tc012_verify_unavailable_does_not_change_the_aggregate(self):
        results = {"task:%s" % r: {"state": "OBSERVED"}
                   for r in ("repoA", "repoB", "repoC")}
        state = aggregate.aggregate(_graph(), results, stale_node_ids=[])
        query = aggregate.verify_capability(provider=None)
        self.assertEqual(query["result"], "VERIFICATION_UNAVAILABLE")
        after = aggregate.aggregate(_graph(), results, stale_node_ids=[])
        self.assertEqual(state, after)

    def test_verify_never_reports_verified_in_v1(self):
        self.assertNotIn("VERIFIED", aggregate.AGGREGATE_STATES)


if __name__ == "__main__":
    unittest.main()
