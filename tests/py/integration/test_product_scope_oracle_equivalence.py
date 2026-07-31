"""The production activation module must agree with the frozen consumer-contract oracle.

tests/py/e2e/test_consumer_contract_checkpoint.py is frozen: its blob hash
(7fefb2b5dcc1be515232dc0beff4356d441fe3c0, plan D06) is the evidence that the code was
made to meet the contract rather than the contract edited to match the code. So the
oracle keeps its own inline harness and is never modified.

That leaves two implementations of one protocol on purpose. This test is what makes
the duplication safe: it drives both against the same inputs and asserts identical
observable behavior, so production cannot drift from the frozen witness silently.
"""

import importlib
import os
import shutil
import subprocess
import tempfile
import unittest

from foundation import core, home
from productscope import activation, errors

_oracle = importlib.import_module("tests.py.e2e.test_consumer_contract_checkpoint")


def _make_repo(prefix):
    work = tempfile.mkdtemp(prefix=prefix)
    subprocess.run(["git", "init", "-q", work], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key, value in (("user.name", "t"), ("user.email", "t@e")):
        subprocess.run(["git", "-C", work, "config", key, value], check=True)
    return work


class OracleEquivalence(unittest.TestCase):
    def setUp(self):
        self.home_work = _make_repo("eq-home-")
        self.foundation = os.path.join(self.home_work, ".git")
        self.repo_work = _make_repo("eq-repo-")
        self.repo_git = os.path.join(self.repo_work, ".git")
        for path in (self.home_work, self.repo_work):
            self.addCleanup(shutil.rmtree, path, ignore_errors=True)
        core.register(self.foundation, "repoA", self.repo_git, home.read_head(self.foundation))

    def _publish(self, rel, content):
        oid, digest = _oracle._commit_file(self.repo_work, rel, content)
        ref = {"repo_id": "repoA", "commit_oid": oid, "path": rel,
               "digest": digest, "artifact_kind": "accepted-scope-delta"}
        core.publish(self.foundation, "repoA/home", ref, [], home.read_head(self.foundation))
        return ref

    def _fresh_scope(self, prefix):
        work = _make_repo(prefix)
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        return os.path.join(work, ".git")

    def test_oracle_blob_is_unmodified(self):
        """If this fails, the frozen witness was edited and the D06 evidence is void."""
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
        blob = subprocess.run(
            ["git", "hash-object", "tests/py/e2e/test_consumer_contract_checkpoint.py"],
            cwd=repo_root, stdout=subprocess.PIPE, check=True,
        ).stdout.decode().strip()
        self.assertEqual(blob, "7fefb2b5dcc1be515232dc0beff4356d441fe3c0")

    def test_activation_and_replay_match_the_oracle(self):
        ref = self._publish("delta-1.json", '{"delta":1}')
        prod_git = self._fresh_scope("eq-prod-")
        oracle_git = self._fresh_scope("eq-oracle-")
        oracle = _oracle._ProductScopeHome(oracle_git, self.foundation)

        prod_first = activation.activate(prod_git, self.foundation, ref, None)
        oracle_first = oracle.activate(ref, None)
        # Receipts are the observable contract; commit OIDs differ by repo identity.
        for field in ("candidate_ref", "parent_revision", "kind"):
            self.assertEqual(prod_first[field], oracle_first[field])

        prod_again = activation.activate(prod_git, self.foundation, ref, None)
        oracle_again = oracle.activate(ref, None)
        self.assertEqual(prod_again["scope_revision"], prod_first["scope_revision"])
        self.assertEqual(oracle_again["scope_revision"], oracle_first["scope_revision"])
        self.assertEqual(len(activation.lineage(prod_git)), 1)

    def test_chained_activation_matches_the_oracle(self):
        """A second delta activated onto an existing revision.

        This exercises the `-p parent` commit and the `update-ref <new> <parent>` CAS,
        a different code path from genesis (`-p` absent, expected-old all-zeros). Only
        genesis was bound before, so the two implementations could have disagreed here
        without any test noticing.
        """
        first_ref = self._publish("delta-1.json", '{"delta":1}')
        second_ref = self._publish("delta-2.json", '{"delta":2}')
        prod_git = self._fresh_scope("eq-chain-prod-")
        oracle_git = self._fresh_scope("eq-chain-oracle-")
        oracle = _oracle._ProductScopeHome(oracle_git, self.foundation)

        prod_first = activation.activate(prod_git, self.foundation, first_ref, None)
        oracle_first = oracle.activate(first_ref, None)

        prod_second = activation.activate(
            prod_git, self.foundation, second_ref, prod_first["scope_revision"])
        oracle_second = oracle.activate(second_ref, oracle_first["scope_revision"])

        for field in ("candidate_ref", "kind"):
            self.assertEqual(prod_second[field], oracle_second[field], field)
        # Each chained onto its own first revision, and advanced the head.
        self.assertEqual(prod_second["parent_revision"], prod_first["scope_revision"])
        self.assertEqual(oracle_second["parent_revision"], oracle_first["scope_revision"])
        self.assertEqual(activation.head(prod_git), prod_second["scope_revision"])
        self.assertEqual(len(activation.lineage(prod_git)), 2)
        # Replay of the chained activation is idempotent in both.
        self.assertEqual(
            activation.activate(prod_git, self.foundation, second_ref,
                                prod_first["scope_revision"])["scope_revision"],
            prod_second["scope_revision"])
        self.assertEqual(
            oracle.activate(second_ref, oracle_first["scope_revision"])["scope_revision"],
            oracle_second["scope_revision"])

    def test_unpublished_candidate_is_refused_by_both(self):
        """Both must refuse at the same point. The exception TYPE differs by design --
        the oracle lets Foundation's Unresolvable propagate, production wraps it as a
        typed ProductScopeError -- so what is asserted is WHEN they fail and that
        neither wrote a revision."""
        oid, digest = _oracle._commit_file(self.repo_work, "never.json", '{"d":9}')
        ghost = {"repo_id": "repoA", "commit_oid": oid, "path": "never.json",
                 "digest": digest, "artifact_kind": "accepted-scope-delta"}
        prod_git = self._fresh_scope("eq-ghost-prod-")
        oracle_git = self._fresh_scope("eq-ghost-oracle-")
        oracle = _oracle._ProductScopeHome(oracle_git, self.foundation)

        with self.assertRaises(errors.ProductScopeError) as caught:
            activation.activate(prod_git, self.foundation, ghost, None)
        self.assertEqual(caught.exception.code, errors.UNPUBLISHED_CANDIDATE)
        with self.assertRaises(Exception):
            oracle.activate(ghost, None)

        # Neither created a revision.
        self.assertIsNone(activation.head(prod_git))
        self.assertIsNone(oracle.head())

    def test_ref_name_and_receipt_path_match_the_oracle(self):
        """The two implementations must agree on WHERE state lives.

        A rename on either side would leave both internally consistent and every other
        test green, while the production module and the frozen witness silently stopped
        describing the same repository.
        """
        self.assertEqual(activation.SCOPE_REF, _oracle._ProductScopeHome.REF)
        self.assertEqual(activation.RECEIPT_PATH, "activation.json")
        # Prove it is the path actually used, not just a matching constant: activate
        # through production, then read the receipt the way the ORACLE reads it.
        ref = self._publish("delta-loc.json", '{"delta":"loc"}')
        prod_git = self._fresh_scope("eq-loc-prod-")
        result = activation.activate(prod_git, self.foundation, ref, None)
        blob = subprocess.run(
            ["git", "--git-dir", prod_git, "cat-file", "blob",
             "%s:activation.json" % result["scope_revision"]],
            stdout=subprocess.PIPE, check=True).stdout.decode()
        import json as _json
        self.assertEqual(_json.loads(blob)["candidate_ref"], ref)

    def test_stale_parent_fails_closed_in_both(self):
        ref = self._publish("delta-1.json", '{"delta":1}')
        stale = self._publish("delta-2.json", '{"delta":2}')
        prod_git = self._fresh_scope("eq-prod2-")
        oracle_git = self._fresh_scope("eq-oracle2-")
        oracle = _oracle._ProductScopeHome(oracle_git, self.foundation)

        activation.activate(prod_git, self.foundation, ref, None)
        oracle.activate(ref, None)
        prod_head = activation.head(prod_git)

        with self.assertRaises(errors.NeedsRebase):
            activation.activate(prod_git, self.foundation, stale, None)
        with self.assertRaises(_oracle._NeedsRebase):
            oracle.activate(stale, None)

        self.assertEqual(activation.head(prod_git), prod_head)


if __name__ == "__main__":
    unittest.main()
