"""S8 — adversarial cells (spec qa-plan ADV rows; authority isolation).

Fork/clone false-replay (ADV-15/TC-B02) and the authority-isolation golden
(ADV-19): the Foundation must never emit consumer-owned verdict fields.
Note: this implementation keeps NO derived index (graph is rebuilt from head
each call, D-006/D-009), so the stale-index cell is N/A by construction.
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, errors, home

# Closed-shape whitelists: query/change-fact may ONLY carry these fields, and
# resolvability may ONLY be one of these values. A whitelist (not a blacklist)
# catches novel authority keys; the value check catches a SUPERSEDED/verdict
# smuggled as a value rather than a key.
_CHANGE_FACT_KEYS = {"resolvability", "supersedes_in_edges"}
# query (spec v1.1.0) additionally carries resolvability (a closed-enum status fact)
# and home_revision (the captured Home head OID) — both facts, never a verdict.
_QUERY_KEYS = {"direct_edges", "transitive", "resolvability", "home_revision"}
_TRANSITIVE_KEYS = {"kind", "edges"}
_EDGE_KEYS = {"kind", "subject", "object"}


def _make_git(prefix):
    d = tempfile.mkdtemp(prefix=prefix)
    for a in (["init", "-q"], ["config", "user.email", "t@e"], ["config", "user.name", "t"]):
        subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
    return d


def _commit(work, rel, content):
    with open(os.path.join(work, rel), "w", encoding="utf-8") as fh:
        fh.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True, capture_output=True)
    subprocess.run(["git", "-C", work, "commit", "-q", "-m", "x"], check=True, capture_output=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    return oid, hashlib.sha256(content.encode()).hexdigest()


def _ref(repo, oid, dg, path="a.md", kind="prd"):
    return {"repo_id": repo, "commit_oid": oid, "path": path, "digest": dg, "artifact_kind": kind}


class TestForkCloneFalseReplay(unittest.TestCase):
    def setUp(self):
        self.hw = _make_git("fdn-adv-home-")
        self.home = os.path.join(self.hw, ".git")
        self.aw = _make_git("fdn-adv-A-")
        self.addCleanup(shutil.rmtree, self.hw, ignore_errors=True)
        self.addCleanup(shutil.rmtree, self.aw, ignore_errors=True)

    def test_same_oid_two_repos_are_distinct_refs(self):
        oid, dg = _commit(self.aw, "a.md", "shared\n")
        # Clone repoA -> repoB: identical commit OID, different locator.
        bw = tempfile.mkdtemp(prefix="fdn-adv-B-")
        self.addCleanup(shutil.rmtree, bw, ignore_errors=True)
        subprocess.run(["git", "clone", "-q", self.aw, bw], check=True, capture_output=True)
        a_git, b_git = os.path.join(self.aw, ".git"), os.path.join(bw, ".git")

        core.register(self.home, "repoA", a_git, home.read_head(self.home))
        core.register(self.home, "repoB", b_git, home.read_head(self.home))

        r_a = core.publish(self.home, "home/collection", _ref("repoA", oid, dg), [], home.read_head(self.home))
        r_b = core.publish(self.home, "home/collection", _ref("repoB", oid, dg), [], home.read_head(self.home))
        # Same OID, different repo_id -> distinct envelope digests, neither a replay.
        self.assertFalse(r_a["replay"])
        self.assertFalse(r_b["replay"])
        self.assertNotEqual(r_a["receipt"]["envelope_digest"], r_b["receipt"]["envelope_digest"])
        # Each resolves against its own repo's object store.
        self.assertEqual(core.resolve(self.home, _ref("repoA", oid, dg))["bytes"], b"shared\n")
        self.assertEqual(core.resolve(self.home, _ref("repoB", oid, dg))["bytes"], b"shared\n")


class TestAuthorityIsolationGolden(unittest.TestCase):
    def setUp(self):
        self.hw = _make_git("fdn-adv2-home-")
        self.home = os.path.join(self.hw, ".git")
        self.aw = _make_git("fdn-adv2-A-")
        self.addCleanup(shutil.rmtree, self.hw, ignore_errors=True)
        self.addCleanup(shutil.rmtree, self.aw, ignore_errors=True)
        core.register(self.home, "repoA", os.path.join(self.aw, ".git"), home.read_head(self.home))

    def _assert_edges_shape(self, edges):
        for edge in edges:
            self.assertLessEqual(set(edge), _EDGE_KEYS, f"edge carries extra field: {set(edge)}")

    def _assert_resolvability_shape(self, value):
        if value == "RESOLVABLE":
            return
        self.assertEqual(set(value), {"status", "reason"})
        self.assertEqual(value["status"], "UNRESOLVABLE")
        self.assertIn(value["reason"], errors.UNRESOLVABLE_REASONS)

    def test_query_and_change_fact_emit_no_verdict(self):
        o_old, d_old = _commit(self.aw, "old.md", "old\n")
        old = _ref("repoA", o_old, d_old, path="old.md")
        core.publish(self.home, "home/collection", old, [], home.read_head(self.home))
        o_new, d_new = _commit(self.aw, "new.md", "new\n")
        rel = [{"kind": "supersedes-artifact", "object": old}]
        core.publish(
            self.home,
            "home/collection",
            _ref("repoA", o_new, d_new, path="new.md"),
            rel,
            home.read_head(self.home),
        )

        fact = core.change_fact(self.home, old)
        # Closed shape: no novel authority key can appear.
        self.assertEqual(set(fact), _CHANGE_FACT_KEYS)
        # Value check: resolvability is a closed enum -> a SUPERSEDED/verdict value is rejected.
        self._assert_resolvability_shape(fact["resolvability"])
        # Supersession is a raw in-edge (subject/kind/object), not a verdict.
        self.assertEqual(len(fact["supersedes_in_edges"]), 1)
        self._assert_edges_shape(fact["supersedes_in_edges"])

        q = core.query(self.home, old, kind="supersedes-artifact")
        self.assertEqual(set(q), _QUERY_KEYS)
        self.assertEqual(set(q["direct_edges"]), {"out", "in"})
        self.assertIn(
            q["resolvability"],
            {"RESOLVABLE", *errors.UNRESOLVABLE_REASONS},
        )
        self.assertEqual(set(q["transitive"]), _TRANSITIVE_KEYS)   # typed transitive wrapper, closed shape
        trans_edges = q["transitive"]["edges"] if q["transitive"] else []
        self._assert_edges_shape(q["direct_edges"]["out"] + q["direct_edges"]["in"] + trans_edges)

    def test_resolve_output_closed_shape(self):
        oid, dg = _commit(self.aw, "a.md", "x\n")
        ref = _ref("repoA", oid, dg)
        core.publish(self.home, "home/collection", ref, [], home.read_head(self.home))
        out = core.resolve(self.home, ref)
        self.assertLessEqual(set(out), {"artifact_ref", "bytes", "resolution_receipt"})
        self.assertNotIn("edges", out)

    def test_unresolvable_change_fact_uses_typed_payload(self):
        ref = _ref("repoA", "a" * 40, "b" * 64)
        fact = core.change_fact(self.home, ref)
        self.assertEqual(set(fact), _CHANGE_FACT_KEYS)
        self._assert_resolvability_shape(fact["resolvability"])
        self.assertEqual(fact["supersedes_in_edges"], [])


if __name__ == "__main__":
    unittest.main()
