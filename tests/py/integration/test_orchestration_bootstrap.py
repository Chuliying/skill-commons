"""Orchestration Slice A: identity, bootstrap slices, and the Work Graph.

Covers qa-plan TC-001/002/003/004/013/014/020.

The bootstrap step exists to break a circular dependency the PRD calls out: an earlier
design required participant Spec/QA/plan refs in order to produce the slices that told
each participant what to build. So these tests assert what bootstrap must NOT need as
much as what it produces.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home
from orchestration import errors, graph, identity


def _make_repo(prefix):
    work = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "init", "-q", work], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key, value in (("user.name", "t"), ("user.email", "t@e")):
        subprocess.run(["git", "-C", work, "config", key, value], check=True)
    return work


def _commit_file(work, rel, content):
    import hashlib

    with open(os.path.join(work, rel), "w", encoding="utf-8") as handle:
        handle.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True)
    subprocess.run(["git", "-C", work, "commit", "-qm", "add"], check=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"],
                         stdout=subprocess.PIPE, check=True).stdout.decode().strip()
    return oid, hashlib.sha256(content.encode("utf-8")).hexdigest()


class SliceABase(unittest.TestCase):
    def setUp(self):
        self.home_work = _make_repo("bs-home-")
        self.foundation = os.path.join(self.home_work, ".git")
        self.repo_a = _make_repo("bs-a-")
        self.repo_b = _make_repo("bs-b-")
        for path in (self.home_work, self.repo_a, self.repo_b):
            self.addCleanup(shutil.rmtree, path, ignore_errors=True)
        for repo_id, work in (("repoA", self.repo_a), ("repoB", self.repo_b)):
            core.register(self.foundation, repo_id, os.path.join(work, ".git"),
                          home.read_head(self.foundation))
        self.prd_ref = self._publish("repoA", self.repo_a, "initiative.md", "PRD", "prd")

    def _publish(self, repo_id, work, rel, content, kind):
        oid, digest = _commit_file(work, rel, content)
        ref = {"repo_id": repo_id, "commit_oid": oid, "path": rel,
               "digest": digest, "artifact_kind": kind}
        core.publish(self.foundation, "orchestration/bootstrap", ref, [],
                     home.read_head(self.foundation))
        return ref

    def _registry(self):
        return [
            {"repo_id": "repoA", "workflow_profile": "team-feature", "owner": "o1"},
            {"repo_id": "repoB", "workflow_profile": "personal-feature", "owner": "o2"},
        ]

    def _assignments(self):
        return [{"requirement_id": "R1", "repo_id": "repoA"},
                {"requirement_id": "R2", "repo_id": "repoB"}]

    def _validated_bindings(self, bindings):
        return graph.resolve_and_validate_bindings(bindings, self.foundation)

    def _build_graph(self, proposals, bindings, generation):
        return graph.build_graph(
            proposals, self._validated_bindings(bindings), generation
        )


class Bootstrap(SliceABase):
    def test_tc001_bootstrap_needs_no_participant_design_artifacts(self):
        proposals = identity.build_slice_proposals(
            self.prd_ref, self._registry(), self._assignments(),
            [{"from": "R1", "to": "R2"}],
        )
        self.assertEqual(sorted(p["repo_id"] for p in proposals["slices"]),
                         ["repoA", "repoB"])
        # Nothing in a proposal may demand an artifact the participant has not built.
        for proposal in proposals["slices"]:
            self.assertNotIn("spec_ref", proposal)
            self.assertNotIn("qa_ref", proposal)
            self.assertNotIn("plan_ref", proposal)

    def test_tc020_owner_declared_topology_is_preserved_not_inferred(self):
        declared = [{"from": "R1", "to": "R2"}]
        proposals = identity.build_slice_proposals(
            self.prd_ref, self._registry(), self._assignments(), declared)
        edges = proposals["topology"]
        self.assertEqual(edges, declared)
        # An undeclared reverse edge must not appear.
        self.assertNotIn({"from": "R2", "to": "R1"}, edges)

    def test_tc013_bootstrap_is_deterministic_from_committed_inputs(self):
        args = (self.prd_ref, self._registry(), self._assignments(),
                [{"from": "R1", "to": "R2"}])
        self.assertEqual(identity.build_slice_proposals(*args),
                         identity.build_slice_proposals(*args))

    def test_unsupported_profile_fails_at_bootstrap(self):
        registry = self._registry()
        registry[0]["workflow_profile"] = "some-other-profile"
        with self.assertRaises(errors.OrchestrationError) as caught:
            identity.build_slice_proposals(
                self.prd_ref, registry, self._assignments(), [])
        self.assertEqual(caught.exception.code, errors.UNSUPPORTED_PROFILE)

    def test_tc004_duplicate_and_case_folded_repo_ids_fail_before_writes(self):
        registry = self._registry() + [
            {"repo_id": "repoa", "workflow_profile": "team-feature", "owner": "o3"}]
        with self.assertRaises(errors.OrchestrationError) as caught:
            identity.build_slice_proposals(
                self.prd_ref, registry, self._assignments(), [])
        self.assertEqual(caught.exception.code, errors.DUPLICATE_REPO_ID)

    def test_requirement_assigned_to_two_repos_is_an_ownership_conflict(self):
        assignments = self._assignments() + [{"requirement_id": "R1", "repo_id": "repoB"}]
        with self.assertRaises(errors.OrchestrationError) as caught:
            identity.build_slice_proposals(
                self.prd_ref, self._registry(), assignments, [])
        self.assertEqual(caught.exception.code, errors.OWNERSHIP_CONFLICT)

    def test_unassigned_requirement_endpoint_fails(self):
        with self.assertRaises(errors.OrchestrationError):
            identity.build_slice_proposals(
                self.prd_ref, self._registry(), self._assignments(),
                [{"from": "R1", "to": "R404"}])


class WorkGraph(SliceABase):
    def _proposals(self):
        return identity.build_slice_proposals(
            self.prd_ref, self._registry(), self._assignments(),
            [{"from": "R1", "to": "R2"}])

    def _full_bindings(self):
        """team-feature needs PRD/Spec/QA/plan; personal-feature needs a plan.

        Memoized: publishing is a real commit, so a second call with identical content
        would have nothing to stage and `git commit` would fail. Tests that need two
        graph generations from the same bindings rely on this returning the same refs.
        """
        if getattr(self, "_bindings_cache", None) is not None:
            return {repo: dict(entries) for repo, entries in self._bindings_cache.items()}
        self._bindings_cache = self._publish_full_bindings()
        return {repo: dict(entries) for repo, entries in self._bindings_cache.items()}

    def _publish_full_bindings(self):
        return {
            "repoA": {
                "prd": self._publish("repoA", self.repo_a, "a-prd.md", "p", "prd"),
                "spec": self._publish("repoA", self.repo_a, "a-spec.md", "s", "spec"),
                "qa-plan": self._publish("repoA", self.repo_a, "a-qa.md", "q", "qa-plan"),
                "execution-plan": self._publish("repoA", self.repo_a, "a-plan.md", "l", "plan"),
            },
            "repoB": {
                "execution-plan": self._publish("repoB", self.repo_b, "b-plan.md", "l", "plan"),
            },
        }

    def test_tc003_complete_bindings_create_a_dispatchable_graph(self):
        built = self._build_graph(self._proposals(), self._full_bindings(), generation=1)
        self.assertEqual(built["generation"], 1)
        kinds = {node["kind"] for node in built["nodes"]}
        self.assertTrue(kinds <= set(graph.NODE_KINDS), kinds)
        edge_kinds = {edge["kind"] for edge in built["edges"]}
        self.assertTrue(edge_kinds <= set(graph.EDGE_KINDS), edge_kinds)
        self.assertEqual(built["ready_order"], ["R1", "R2"])
        self.assertTrue(built["dispatchable"])

    def test_tc002_missing_binding_blocks_only_the_affected_slice(self):
        bindings = self._full_bindings()
        del bindings["repoA"]["spec"]  # team-feature requires it
        report = graph.binding_report(
            self._proposals(), self._validated_bindings(bindings)
        )
        blocked = {entry["repo_id"]: entry for entry in report["slices"]}
        self.assertEqual(blocked["repoA"]["state"], "BLOCKED")
        self.assertEqual(blocked["repoB"]["state"], "CURRENT")
        self.assertEqual(blocked["repoA"]["missing"], ["spec"])
        # Exactly one recovery action, so the operator is never asked to choose.
        self.assertIsInstance(blocked["repoA"]["recovery_action"], str)

    def test_missing_binding_graph_is_not_dispatchable(self):
        bindings = self._full_bindings()
        del bindings["repoB"]["execution-plan"]
        built = self._build_graph(self._proposals(), bindings, generation=1)
        self.assertFalse(built["dispatchable"])

    def test_unknown_node_or_edge_kind_is_rejected(self):
        built = self._build_graph(self._proposals(), self._full_bindings(), generation=1)
        poisoned = dict(built, edges=built["edges"] + [
            {"kind": "smuggled-edge", "from": "R1", "to": "R2"}])
        with self.assertRaises(errors.OrchestrationError) as caught:
            graph.validate_graph(poisoned)
        self.assertEqual(caught.exception.code, errors.UNKNOWN_GRAPH_KIND)

    def test_mixed_generation_is_rejected(self):
        first = self._build_graph(self._proposals(), self._full_bindings(), generation=1)
        second = self._build_graph(self._proposals(), self._full_bindings(), generation=2)
        mixed = dict(first, nodes=first["nodes"] + second["nodes"])
        with self.assertRaises(errors.OrchestrationError) as caught:
            graph.validate_graph(mixed)
        self.assertEqual(caught.exception.code, errors.MIXED_GENERATION)

    def test_tc013_graph_rebuild_is_byte_identical(self):
        bindings = self._full_bindings()
        proposals = self._proposals()
        self.assertEqual(self._build_graph(proposals, bindings, generation=1),
                         self._build_graph(proposals, bindings, generation=1))

    def test_rebind_creates_a_new_generation_without_touching_the_old(self):
        bindings = self._full_bindings()
        proposals = self._proposals()
        first = self._build_graph(proposals, bindings, generation=1)
        snapshot = self._build_graph(proposals, bindings, generation=1)
        second = self._build_graph(proposals, bindings, generation=2)
        self.assertEqual(first, snapshot)          # old bytes unchanged
        self.assertNotEqual(first["graph_digest"], second["graph_digest"])


class Compatibility(SliceABase):
    def test_tc014_not_using_cross_repo_leaves_foundation_state_alone(self):
        before = home.read_head(self.foundation)
        identity.build_slice_proposals(
            self.prd_ref, self._registry(), self._assignments(), [])
        self._build_graph(
            self._registry()
            and identity.build_slice_proposals(
                self.prd_ref, self._registry(), self._assignments(), []
            ),
            {"repoA": {}, "repoB": {}},
            generation=1,
        )
        # Bootstrap and graph building are pure: they read Foundation, never write it.
        self.assertEqual(home.read_head(self.foundation), before)


if __name__ == "__main__":
    unittest.main()
