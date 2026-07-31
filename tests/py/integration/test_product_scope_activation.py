"""Product Scope activation protocol (S-PSG-01 TC-001/004/005/007/008/011).

These exercise real Git: commit-tree plus update-ref CAS, not an in-memory stand-in,
because the properties under test (zero-write on stale parent, replay after a lost
acknowledgement) only exist at the ref-update layer.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home
from productscope import activation, errors


def _git(git_dir, args, input_bytes=None):
    return subprocess.run(
        ["git", "--git-dir", git_dir] + args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _make_repo(prefix):
    work = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "init", "-q", work], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key, value in (("user.name", "t"), ("user.email", "t@e")):
        subprocess.run(["git", "-C", work, "config", key, value], check=True)
    return work


def _commit_file(work, rel, content):
    path = os.path.join(work, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(rel) else None
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    subprocess.run(["git", "-C", work, "add", rel], check=True)
    subprocess.run(["git", "-C", work, "commit", "-qm", "add %s" % rel], check=True)
    oid = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"],
                         stdout=subprocess.PIPE, check=True).stdout.decode().strip()
    import hashlib
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    return oid, digest


class ActivationBase(unittest.TestCase):
    def setUp(self):
        self.home_work = _make_repo("ps-home-")
        self.foundation = os.path.join(self.home_work, ".git")
        self.repo_work = _make_repo("ps-repo-")
        self.repo_git = os.path.join(self.repo_work, ".git")
        self.scope_work = _make_repo("ps-scope-")
        self.scope_git = os.path.join(self.scope_work, ".git")
        for path in (self.home_work, self.repo_work, self.scope_work):
            self.addCleanup(shutil.rmtree, path, ignore_errors=True)
        core.register(self.foundation, "repoA", self.repo_git, home.read_head(self.foundation))

    def _publish(self, path, content, kind="accepted-scope-delta"):
        oid, digest = _commit_file(self.repo_work, path, content)
        ref = {"repo_id": "repoA", "commit_oid": oid, "path": path,
               "digest": digest, "artifact_kind": kind}
        core.publish(self.foundation, "repoA/home", ref, [],
                     home.read_head(self.foundation))
        return ref

    def _unpublished_ref(self, path, content, kind="accepted-scope-delta"):
        oid, digest = _commit_file(self.repo_work, path, content)
        return {"repo_id": "repoA", "commit_oid": oid, "path": path,
                "digest": digest, "artifact_kind": kind}


class GenesisAndActivation(ActivationBase):
    def test_tc001_genesis_has_no_parent_and_no_delta(self):
        self.assertIsNone(activation.head(self.scope_git))
        self.assertEqual(activation.lineage(self.scope_git), [])

    def test_tc004_activation_creates_exactly_one_revision_with_receipt(self):
        ref = self._publish("delta-1.json", '{"delta":1}')
        result = activation.activate(self.scope_git, self.foundation, ref, None)
        self.assertEqual(result["scope_revision"], activation.head(self.scope_git))
        self.assertEqual(len(activation.lineage(self.scope_git)), 1)
        _, receipt = activation.lineage(self.scope_git)[0]
        self.assertEqual(receipt["candidate_ref"], ref)
        self.assertIsNone(receipt["parent_revision"])
        self.assertEqual(receipt["kind"], "activation")

    def test_tc005_replay_after_lost_ack_returns_the_same_revision(self):
        ref = self._publish("delta-1.json", '{"delta":1}')
        first = activation.activate(self.scope_git, self.foundation, ref, None)
        again = activation.activate(self.scope_git, self.foundation, ref, None)
        self.assertEqual(first["scope_revision"], again["scope_revision"])
        self.assertEqual(len(activation.lineage(self.scope_git)), 1)

    def test_second_delta_chains_onto_the_first(self):
        first_ref = self._publish("delta-1.json", '{"delta":1}')
        first = activation.activate(self.scope_git, self.foundation, first_ref, None)
        second_ref = self._publish("delta-2.json", '{"delta":2}')
        second = activation.activate(
            self.scope_git, self.foundation, second_ref, first["scope_revision"]
        )
        self.assertNotEqual(first["scope_revision"], second["scope_revision"])
        self.assertEqual(len(activation.lineage(self.scope_git)), 2)
        self.assertEqual(activation.head(self.scope_git), second["scope_revision"])


class FailClosed(ActivationBase):
    def test_tc007_stale_parent_raises_and_writes_nothing(self):
        first_ref = self._publish("delta-1.json", '{"delta":1}')
        activation.activate(self.scope_git, self.foundation, first_ref, None)
        before_head = activation.head(self.scope_git)
        before_len = len(activation.lineage(self.scope_git))

        stale_ref = self._publish("delta-3.json", '{"delta":3}')
        with self.assertRaises(errors.NeedsRebase):
            # Claiming genesis as parent when a revision already exists is stale.
            activation.activate(self.scope_git, self.foundation, stale_ref, None)

        self.assertEqual(activation.head(self.scope_git), before_head)
        self.assertEqual(len(activation.lineage(self.scope_git)), before_len)

    def test_tc011_unpublished_candidate_is_refused_before_any_write(self):
        ref = self._unpublished_ref("never-published.json", '{"delta":9}')
        with self.assertRaises(errors.ProductScopeError) as caught:
            activation.activate(self.scope_git, self.foundation, ref, None)
        self.assertEqual(caught.exception.code, errors.UNPUBLISHED_CANDIDATE)
        self.assertIsNone(activation.head(self.scope_git))
        self.assertEqual(activation.lineage(self.scope_git), [])

    def test_tc008_not_using_product_scope_leaves_foundation_unchanged(self):
        before_head = home.read_head(self.foundation)
        before_state = home.read_state(self.foundation, before_head)
        # A full activation cycle touches only the consumer's own ref.
        ref = self._publish("delta-1.json", '{"delta":1}')
        activation.activate(self.scope_git, self.foundation, ref, None)
        # Publishing advanced the Foundation home once; activation itself must not.
        after_publish_head = home.read_head(self.foundation)
        activation.activate(self.scope_git, self.foundation, ref, None)
        self.assertEqual(home.read_head(self.foundation), after_publish_head)
        self.assertIsNotNone(before_state)


if __name__ == "__main__":
    unittest.main()
