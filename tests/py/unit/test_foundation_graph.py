"""S4 — provenance graph (spec FR-004/FR-007, D-008/D-009).

Pure logic over published envelopes: union-acyclic + same-kind supersedes
validation, bidirectional direct edges, and typed transitive closure returned
as a DAG edge set (all branches, no currentness pick). Rebuilt from envelopes
each call (D-006/D-009), so freshness is the caller's (core) concern.
"""

import hashlib
import unittest

from foundation import errors, graph


def _ref(repo, kind="prd", oid=None):
    # Derive a valid 40-hex commit OID per repo/seed so distinct nodes stay distinct.
    seed = oid or repo
    return {
        "repo_id": repo,
        "commit_oid": hashlib.sha1(seed.encode()).hexdigest(),
        "path": "a.md",
        "digest": "d" * 64,
        "artifact_kind": kind,
    }


def _env(subject, relations=None):
    return {"artifact_ref": subject, "relations": relations or []}


class TestAcyclic(unittest.TestCase):
    def test_self_edge_fails(self):
        a = _ref("a")
        env = _env(a, [{"kind": "derived-from", "object": a}])
        with self.assertRaises(errors.FoundationError) as ctx:
            graph.check_acyclic([env])
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_two_node_cycle_fails(self):
        a, b = _ref("a"), _ref("b")
        envs = [
            _env(a, [{"kind": "derived-from", "object": b}]),
            _env(b, [{"kind": "derived-from", "object": a}]),
        ]
        with self.assertRaises(errors.FoundationError):
            graph.check_acyclic(envs)

    def test_dag_ok(self):
        a, b, c = _ref("a"), _ref("b"), _ref("c")
        envs = [
            _env(a, [{"kind": "derived-from", "object": b}]),
            _env(b, [{"kind": "derived-from", "object": c}]),
        ]
        graph.check_acyclic(envs)  # no raise

    def test_cross_kind_union_cycle_fails(self):
        # cycle formed across two different relation kinds must still fail.
        a, b = _ref("a"), _ref("b")
        envs = [
            _env(a, [{"kind": "derived-from", "object": b}]),
            _env(b, [{"kind": "evidences", "object": a}]),
        ]
        with self.assertRaises(errors.FoundationError):
            graph.check_acyclic(envs)


class TestSupersedesKinds(unittest.TestCase):
    def test_cross_kind_supersedes_fails(self):
        subj = _ref("s", kind="spec")
        obj = _ref("p", kind="prd")
        with self.assertRaises(errors.FoundationError) as ctx:
            graph.check_supersedes_kinds(subj, [{"kind": "supersedes-artifact", "object": obj}])
        self.assertEqual(ctx.exception.code, errors.SCHEMA_ERROR)

    def test_same_kind_supersedes_ok(self):
        subj = _ref("v2", kind="prd")
        obj = _ref("v1", kind="prd")
        graph.check_supersedes_kinds(subj, [{"kind": "supersedes-artifact", "object": obj}])

    def test_non_supersedes_cross_kind_ok(self):
        subj = _ref("s", kind="spec")
        obj = _ref("p", kind="prd")
        graph.check_supersedes_kinds(subj, [{"kind": "derived-from", "object": obj}])


class TestEdges(unittest.TestCase):
    def test_direct_edges_bidirectional(self):
        a, b = _ref("a"), _ref("b")
        envs = [_env(a, [{"kind": "derived-from", "object": b}])]
        out = graph.direct_edges(envs, a)
        self.assertEqual(len(out["out"]), 1)
        self.assertEqual(out["out"][0]["object"], b)
        self.assertEqual(out["in"], [])
        inb = graph.direct_edges(envs, b)
        self.assertEqual(len(inb["in"]), 1)
        self.assertEqual(inb["in"][0]["subject"], a)

    def test_transitive_follows_chain(self):
        a, b, c = _ref("a"), _ref("b"), _ref("c")
        envs = [
            _env(a, [{"kind": "derived-from", "object": b}]),
            _env(b, [{"kind": "derived-from", "object": c}]),
        ]
        edges = graph.transitive_edges(envs, a, "derived-from")
        pairs = {(e["subject"]["repo_id"], e["object"]["repo_id"]) for e in edges}
        self.assertEqual(pairs, {("a", "b"), ("b", "c")})

    def test_transitive_returns_all_branches_no_currentness(self):
        # X superseded by BOTH y and z: transitive in-view must return both,
        # never pick a single "current" successor (C4 authority isolation).
        x, y, z = _ref("x", "prd"), _ref("y", "prd"), _ref("z", "prd")
        envs = [
            _env(y, [{"kind": "supersedes-artifact", "object": x}]),
            _env(z, [{"kind": "supersedes-artifact", "object": x}]),
        ]
        superseders = {
            e["subject"]["repo_id"]
            for e in graph.transitive_edges(envs, x, "supersedes-artifact")
        }
        self.assertEqual(superseders, {"y", "z"})

    def test_derived_from_closure_does_not_pull_in_siblings(self):
        parent, child, sibling = _ref("parent"), _ref("child"), _ref("sibling")
        envs = [
            _env(child, [{"kind": "derived-from", "object": parent}]),
            _env(sibling, [{"kind": "derived-from", "object": parent}]),
        ]
        edges = graph.transitive_edges(envs, child, "derived-from")
        pairs = {(e["subject"]["repo_id"], e["object"]["repo_id"]) for e in edges}
        self.assertEqual(pairs, {("child", "parent")})

    def test_supersedes_closure_from_mid_chain_excludes_predecessor(self):
        old, middle, newest = _ref("old"), _ref("middle"), _ref("newest")
        envs = [
            _env(middle, [{"kind": "supersedes-artifact", "object": old}]),
            _env(newest, [{"kind": "supersedes-artifact", "object": middle}]),
        ]
        edges = graph.transitive_edges(envs, middle, "supersedes-artifact")
        pairs = {(e["subject"]["repo_id"], e["object"]["repo_id"]) for e in edges}
        self.assertEqual(pairs, {("newest", "middle")})

    def test_transitive_single_kind_only(self):
        a, b, c = _ref("a"), _ref("b"), _ref("c")
        envs = [
            _env(a, [{"kind": "derived-from", "object": b}]),
            _env(b, [{"kind": "evidences", "object": c}]),
        ]
        edges = graph.transitive_edges(envs, a, "derived-from")
        pairs = {(e["subject"]["repo_id"], e["object"]["repo_id"]) for e in edges}
        self.assertEqual(pairs, {("a", "b")})  # does not cross into evidences


if __name__ == "__main__":
    unittest.main()
