"""T07/T02 — consumer-contract checkpoint, RED-first against the APPROVED contract.

Spec: cross-repo-artifact-foundation/spec.md v1.1.0 (owner re-Gate-2 approved
2026-07-23) + qa-plan TC-B02/B03/B06, ADV-12/13, and I07 EC01/EC02/V02.

RED-first (plan D01/D06, sequence exception): these fixtures are written against
the approved contract, NOT the current implementation. Run against the CURRENT
(un-remediated) foundation/ they are expected to FAIL for specific missing-behavior
reasons — that failure is the frozen RED evidence. T03–T06 then make them GREEN
WITHOUT modifying this oracle (fixture blob hash is recorded at freeze time).

The Product Scope activation model here is REAL Git (a consumer-owned home ref,
activation = a commit, CAS = `update-ref` old-value, ack-loss replay = walking the
commit lineage for the receipt) — not an in-memory dict. It exercises the Foundation
only through publish/resolve, proving a consumer can own activation while the
Foundation does not.

Expected-RED against current code (documented, discriminating):
- FoundationContractGaps.test_query_returns_home_revision   → current query has no home_revision (#6)
- FoundationContractGaps.test_transitive_supersedes_successor_closure → current transitive(X) == [] (#4/TC-B06)
- FoundationContractGaps.test_publish_poisoned_envelope_no_false_replay → current false-replays (#3/ADV-21-family)
- FoundationContractGaps.test_query_on_unresolvable_home_fails_closed → current returns empty (#5)
The consumer-activation / orchestration-bind tests freeze the positive contract
(already satisfiable by publish/resolve) and should stay GREEN throughout.
"""

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, errors, home, schema


_ENV = {
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@e",
    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@e",
}


def _git(git_dir, args, input_bytes=None):
    env = dict(os.environ); env.update(_ENV)
    return subprocess.run(["git", "--git-dir", git_dir, *args],
                          input=input_bytes, capture_output=True, env=env)


def _make_repo(prefix):
    d = tempfile.mkdtemp(prefix=prefix)
    for a in (["init", "-q"], ["config", "user.email", "t@e"], ["config", "user.name", "t"]):
        subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
    return d


def _commit_file(work, rel, content):
    with open(os.path.join(work, rel), "w", encoding="utf-8") as fh:
        fh.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True, capture_output=True)
    subprocess.run(["git", "-C", work, "commit", "-q", "-m", "x"], check=True, capture_output=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"], check=True,
                         capture_output=True, text=True).stdout.strip()
    return oid, hashlib.sha256(content.encode()).hexdigest()


class _NeedsRebase(Exception):
    """Consumer activation CAS lost (stale parent) — zero-write."""


class _ProductScopeHome:
    """Real-git model of Product Scope's CONSUMER-OWNED activation home (4b
    brainstorm L135-137, ADR-002/006). Activation is a commit on a dedicated ref;
    CAS via `update-ref` old-value; the activation receipt is a blob in the commit
    tree; ack-loss replay walks the commit lineage. Idempotency key =
    {candidate_artifact_ref, parent_scope_revision} — distinct from the Foundation
    envelope-digest publish key. Uses the Foundation ONLY via resolve (the EC01 gate).
    """

    REF = "refs/product-scope/head"

    def __init__(self, git_dir, foundation_home):
        self.git_dir = git_dir
        self.foundation = foundation_home

    def head(self):
        p = _git(self.git_dir, ["rev-parse", "--verify", "-q", self.REF])
        return (p.stdout.decode().strip() or None) if p.returncode == 0 else None

    def _lineage_receipts(self):
        p = _git(self.git_dir, ["rev-list", self.REF])
        if p.returncode != 0:
            return []
        out = []
        for commit in p.stdout.decode().split():
            b = _git(self.git_dir, ["cat-file", "blob", "%s:activation.json" % commit])
            if b.returncode == 0:
                out.append((commit, json.loads(b.stdout.decode())))
        return out

    def activate(self, candidate_ref, parent_revision):
        # EC01: an active revision must never reference an unpublished candidate.
        # The Foundation's resolve is the consumer's gate (raises Unresolvable).
        core.resolve(self.foundation, candidate_ref)
        key = (schema.canonical_json(candidate_ref), parent_revision)
        # ack-loss replay: retry finds the receipt in the lineage → SAME revision.
        for commit, rc in self._lineage_receipts():
            if (schema.canonical_json(rc["candidate_ref"]), rc["parent_revision"]) == key:
                return {"scope_revision": commit, **rc}
        receipt = {"candidate_ref": candidate_ref, "parent_revision": parent_revision, "kind": "activation"}
        blob = _git(self.git_dir, ["hash-object", "-w", "--stdin"],
                    input_bytes=schema.canonical_json(receipt).encode()).stdout.decode().strip()
        tree = _git(self.git_dir, ["mktree"],
                    input_bytes=("100644 blob %s\tactivation.json\n" % blob).encode()).stdout.decode().strip()
        args = ["commit-tree", tree, "-m", "activate"]
        if parent_revision is not None:
            args += ["-p", parent_revision]
        new = _git(self.git_dir, args).stdout.decode().strip()
        old = parent_revision if parent_revision is not None else "0" * 40
        if _git(self.git_dir, ["update-ref", self.REF, new, old]).returncode != 0:
            raise _NeedsRebase()  # stale parent → zero-write
        return {"scope_revision": new, **receipt}


class _Base(unittest.TestCase):
    def setUp(self):
        self.hw = _make_repo("cc-home-")
        self.home = os.path.join(self.hw, ".git")
        self.rw = _make_repo("cc-repo-")
        self.rgit = os.path.join(self.rw, ".git")
        self.cw = _make_repo("cc-ps-")           # product-scope consumer home
        self.cgit = os.path.join(self.cw, ".git")
        for d in (self.hw, self.rw, self.cw):
            self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        core.register(self.home, "repoA", self.rgit, home.read_head(self.home))

    def _ref(self, oid, dg, path, kind):
        return {"repo_id": "repoA", "commit_oid": oid, "path": path, "digest": dg, "artifact_kind": kind}

    def _publish(self, path, content, kind, relations=None):
        oid, dg = _commit_file(self.rw, path, content)
        ref = self._ref(oid, dg, path, kind)
        core.publish(self.home, "repoA/home", ref, relations or [], home.read_head(self.home))
        return ref


class ProductScopeActivationContract(_Base):
    """4b: consumer publishes a candidate Ref via Foundation, then owns the
    activation (real Git commit + parent CAS + lineage receipt)."""

    def test_publish_candidate_then_activate_creates_real_scope_revision(self):
        ref = self._publish("delta-1.json", '{"d":1}\n', "scope-delta")
        ps = _ProductScopeHome(self.cgit, self.home)
        r1 = ps.activate(ref, None)                       # genesis
        self.assertEqual(ps.head(), r1["scope_revision"])  # real commit on the ref
        # receipt is a real blob in the activation commit's tree
        blob = _git(self.cgit, ["cat-file", "blob", "%s:activation.json" % r1["scope_revision"]])
        self.assertEqual(blob.returncode, 0)

    def test_activation_ack_loss_replays_same_revision_via_git_lineage(self):
        ref = self._publish("delta-2.json", '{"d":2}\n', "scope-delta")
        ps = _ProductScopeHome(self.cgit, self.home)
        first = ps.activate(ref, None)
        replay = ps.activate(ref, None)                   # ack-loss retry, same key
        self.assertEqual(first["scope_revision"], replay["scope_revision"])
        # exactly one activation commit exists (no second write)
        n = _git(self.cgit, ["rev-list", "--count", _ProductScopeHome.REF]).stdout.decode().strip()
        self.assertEqual(n, "1")

    def test_active_revision_cannot_reference_unpublished_candidate(self):
        ps = _ProductScopeHome(self.cgit, self.home)
        oid, dg = _commit_file(self.rw, "delta-3.json", '{"d":3}\n')   # committed but NOT published
        unpublished = self._ref(oid, dg, "delta-3.json", "scope-delta")
        with self.assertRaises(errors.Unresolvable):
            ps.activate(unpublished, None)
        self.assertIsNone(ps.head())                      # zero-write

    def test_activation_cas_conflict_is_zero_write(self):
        a = self._publish("delta-a.json", '{"a":1}\n', "scope-delta")
        b = self._publish("delta-b.json", '{"b":1}\n', "scope-delta")
        ps = _ProductScopeHome(self.cgit, self.home)
        r1 = ps.activate(a, None)                          # genesis → head=r1
        # second writer still thinks parent is genesis-None (stale) → CAS conflict
        with self.assertRaises(_NeedsRebase):
            ps.activate(b, None)
        self.assertEqual(ps.head(), r1["scope_revision"])  # zero-write


class OrchestrationContract(_Base):
    """4a: bind Refs via resolver, read Foundation facts, derive currentness itself."""

    def test_bind_ref_reads_committed_git_not_worktree(self):
        ref = self._publish("artifact.md", "bound\n", "spec")
        with open(os.path.join(self.rw, "artifact.md"), "w", encoding="utf-8") as fh:
            fh.write("DIRTY\n")
        self.assertEqual(core.resolve(self.home, ref)["bytes"], b"bound\n")

    def test_change_fact_returns_facts_only_no_verdict(self):
        base = self._publish("v1.md", "v1\n", "spec")
        self._publish("v2.md", "v2\n", "spec",
                      relations=[{"kind": "supersedes-artifact", "object": base}])
        fact = core.change_fact(self.home, base)
        forbidden = {"current", "stale", "impact", "approval", "SUPERSEDED", "superseded", "verdict"}
        self.assertTrue(forbidden.isdisjoint(fact.keys()))
        self.assertEqual(len(fact["supersedes_in_edges"]), 1)

    def test_change_fact_carries_no_home_revision(self):
        # Fix 2: only query returns home_revision; change-fact contract is unchanged.
        ref = self._publish("t.md", "t\n", "spec")
        self.assertNotIn("home_revision", core.change_fact(self.home, ref))


class FoundationContractGaps(_Base):
    """Foundation contract points the consumers depend on. Against the CURRENT
    implementation these are the frozen RED evidence (see module docstring)."""

    def test_query_returns_home_revision(self):
        # spec v1.1.0: query returns home_revision = captured authoritative Home head.
        ref = self._publish("q.md", "q\n", "spec")
        result = core.query(self.home, ref)
        self.assertIn("home_revision", result)                      # RED: current lacks it
        self.assertEqual(result["home_revision"], home.read_head(self.home))

    def test_transitive_supersedes_successor_closure(self):
        # TC-B06 (#4): X superseded by Y and Z (Z supersedes Y) → transitive from X
        # returns the full successor set {Y, Z}, never a single "current".
        x = self._publish("x.md", "x\n", "spec")
        y = self._publish("y.md", "y\n", "spec",
                          relations=[{"kind": "supersedes-artifact", "object": x}])
        self._publish("z.md", "z\n", "spec",
                      relations=[{"kind": "supersedes-artifact", "object": y}])
        trans = core.query(self.home, x, kind="supersedes-artifact")["transitive"]
        subjects = {e["subject"]["path"] for e in (trans.get("edges", []) if isinstance(trans, dict) else trans)}
        self.assertEqual(subjects, {"y.md", "z.md"})               # RED: current returns set()

    def test_publish_poisoned_envelope_no_false_replay(self):
        # #3 integrity: a planted envelope file (right name, junk content) for an
        # UNREGISTERED repo must not be honored as a replay.
        ghost = {"repo_id": "ghost", "commit_oid": "a" * 40, "path": "x.md",
                 "digest": "b" * 64, "artifact_kind": "spec"}
        digest = schema.envelope_digest("repoA/home", ghost, [])
        home.commit_entries(self.home, home.read_head(self.home),
                            {"envelope-%s.json" % digest: b"{}"})     # poison
        with self.assertRaises(errors.FoundationError):               # RED: current returns replay=True
            core.publish(self.home, "repoA/home", ghost, [], home.read_head(self.home))

    def test_query_on_unresolvable_home_fails_closed(self):
        # #5: an unresolvable home must fail closed (HOME_ERROR), not read as empty.
        ref = self._ref("a" * 40, "b" * 64, "x.md", "spec")
        with self.assertRaises(errors.FoundationError):               # RED: current returns empty edges
            core.query("/nonexistent/not/a/git/dir", ref)

    def test_home_locator_rejects_global_absolute_path_identity(self):
        # #2 / TC-B01: home identity must be a stable repo_id + repo-relative path;
        # a hardcoded global/absolute path is NOT a valid identity and must be rejected.
        from foundation import homelocator
        cfg = os.path.join(self.cw, "artifact-home.json")
        with open(cfg, "w", encoding="utf-8") as fh:
            json.dump({"home_git_dir": self.home}, fh)                # absolute/global path — forbidden identity
        with self.assertRaises(errors.FoundationError):               # RED: current ACCEPTS absolute home_git_dir
            homelocator.resolve_home(cfg)


if __name__ == "__main__":
    unittest.main()
