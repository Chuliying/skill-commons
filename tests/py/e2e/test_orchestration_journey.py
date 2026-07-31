"""Three-repo advisory journey, end to end (PRD AC-007, qa-plan TC-007).

bootstrap -> bind -> graph -> project -> apply -> dispatch -> evidence -> aggregate,
over real temporary Git repos and with no network access of any kind. The PRD requires
the core to reach ADVISORY_COMPLETE without network, remote CI or a trusted provider,
so this drives the whole chain rather than each module in isolation.

Each slice already has unit-level coverage. What this adds is the seams: a graph built
in one module being projected by another, applied receipts feeding readiness, and
evidence rolling up into one aggregate.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home
from orchestration import aggregate, execution, graph, identity, invalidation, projection


COLLECTION = "initiative/home"


def _make_repo(prefix):
    work = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "init", "-q", work], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key, value in (("user.name", "t"), ("user.email", "t@e")):
        subprocess.run(["git", "-C", work, "config", key, value], check=True)
    return work


def _commit(work, rel, content):
    import hashlib

    with open(os.path.join(work, rel), "w", encoding="utf-8") as handle:
        handle.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True)
    subprocess.run(["git", "-C", work, "commit", "-qm", "add"], check=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"],
                         stdout=subprocess.PIPE, check=True).stdout.decode().strip()
    return oid, hashlib.sha256(content.encode("utf-8")).hexdigest()


class ThreeRepoJourney(unittest.TestCase):
    def setUp(self):
        self.home_work = _make_repo("j-home-")
        self.foundation = os.path.join(self.home_work, ".git")
        self.works = {}
        for repo_id in ("repoA", "repoB", "repoC"):
            self.works[repo_id] = _make_repo("j-%s-" % repo_id)
        for path in [self.home_work] + list(self.works.values()):
            self.addCleanup(shutil.rmtree, path, ignore_errors=True)
        for repo_id, work in self.works.items():
            core.register(self.foundation, repo_id, os.path.join(work, ".git"),
                          home.read_head(self.foundation))
        self.prd_ref = self._publish("repoA", "initiative.md", "initiative", "prd")

    def _publish(self, repo_id, rel, content, kind):
        oid, digest = _commit(self.works[repo_id], rel, content)
        ref = {"repo_id": repo_id, "commit_oid": oid, "path": rel,
               "digest": digest, "artifact_kind": kind}
        # One Foundation home carries ONE collection identity (Legal Home V1); publishing
        # under a per-repo collection would be a split-brain home and is refused.
        core.publish(self.foundation, COLLECTION, ref, [],
                     home.read_head(self.foundation))
        return ref

    def _bootstrap(self):
        registry = [
            {"repo_id": "repoA", "workflow_profile": "team-feature", "owner": "o1"},
            {"repo_id": "repoB", "workflow_profile": "personal-feature", "owner": "o2"},
            {"repo_id": "repoC", "workflow_profile": "personal-feature", "owner": "o3"},
        ]
        assignments = [{"requirement_id": "R1", "repo_id": "repoA"},
                       {"requirement_id": "R2", "repo_id": "repoB"},
                       {"requirement_id": "R3", "repo_id": "repoC"}]
        # repoB depends on repoA; repoC is independent.
        topology = [{"from": "R1", "to": "R2"}]
        return identity.build_slice_proposals(
            self.prd_ref, registry, assignments, topology)

    def _bindings(self):
        return {
            "repoA": {
                "prd": self._publish("repoA", "a-prd.md", "a-prd", "prd"),
                "spec": self._publish("repoA", "a-spec.md", "a-spec", "spec"),
                "qa-plan": self._publish("repoA", "a-qa.md", "a-qa", "qa-plan"),
                "execution-plan": self._publish("repoA", "a-plan.md", "a-plan", "plan"),
            },
            "repoB": {
                "execution-plan": self._publish("repoB", "b-plan.md", "b-plan", "plan"),
            },
            "repoC": {
                "execution-plan": self._publish("repoC", "c-plan.md", "c-plan", "plan"),
            },
        }

    def _build_graph(self, proposals, bindings, generation):
        validated = graph.resolve_and_validate_bindings(bindings, self.foundation)
        return graph.build_graph(proposals, validated, generation)

    def test_journey_reaches_advisory_complete_without_network(self):
        proposals = self._bootstrap()
        built = self._build_graph(proposals, self._bindings(), generation=1)
        self.assertTrue(built["dispatchable"])

        # Every repo owner applies its own projection. Coordinator writes nothing.
        receipts = {}
        for repo_id in ("repoA", "repoB", "repoC"):
            proposal = projection.project(built, repo_id, "plan-%s" % repo_id)
            plan = {"digest": "plan-%s" % repo_id, "external_block": "",
                    "tasks": ["local"]}
            applied = projection.apply(proposal, plan)
            self.assertEqual(applied["state"], "APPLIED")
            receipts[repo_id] = applied["receipt"]
        self.assertEqual(projection.apply_status(built, receipts)["pending_repo_ids"], [])

        # Execute in dependency order; repoB is not ready until repoA is OBSERVED.
        journal = execution.new_journal()
        early = execution.dispatch(built, "task:repoB", {"max_retries": 1}, journal)
        self.assertEqual(early["state"], "BLOCKED")

        for node_id in ("task:repoA", "task:repoB", "task:repoC"):
            dispatched = execution.dispatch(built, node_id, {"max_retries": 1}, journal)
            self.assertEqual(dispatched["state"], "DISPATCHED", node_id)
            execution.record_result(
                journal, dispatched["attempt_digest"], "OBSERVED", exit_code=0
            )

        rolled_up = aggregate.aggregate(built, journal["results"], stale_node_ids=[])
        self.assertEqual(rolled_up["aggregate"], "ADVISORY_COMPLETE")
        self.assertEqual(rolled_up["actions"], [])
        self.assertIsNone(rolled_up["next_action"])

        # The trusted boundary stays explicit even on a fully completed journey.
        self.assertEqual(aggregate.verify_capability(None)["result"],
                         "VERIFICATION_UNAVAILABLE")

    def test_upstream_rebind_makes_only_downstream_stale(self):
        proposals = self._bootstrap()
        bindings = self._bindings()
        first = self._build_graph(proposals, bindings, generation=1)

        journal = execution.new_journal()
        for node_id in ("task:repoA", "task:repoB", "task:repoC"):
            dispatched = execution.dispatch(
                first, node_id, {"max_retries": 1}, journal
            )
            execution.record_result(
                journal, dispatched["attempt_digest"], "OBSERVED", exit_code=0
            )
        self.assertEqual(
            aggregate.aggregate(first, journal["results"], [])["aggregate"],
            "ADVISORY_COMPLETE")

        # repoA republishes its spec: a new generation, and only repoA/repoB go stale.
        bindings["repoA"]["spec"] = self._publish("repoA", "a-spec.md", "a-spec-v2", "spec")
        second = self._build_graph(proposals, bindings, generation=2)
        self.assertNotEqual(first["graph_digest"], second["graph_digest"])

        closure = invalidation.impact_closure(first, second, ["task:repoA"])
        self.assertEqual(closure["stale_node_ids"], ["task:repoA", "task:repoB"])
        self.assertIn("task:repoC", closure["unaffected_node_ids"])

        # Old evidence bytes are untouched; STALE is a separate record.
        before = dict(journal["results"]["task:repoA"])
        records = invalidation.stale_records(second, journal["results"],
                                            closure["stale_node_ids"])
        self.assertEqual(journal["results"]["task:repoA"], before)
        self.assertEqual({r["node_id"] for r in records},
                         {"task:repoA", "task:repoB"})

        rolled_up = aggregate.aggregate(second, journal["results"],
                                        closure["stale_node_ids"])
        self.assertEqual(rolled_up["aggregate"], "STALE")
        self.assertEqual(rolled_up["next_action"]["action"], "REBIND_IMPACT")
        # repoC keeps its result and is not asked to redo anything.
        self.assertNotIn("task:repoC",
                         [a["node_id"] for a in rolled_up["actions"]])

    def test_missing_binding_blocks_only_its_own_slice(self):
        proposals = self._bootstrap()
        bindings = self._bindings()
        del bindings["repoA"]["qa-plan"]          # team-feature requires it
        built = self._build_graph(proposals, bindings, generation=1)
        self.assertFalse(built["dispatchable"])

        report = {entry["repo_id"]: entry for entry in built["binding_report"]["slices"]}
        self.assertEqual(report["repoA"]["state"], "BLOCKED")
        self.assertEqual(report["repoB"]["state"], "CURRENT")
        self.assertEqual(report["repoC"]["state"], "CURRENT")
        # Projection is refused while the graph is not dispatchable.
        with self.assertRaises(Exception):
            projection.project(built, "repoC", "plan-repoC")


if __name__ == "__main__":
    unittest.main()
